package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"
)

// Minimal Kubernetes object shapes; only the fields the webhook reads.

type OwnerReference struct {
	APIVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Name       string `json:"name"`
	UID        string `json:"uid"`
	Controller *bool  `json:"controller,omitempty"`
}

type ObjectMeta struct {
	Name              string            `json:"name,omitempty"`
	GenerateName      string            `json:"generateName,omitempty"`
	Namespace         string            `json:"namespace,omitempty"`
	UID               string            `json:"uid,omitempty"`
	Labels            map[string]string `json:"labels,omitempty"`
	Annotations       map[string]string `json:"annotations,omitempty"`
	OwnerReferences   []OwnerReference  `json:"ownerReferences,omitempty"`
	DeletionTimestamp *string           `json:"deletionTimestamp,omitempty"`
}

type NodeSelectorTerm struct {
	MatchExpressions []json.RawMessage `json:"matchExpressions,omitempty"`
	MatchFields      []json.RawMessage `json:"matchFields,omitempty"`
}

type NodeSelector struct {
	NodeSelectorTerms []NodeSelectorTerm `json:"nodeSelectorTerms"`
}

type NodeAffinity struct {
	Required  *NodeSelector     `json:"requiredDuringSchedulingIgnoredDuringExecution,omitempty"`
	Preferred []json.RawMessage `json:"preferredDuringSchedulingIgnoredDuringExecution,omitempty"`
}

type Affinity struct {
	NodeAffinity *NodeAffinity `json:"nodeAffinity,omitempty"`
}

type PodSpec struct {
	Affinity                  *Affinity         `json:"affinity,omitempty"`
	Tolerations               []json.RawMessage `json:"tolerations,omitempty"`
	TopologySpreadConstraints []json.RawMessage `json:"topologySpreadConstraints,omitempty"`
}

type Pod struct {
	Metadata ObjectMeta `json:"metadata"`
	Spec     PodSpec    `json:"spec"`
	Status   struct {
		Phase string `json:"phase,omitempty"`
	} `json:"status"`
}

type ReplicaSet struct {
	Metadata ObjectMeta `json:"metadata"`
}

type hpaList struct {
	Items []struct {
		Spec struct {
			ScaleTargetRef struct {
				Kind string `json:"kind"`
				Name string `json:"name"`
			} `json:"scaleTargetRef"`
			MinReplicas *int `json:"minReplicas"`
		} `json:"spec"`
	} `json:"items"`
}

type podList struct {
	Items []Pod `json:"items"`
}

// Cluster is the read-only API surface the decider needs.
type Cluster interface {
	GetReplicaSet(ctx context.Context, ns, name string) (*ReplicaSet, error)
	// MinReplicasForDeployment returns the minReplicas of the HPA that targets the
	// Deployment, or 1 when no HPA targets it.
	MinReplicasForDeployment(ctx context.Context, ns, name string) (int, error)
	ListPods(ctx context.Context, ns, labelSelector string) ([]Pod, error)
}

type restCluster struct {
	base   string
	client *http.Client
	token  string
}

const saDir = "/var/run/secrets/kubernetes.io/serviceaccount"

func newInClusterCluster() (*restCluster, error) {
	host, port := os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
	if host == "" {
		return nil, fmt.Errorf("not running in a cluster")
	}
	ca, err := os.ReadFile(saDir + "/ca.crt")
	if err != nil {
		return nil, err
	}
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(ca)
	return &restCluster{
		base: fmt.Sprintf("https://%s:%s", host, port),
		client: &http.Client{
			Timeout:   5 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool}},
		},
	}, nil
}

func (c *restCluster) get(ctx context.Context, path string, out any) error {
	// Re-read the projected token each call; kubelet rotates it.
	token, err := os.ReadFile(saDir + "/token")
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+string(token))
	req.Header.Set("Accept", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("GET %s: %s: %s", path, resp.Status, body)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *restCluster) GetReplicaSet(ctx context.Context, ns, name string) (*ReplicaSet, error) {
	var rs ReplicaSet
	err := c.get(ctx, fmt.Sprintf("/apis/apps/v1/namespaces/%s/replicasets/%s", ns, name), &rs)
	return &rs, err
}

func (c *restCluster) MinReplicasForDeployment(ctx context.Context, ns, name string) (int, error) {
	var list hpaList
	if err := c.get(ctx, fmt.Sprintf("/apis/autoscaling/v2/namespaces/%s/horizontalpodautoscalers", ns), &list); err != nil {
		return 0, err
	}
	for _, h := range list.Items {
		ref := h.Spec.ScaleTargetRef
		if ref.Kind == "Deployment" && ref.Name == name {
			if h.Spec.MinReplicas == nil {
				return 1, nil
			}
			return *h.Spec.MinReplicas, nil
		}
	}
	return 1, nil
}

func (c *restCluster) ListPods(ctx context.Context, ns, labelSelector string) ([]Pod, error) {
	var list podList
	// No resourceVersion: a consistent (quorum) read, not the watch cache.
	path := fmt.Sprintf("/api/v1/namespaces/%s/pods?labelSelector=%s", ns, url.QueryEscape(labelSelector))
	err := c.get(ctx, path, &list)
	return list.Items, err
}
