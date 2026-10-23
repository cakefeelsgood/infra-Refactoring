package main

import (
	"strconv"
	"strings"
)

type patchOp struct {
	Op    string `json:"op"`
	Path  string `json:"path"`
	Value any    `json:"value,omitempty"`
}

type PatchOptions struct {
	TopologySpread bool
}

const (
	capacityTypeKey = "karpenter.sh/capacity-type"
	capacityTaint   = "capacity"
)

func escape(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, "~", "~0"), "/", "~1")
}

type expr struct {
	Key      string   `json:"key"`
	Operator string   `json:"operator"`
	Values   []string `json:"values"`
}

type toleration struct {
	Key      string `json:"key"`
	Operator string `json:"operator"`
	Value    string `json:"value"`
	Effect   string `json:"effect"`
}

// BuildPatch returns the JSON patch for a decided pod.
func BuildPatch(pod *Pod, dec *Decision, opt PatchOptions) []patchOp {
	var ops []patchOp
	add := func(path string, v any) { ops = append(ops, patchOp{Op: "add", Path: path, Value: v}) }

	// Label
	if pod.Metadata.Labels == nil {
		add("/metadata/labels", map[string]string{LabelRole: dec.Role})
	} else {
		add("/metadata/labels/"+escape(LabelRole), dec.Role)
	}

	// Annotations
	cost := "-1000"
	if dec.Role == RoleBase {
		cost = "1000"
	}
	anns := map[string]string{AnnDeletionCost: cost}
	if dec.ID != "" {
		anns[AnnDecisionID] = dec.ID
	}
	if pod.Metadata.Annotations == nil {
		add("/metadata/annotations", anns)
	} else {
		for _, k := range []string{AnnDeletionCost, AnnDecisionID} {
			if v, ok := anns[k]; ok {
				add("/metadata/annotations/"+escape(k), v)
			}
		}
	}

	// Node affinity
	spec := &pod.Spec
	if dec.Role == RoleBase {
		e := expr{Key: capacityTypeKey, Operator: "In", Values: []string{"on-demand"}}
		required := map[string]any{"nodeSelectorTerms": []any{map[string]any{"matchExpressions": []any{e}}}}
		switch {
		case spec.Affinity == nil:
			add("/spec/affinity", map[string]any{"nodeAffinity": map[string]any{"requiredDuringSchedulingIgnoredDuringExecution": required}})
		case spec.Affinity.NodeAffinity == nil:
			add("/spec/affinity/nodeAffinity", map[string]any{"requiredDuringSchedulingIgnoredDuringExecution": required})
		case spec.Affinity.NodeAffinity.Required == nil || len(spec.Affinity.NodeAffinity.Required.NodeSelectorTerms) == 0:
			add("/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution", required)
		default:
			// Terms are ORed, so the expression must be ANDed into every term.
			for i, t := range spec.Affinity.NodeAffinity.Required.NodeSelectorTerms {
				p := "/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/" + strconv.Itoa(i) + "/matchExpressions"
				if t.MatchExpressions == nil {
					add(p, []any{e})
				} else {
					add(p+"/-", e)
				}
			}
		}
	} else {
		pref := map[string]any{
			"weight":     100,
			"preference": map[string]any{"matchExpressions": []any{expr{Key: capacityTypeKey, Operator: "In", Values: []string{"spot"}}}},
		}
		switch {
		case spec.Affinity == nil:
			add("/spec/affinity", map[string]any{"nodeAffinity": map[string]any{"preferredDuringSchedulingIgnoredDuringExecution": []any{pref}}})
		case spec.Affinity.NodeAffinity == nil:
			add("/spec/affinity/nodeAffinity", map[string]any{"preferredDuringSchedulingIgnoredDuringExecution": []any{pref}})
		case spec.Affinity.NodeAffinity.Preferred == nil:
			add("/spec/affinity/nodeAffinity/preferredDuringSchedulingIgnoredDuringExecution", []any{pref})
		default:
			add("/spec/affinity/nodeAffinity/preferredDuringSchedulingIgnoredDuringExecution/-", pref)
		}
	}

	// Tolerations: burst tolerates the spot taint; base tolerates the optional
	// on-demand taint (only present if the OD NodePool is tainted, see deviations.md).
	tolValue := "spot"
	if dec.Role == RoleBase {
		tolValue = "on-demand"
	}
	tol := toleration{Key: capacityTaint, Operator: "Equal", Value: tolValue, Effect: "NoSchedule"}
	if spec.Tolerations == nil {
		add("/spec/tolerations", []any{tol})
	} else {
		add("/spec/tolerations/-", tol)
	}

	// Topology spread per role and per ReplicaSet (case D)
	if opt.TopologySpread {
		selector := map[string]any{"matchLabels": map[string]string{LabelRole: dec.Role}}
		cs := []any{
			map[string]any{
				"maxSkew":           1,
				"minDomains":        2,
				"topologyKey":       "topology.kubernetes.io/zone",
				"whenUnsatisfiable": "DoNotSchedule",
				"labelSelector":     selector,
				"matchLabelKeys":    []string{LabelTemplate},
			},
			map[string]any{
				"maxSkew":           1,
				"topologyKey":       "kubernetes.io/hostname",
				"whenUnsatisfiable": "ScheduleAnyway",
				"labelSelector":     selector,
				"matchLabelKeys":    []string{LabelTemplate},
			},
		}
		if spec.TopologySpreadConstraints == nil {
			add("/spec/topologySpreadConstraints", cs)
		} else {
			for _, c := range cs {
				add("/spec/topologySpreadConstraints/-", c)
			}
		}
	}
	return ops
}
