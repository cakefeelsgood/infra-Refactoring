package main

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
)

func admissionFor(t *testing.T, p Pod) *admissionRequest {
	t.Helper()
	raw, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	return &admissionRequest{UID: "u1", Namespace: "moment-prod", Operation: "CREATE", Object: raw}
}

func TestReviewFailOpenAllowsUnmodifiedOnLookupError(t *testing.T) {
	h := &handler{decider: NewDecider(&fakeCluster{hpaErr: errors.New("boom")}, 0), failOpen: true}
	resp := h.review(context.Background(), admissionFor(t, newPod("rs1")))
	if !resp.Allowed || resp.Patch != nil || resp.PatchType != nil {
		t.Fatalf("fail-open: allowed=%t patch=%s, want allowed without patch", resp.Allowed, resp.Patch)
	}
}

func TestReviewFailClosedDeniesOnLookupError(t *testing.T) {
	h := &handler{decider: NewDecider(&fakeCluster{hpaErr: errors.New("boom")}, 0)}
	resp := h.review(context.Background(), admissionFor(t, newPod("rs1")))
	if resp.Allowed || resp.Result == nil {
		t.Fatalf("fail-closed: allowed=%t, want denied with message", resp.Allowed)
	}
}

func TestReviewPatchesBasePodWithMomentAnnotation(t *testing.T) {
	h := &handler{decider: NewDecider(&fakeCluster{minBase: 2}, 0), failOpen: true}
	resp := h.review(context.Background(), admissionFor(t, newPod("rs1")))
	if !resp.Allowed || resp.Patch == nil {
		t.Fatalf("allowed=%t patch=%s, want allowed with patch", resp.Allowed, resp.Patch)
	}
	var ops []patchOp
	if err := json.Unmarshal(resp.Patch, &ops); err != nil {
		t.Fatal(err)
	}
	m := applyPaths(ops)
	anns, _ := m["/metadata/annotations"].(map[string]any)
	if anns[AnnDeletionCost] != "1000" || anns["capacity-split.moment.io/decision-id"] == nil {
		t.Fatalf("annotations: %v", anns)
	}
}

func TestReviewFailOpenAllowsUndecodablePod(t *testing.T) {
	h := &handler{decider: NewDecider(&fakeCluster{minBase: 1}, 0), failOpen: true}
	resp := h.review(context.Background(), &admissionRequest{UID: "u2", Operation: "CREATE", Object: []byte(`"not-a-pod"`)})
	if !resp.Allowed || resp.Patch != nil {
		t.Fatalf("fail-open decode error: allowed=%t patch=%s, want allowed without patch", resp.Allowed, resp.Patch)
	}
}
