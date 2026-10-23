// Mutating admission webhook that splits a Deployment's pods into
// base (on-demand) and burst (spot) roles. See DESIGN.md.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type admissionRequest struct {
	UID       string          `json:"uid"`
	Namespace string          `json:"namespace"`
	Operation string          `json:"operation"`
	DryRun    *bool           `json:"dryRun,omitempty"`
	Object    json.RawMessage `json:"object"`
}

type admissionResponse struct {
	UID       string  `json:"uid"`
	Allowed   bool    `json:"allowed"`
	PatchType *string `json:"patchType,omitempty"`
	Patch     []byte  `json:"patch,omitempty"`
	Result    *struct {
		Message string `json:"message"`
	} `json:"status,omitempty"`
}

type admissionReview struct {
	APIVersion string             `json:"apiVersion"`
	Kind       string             `json:"kind"`
	Request    *admissionRequest  `json:"request,omitempty"`
	Response   *admissionResponse `json:"response,omitempty"`
}

type handler struct {
	decider  *Decider
	opt      PatchOptions
	// failOpen admits the pod unmodified when the decision cannot be made (API lookup error).
	// The lab ran fail-closed (failurePolicy Fail, deny on error) so that no pod could carry an
	// unknown role and contaminate the experiment. In production the webhook runs as a single
	// replica (in-memory state, see DESIGN.md), so fail-closed would block pod creation in opted-in
	// workloads whenever it is unavailable. The pod template carries the burst defaults instead.
	failOpen bool
}

func (h *handler) review(ctx context.Context, req *admissionRequest) *admissionResponse {
	resp := &admissionResponse{UID: req.UID, Allowed: true}
	if req.Operation != "CREATE" {
		return resp
	}
	var pod Pod
	if err := json.Unmarshal(req.Object, &pod); err != nil {
		return h.fail(resp, fmt.Sprintf("decode pod: %v", err))
	}
	dryRun := req.DryRun != nil && *req.DryRun

	dec, err := h.decider.Decide(ctx, req.Namespace, &pod, dryRun)
	if err != nil {
		return h.fail(resp, fmt.Sprintf("ns=%s gen=%s: %v", req.Namespace, pod.Metadata.GenerateName, err))
	}
	if dec == nil {
		return resp
	}
	patch, err := json.Marshal(BuildPatch(&pod, dec, h.opt))
	if err != nil {
		return h.fail(resp, fmt.Sprintf("marshal patch: %v", err))
	}
	pt := "JSONPatch"
	resp.PatchType = &pt
	resp.Patch = patch
	log.Printf("decide ns=%s rs=%s role=%s visible_base=%d inflight_base=%d min=%d dry_run=%t id=%s",
		req.Namespace, dec.ReplicaSet, dec.Role, dec.VisibleBase, dec.InflightBase, dec.MinBase, dryRun, dec.ID)
	return resp
}

// fail handles any error before a patch is returned: admit unmodified when failOpen, else deny.
func (h *handler) fail(resp *admissionResponse, msg string) *admissionResponse {
	if h.failOpen {
		log.Printf("allow-unmodified %s", msg)
		return resp
	}
	log.Printf("deny %s", msg)
	return deny(resp, msg)
}

func deny(resp *admissionResponse, msg string) *admissionResponse {
	resp.Allowed = false
	resp.Result = &struct {
		Message string `json:"message"`
	}{Message: "capacity-split: " + msg}
	return resp
}

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var rev admissionReview
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20)).Decode(&rev); err != nil || rev.Request == nil {
		http.Error(w, "bad admission review", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	out := admissionReview{
		APIVersion: "admission.k8s.io/v1",
		Kind:       "AdmissionReview",
		Response:   h.review(ctx, rev.Request),
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(out)
}

func main() {
	cluster, err := newInClusterCluster()
	if err != nil {
		log.Fatalf("cluster client: %v", err)
	}
	h := &handler{
		decider:  NewDecider(cluster, 15*time.Second),
		opt:      PatchOptions{TopologySpread: os.Getenv("ENABLE_TOPOLOGY_SPREAD") == "true"},
		failOpen: os.Getenv("FAIL_OPEN") == "true",
	}
	log.Printf("starting topology_spread=%t fail_open=%t", h.opt.TopologySpread, h.failOpen)

	mux := http.NewServeMux()
	mux.Handle("POST /mutate", h)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })

	srv := &http.Server{Addr: ":9443", Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := srv.ListenAndServeTLS("/certs/tls.crt", "/certs/tls.key"); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
	<-sig
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
}
