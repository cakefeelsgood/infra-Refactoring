package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func applyPaths(ops []patchOp) map[string]any {
	m := map[string]any{}
	for _, o := range ops {
		m[o.Path] = o.Value
	}
	return m
}

func TestBasePatchOnPlainPod(t *testing.T) {
	p := newPod("rs1")
	ops := BuildPatch(&p, &Decision{Role: RoleBase, ID: "abc"}, PatchOptions{})
	m := applyPaths(ops)
	if m["/metadata/labels/capacity-role"] != RoleBase {
		t.Fatalf("label missing: %v", m)
	}
	anns, _ := m["/metadata/annotations"].(map[string]string)
	if anns[AnnDeletionCost] != "1000" || anns[AnnDecisionID] != "abc" {
		t.Fatalf("annotations: %v", anns)
	}
	b, _ := json.Marshal(m["/spec/affinity"])
	if !strings.Contains(string(b), `"requiredDuringSchedulingIgnoredDuringExecution"`) || !strings.Contains(string(b), `"on-demand"`) {
		t.Fatalf("affinity: %s", b)
	}
	if _, ok := m["/spec/topologySpreadConstraints"]; ok {
		t.Fatal("topology spread must be off by default")
	}
}

func TestBurstPatchAppendsToExisting(t *testing.T) {
	p := newPod("rs1")
	p.Metadata.Annotations = map[string]string{"x": "y"}
	p.Spec.Tolerations = []json.RawMessage{json.RawMessage(`{"key":"a","operator":"Exists"}`)}
	p.Spec.Affinity = &Affinity{NodeAffinity: &NodeAffinity{Preferred: []json.RawMessage{json.RawMessage(`{}`)}}}
	ops := BuildPatch(&p, &Decision{Role: RoleBurst, ID: "id1"}, PatchOptions{TopologySpread: true})
	m := applyPaths(ops)
	if m["/metadata/annotations/controller.kubernetes.io~1pod-deletion-cost"] != "-1000" {
		t.Fatalf("deletion cost: %v", m)
	}
	if _, ok := m["/spec/affinity/nodeAffinity/preferredDuringSchedulingIgnoredDuringExecution/-"]; !ok {
		t.Fatalf("preferred append missing: %v", m)
	}
	tol, _ := json.Marshal(m["/spec/tolerations/-"])
	if !strings.Contains(string(tol), `"value":"spot"`) {
		t.Fatalf("toleration: %s", tol)
	}
	ts, _ := json.Marshal(m["/spec/topologySpreadConstraints"])
	if !strings.Contains(string(ts), `"capacity-role":"burst"`) || !strings.Contains(string(ts), `"matchLabelKeys":["pod-template-hash"]`) ||
		!strings.Contains(string(ts), `"DoNotSchedule"`) || !strings.Contains(string(ts), `"ScheduleAnyway"`) {
		t.Fatalf("topology: %s", ts)
	}
}

func TestBaseRequiredANDedIntoEveryTerm(t *testing.T) {
	p := newPod("rs1")
	p.Spec.Affinity = &Affinity{NodeAffinity: &NodeAffinity{Required: &NodeSelector{NodeSelectorTerms: []NodeSelectorTerm{
		{MatchExpressions: []json.RawMessage{json.RawMessage(`{}`)}},
		{},
	}}}}
	m := applyPaths(BuildPatch(&p, &Decision{Role: RoleBase}, PatchOptions{}))
	base := "/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/"
	if _, ok := m[base+"0/matchExpressions/-"]; !ok {
		t.Fatalf("term 0 not appended: %v", m)
	}
	if _, ok := m[base+"1/matchExpressions"]; !ok {
		t.Fatalf("term 1 not created: %v", m)
	}
}
