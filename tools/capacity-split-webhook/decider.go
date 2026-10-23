package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"sync"
	"time"
)

const (
	LabelRole       = "capacity-role"
	RoleBase        = "base"
	RoleBurst       = "burst"
	AnnDecisionID   = "capacity-split.moment.io/decision-id"
	AnnDeletionCost = "controller.kubernetes.io/pod-deletion-cost"
	LabelTemplate   = "pod-template-hash"
)

// Decision is the outcome for one admitted pod.
type Decision struct {
	Role         string
	ID           string // empty for dry-run
	ReplicaSet   string
	MinBase      int
	VisibleBase  int
	InflightBase int
}

type inflight struct {
	role    string
	expires time.Time
}

type rsState struct {
	mu       sync.Mutex
	inflight map[string]inflight
}

// Decider assigns base/burst per ReplicaSet. See DESIGN.md.
//
// Admissions for the same ReplicaSet are serialized. Each non-dry-run decision is
// remembered as "in flight" under a random decision id that is also written onto
// the pod as an annotation. Once a pod carrying that id is visible in a pod list,
// the in-flight entry is dropped and the pod is counted from the list instead.
// Entries that never become visible (pod rejected by a later admission stage)
// expire after ttl.
type Decider struct {
	cluster Cluster
	ttl     time.Duration
	now     func() time.Time

	mu     sync.Mutex
	states map[string]*rsState
}

func NewDecider(c Cluster, ttl time.Duration) *Decider {
	return &Decider{cluster: c, ttl: ttl, now: time.Now, states: map[string]*rsState{}}
}

func (d *Decider) state(rsUID string) *rsState {
	d.mu.Lock()
	defer d.mu.Unlock()
	s, ok := d.states[rsUID]
	if !ok {
		s = &rsState{inflight: map[string]inflight{}}
		d.states[rsUID] = s
	}
	return s
}

func controllerRef(refs []OwnerReference, kind string) *OwnerReference {
	for i := range refs {
		r := &refs[i]
		if r.Kind == kind && r.Controller != nil && *r.Controller {
			return r
		}
	}
	return nil
}

func newID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// Decide returns nil (no mutation) for pods not owned by a ReplicaSet.
func (d *Decider) Decide(ctx context.Context, ns string, pod *Pod, dryRun bool) (*Decision, error) {
	ref := controllerRef(pod.Metadata.OwnerReferences, "ReplicaSet")
	hash := pod.Metadata.Labels[LabelTemplate]
	if ref == nil || hash == "" {
		return nil, nil
	}

	rs, err := d.cluster.GetReplicaSet(ctx, ns, ref.Name)
	if err != nil {
		return nil, fmt.Errorf("get replicaset %s/%s: %w", ns, ref.Name, err)
	}
	minBase := 1
	if dep := controllerRef(rs.Metadata.OwnerReferences, "Deployment"); dep != nil {
		minBase, err = d.cluster.MinReplicasForDeployment(ctx, ns, dep.Name)
		if err != nil {
			return nil, fmt.Errorf("lookup hpa for deployment %s/%s: %w", ns, dep.Name, err)
		}
	}

	st := d.state(ref.UID)
	st.mu.Lock()
	defer st.mu.Unlock()

	pods, err := d.cluster.ListPods(ctx, ns, LabelTemplate+"="+hash)
	if err != nil {
		return nil, fmt.Errorf("list pods %s/%s: %w", ns, hash, err)
	}

	visibleIDs := map[string]bool{}
	visibleBase := 0
	for i := range pods {
		p := &pods[i]
		if id := p.Metadata.Annotations[AnnDecisionID]; id != "" {
			visibleIDs[id] = true
		}
		owner := controllerRef(p.Metadata.OwnerReferences, "ReplicaSet")
		if owner == nil || owner.UID != ref.UID {
			continue
		}
		if p.Metadata.DeletionTimestamp != nil || p.Status.Phase == "Failed" || p.Status.Phase == "Succeeded" {
			continue
		}
		if p.Metadata.Labels[LabelRole] == RoleBase {
			visibleBase++
		}
	}

	now := d.now()
	inflightBase := 0
	for id, e := range st.inflight {
		if visibleIDs[id] || now.After(e.expires) {
			delete(st.inflight, id)
			continue
		}
		if e.role == RoleBase {
			inflightBase++
		}
	}

	dec := &Decision{
		Role:         RoleBurst,
		ReplicaSet:   ref.Name,
		MinBase:      minBase,
		VisibleBase:  visibleBase,
		InflightBase: inflightBase,
	}
	if visibleBase+inflightBase < minBase {
		dec.Role = RoleBase
	}
	if !dryRun {
		dec.ID = newID()
		st.inflight[dec.ID] = inflight{role: dec.Role, expires: now.Add(d.ttl)}
	}
	return dec, nil
}
