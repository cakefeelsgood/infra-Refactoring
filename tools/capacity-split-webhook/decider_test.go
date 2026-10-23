package main

import (
	"context"
	"errors"
	"fmt"
	"math/rand/v2"
	"sync"
	"testing"
	"time"
)

// fakeCluster stores pods that become visible only after their "create" lands,
// mimicking the gap between admission and persistence.
type fakeCluster struct {
	mu       sync.Mutex
	pods     []Pod
	minBase  int
	hpaErr   error
	listWait time.Duration
}

func (f *fakeCluster) GetReplicaSet(_ context.Context, _, name string) (*ReplicaSet, error) {
	t := true
	return &ReplicaSet{Metadata: ObjectMeta{Name: name, UID: "uid-" + name,
		OwnerReferences: []OwnerReference{{Kind: "Deployment", Name: "web", Controller: &t}}}}, nil
}

func (f *fakeCluster) MinReplicasForDeployment(context.Context, string, string) (int, error) {
	if f.hpaErr != nil {
		return 0, f.hpaErr
	}
	return f.minBase, nil
}

func (f *fakeCluster) ListPods(_ context.Context, _, selector string) ([]Pod, error) {
	if f.listWait > 0 {
		time.Sleep(time.Duration(rand.Int64N(int64(f.listWait))))
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []Pod
	for _, p := range f.pods {
		if LabelTemplate+"="+p.Metadata.Labels[LabelTemplate] == selector {
			out = append(out, p)
		}
	}
	return out, nil
}

func (f *fakeCluster) persist(p Pod) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.pods = append(f.pods, p)
}

func newPod(rs string) Pod {
	t := true
	return Pod{Metadata: ObjectMeta{
		GenerateName:    rs + "-",
		Labels:          map[string]string{"app": "web", LabelTemplate: "hash-" + rs},
		OwnerReferences: []OwnerReference{{Kind: "ReplicaSet", Name: rs, UID: "uid-" + rs, Controller: &t}},
	}}
}

// admitAndPersist runs Decide and then, after a random delay, stores the mutated pod.
func admitAndPersist(t *testing.T, d *Decider, f *fakeCluster, rs string, maxDelay time.Duration) string {
	t.Helper()
	p := newPod(rs)
	dec, err := d.Decide(context.Background(), "app", &p, false)
	if err != nil {
		t.Errorf("decide: %v", err)
		return ""
	}
	if maxDelay > 0 {
		time.Sleep(time.Duration(rand.Int64N(int64(maxDelay))))
	}
	p.Metadata.Labels[LabelRole] = dec.Role
	p.Metadata.Annotations = map[string]string{AnnDecisionID: dec.ID}
	f.persist(p)
	return dec.Role
}

func countRoles(f *fakeCluster, rs string) (base, burst int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, p := range f.pods {
		if p.Metadata.OwnerReferences[0].Name != rs {
			continue
		}
		switch p.Metadata.Labels[LabelRole] {
		case RoleBase:
			base++
		case RoleBurst:
			burst++
		}
	}
	return
}

func TestConcurrent16Pods(t *testing.T) {
	for trial := 0; trial < 50; trial++ {
		f := &fakeCluster{minBase: 4, listWait: 2 * time.Millisecond}
		d := NewDecider(f, 15*time.Second)
		var wg sync.WaitGroup
		for i := 0; i < 16; i++ {
			wg.Add(1)
			go func() { defer wg.Done(); admitAndPersist(t, d, f, "rs1", 20*time.Millisecond) }()
		}
		wg.Wait()
		if base, burst := countRoles(f, "rs1"); base != 4 || burst != 12 {
			t.Fatalf("trial %d: base=%d burst=%d, want 4/12", trial, base, burst)
		}
	}
}

func TestRollingUpdateTwoReplicaSets(t *testing.T) {
	f := &fakeCluster{minBase: 4, listWait: time.Millisecond}
	d := NewDecider(f, 15*time.Second)
	var wg sync.WaitGroup
	for _, rs := range []string{"old", "new"} {
		for i := 0; i < 16; i++ {
			wg.Add(1)
			go func() { defer wg.Done(); admitAndPersist(t, d, f, rs, 10*time.Millisecond) }()
		}
	}
	wg.Wait()
	for _, rs := range []string{"old", "new"} {
		if base, burst := countRoles(f, rs); base != 4 || burst != 12 {
			t.Fatalf("%s: base=%d burst=%d, want 4/12", rs, base, burst)
		}
	}
}

func TestBaseReplacedAfterDeletion(t *testing.T) {
	f := &fakeCluster{minBase: 4}
	d := NewDecider(f, 15*time.Second)
	for i := 0; i < 6; i++ {
		admitAndPersist(t, d, f, "rs1", 0)
	}
	// Mark one base pod as terminating; the next pod must become base again.
	f.mu.Lock()
	ts := "2026-01-01T00:00:00Z"
	for i := range f.pods {
		if f.pods[i].Metadata.Labels[LabelRole] == RoleBase {
			f.pods[i].Metadata.DeletionTimestamp = &ts
			break
		}
	}
	f.mu.Unlock()
	if role := admitAndPersist(t, d, f, "rs1", 0); role != RoleBase {
		t.Fatalf("replacement role=%s, want base", role)
	}
}

func TestRejectedPodSelfHealsAfterTTL(t *testing.T) {
	f := &fakeCluster{minBase: 4}
	d := NewDecider(f, 15*time.Second)
	now := time.Unix(0, 0)
	d.now = func() time.Time { return now }

	for i := 0; i < 3; i++ {
		admitAndPersist(t, d, f, "rs1", 0)
	}
	// 4th pod is decided base but rejected by a later admission stage (never persisted).
	p := newPod("rs1")
	dec, _ := d.Decide(context.Background(), "app", &p, false)
	if dec.Role != RoleBase {
		t.Fatalf("4th role=%s, want base", dec.Role)
	}
	// Retry within TTL: phantom in-flight base still counted -> burst.
	p2 := newPod("rs1")
	if dec, _ := d.Decide(context.Background(), "app", &p2, false); dec.Role != RoleBurst {
		t.Fatalf("within ttl role=%s, want burst (documented limitation)", dec.Role)
	}
	// After TTL the phantom expires and the next pod is base again.
	now = now.Add(16 * time.Second)
	p3 := newPod("rs1")
	if dec, _ := d.Decide(context.Background(), "app", &p3, false); dec.Role != RoleBase {
		t.Fatalf("after ttl role=%s, want base", dec.Role)
	}
}

func TestDryRunDoesNotChangeState(t *testing.T) {
	f := &fakeCluster{minBase: 4}
	d := NewDecider(f, 15*time.Second)
	for i := 0; i < 10; i++ {
		p := newPod("rs1")
		dec, err := d.Decide(context.Background(), "app", &p, true)
		if err != nil || dec.Role != RoleBase || dec.ID != "" {
			t.Fatalf("dry run %d: dec=%+v err=%v", i, dec, err)
		}
	}
	if n := len(d.state("uid-rs1").inflight); n != 0 {
		t.Fatalf("inflight after dry runs = %d, want 0", n)
	}
}

func TestHPALookupFailureDenies(t *testing.T) {
	f := &fakeCluster{minBase: 4, hpaErr: errors.New("boom")}
	d := NewDecider(f, 15*time.Second)
	p := newPod("rs1")
	if _, err := d.Decide(context.Background(), "app", &p, false); err == nil {
		t.Fatal("want error when HPA lookup fails")
	}
}

func TestNoHPAMeansOneBase(t *testing.T) {
	f := &fakeCluster{minBase: 1}
	d := NewDecider(f, 15*time.Second)
	got := []string{}
	for i := 0; i < 3; i++ {
		got = append(got, admitAndPersist(t, d, f, "rs1", 0))
	}
	if fmt.Sprint(got) != "[base burst burst]" {
		t.Fatalf("roles=%v", got)
	}
}

func TestNonReplicaSetPodIgnored(t *testing.T) {
	d := NewDecider(&fakeCluster{minBase: 4}, time.Second)
	p := Pod{Metadata: ObjectMeta{Name: "bare", Labels: map[string]string{"a": "b"}}}
	if dec, err := d.Decide(context.Background(), "app", &p, false); dec != nil || err != nil {
		t.Fatalf("dec=%v err=%v", dec, err)
	}
}
