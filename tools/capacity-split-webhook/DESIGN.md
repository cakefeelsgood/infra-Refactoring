# capacity-split webhook — design

## Goal

For every pod a ReplicaSet creates in a namespace labelled `capacity-split=enabled`:

- while the ReplicaSet has fewer than `minReplicas` (from the HPA targeting its Deployment, default 1) live base pods, the pod becomes **base**: label `capacity-role=base`, `pod-deletion-cost: 1000`, required node affinity `karpenter.sh/capacity-type In [on-demand]`, toleration for the optional `capacity=on-demand:NoSchedule` taint;
- otherwise it becomes **burst**: label `capacity-role=burst`, `pod-deletion-cost: -1000`, preferred (weight 100) affinity for `spot`, toleration `capacity=spot:NoSchedule`;
- with `ENABLE_TOPOLOGY_SPREAD=true` (case D) it also gets, per role and per ReplicaSet (`labelSelector capacity-role=<role>` + `matchLabelKeys [pod-template-hash]`):
  - zone: `maxSkew 1`, `DoNotSchedule`, `minDomains 2`
  - hostname: `maxSkew 1`, `ScheduleAnyway`

`minDomains: 2` matters for base pods. kube-scheduler only counts zones that already have a node matching the pod's node affinity. If the only on-demand node is in one zone, the scheduler would see a single domain and could put all four base pods there. `minDomains: 2` treats the missing zone as having zero pods, so the 3rd base pod stays Pending until Karpenter brings up an on-demand node in the other zone.

## The race problem

1. At admission the pod has no name (`generateName`), so a decision cannot be matched to a pod by name.
2. The ReplicaSet controller creates many pods concurrently. If each admission just lists pods and counts base pods, several admissions see the same count and the result ends up with more or fewer than 4 base pods.
3. A pod we mutated can still be rejected by a later admission stage (another webhook, quota), so "decided" does not mean "exists".

## Approach

- **Per-ReplicaSet serialization:** one mutex per RS UID. All admissions for the same RS run one at a time. Different RSs (for example the old and new RS during a rolling update) do not block each other.
- **Decision id:** every non-dry-run decision gets a random id, written to the pod as the annotation `capacity-split.lab/decision-id` and kept in memory as an *in-flight* entry `{role, expires}`.
- **Count = visible + in-flight.** Under the RS lock:
  1. list pods with `pod-template-hash=<hash>`. This is a consistent read because no resourceVersion is sent;
  2. count *visible base* pods: owned by this RS UID, not terminating, not Failed/Succeeded, `capacity-role=base`;
  3. drop in-flight entries whose id now appears on any listed pod (the list already accounts for them) or whose TTL has passed;
  4. `role = base if visibleBase + inflightBase < minReplicas else burst`.
- **TTL (15s)** bounds the damage from case 3. A rejected base decision is counted as a phantom base for at most 15s. A pod admitted for the same RS within that window becomes burst, so the RS can end up with 3 base + N burst until base pods are recreated. Once the TTL passes, new pods are decided correctly again (`TestRejectedPodSelfHealsAfterTTL`). There is no active reconciler that evicts a burst pod to restore the base count. Evicting pods would add disruptions the experiments must not have. Drift is checked from outside instead (Phase 4 and Phase 7 precondition checks).
- **dryRun:** decisions are computed and a patch is returned, but no in-flight entry is stored and no id is written (`sideEffects: NoneOnDryRun`).
- **Errors → deny.** If ReplicaSet, HPA, or pod list lookup fails, the pod is denied. The ReplicaSet controller retries with backoff. With `failurePolicy: Fail` a pod is never admitted with an unknown role, which would silently contaminate the experiment.

## Operational notes / known limits

- **Single replica, `Recreate` strategy = SPOF.** The in-memory state only works with exactly one live webhook process. A rolling update could briefly run two pods that each count independently. While the webhook pod restarts, pod creation in `app` fails and is retried by the ReplicaSet controller. This is acceptable for a lab and is not production-grade. The production alternative is leader election, or storing in-flight decisions in the API server (for example a Lease/ConfigMap per RS with optimistic concurrency).
- Restarting the webhook loses in-flight entries. Any pod admitted < 1s before the restart and not yet visible could be double counted, but in the other direction (an extra base). Phase 4 tests this by restarting during creation.
- The webhook runs on system nodes (`role=system`, tolerates `CriticalAddonsOnly`). It does not apply to its own namespace, `kube-system`, or `karpenter`.
- The API server reaches the webhook on port 9443, which the EKS module's recommended node security-group rules already allow from the control plane.

## Tests

`go test -race ./...` (run in the `golang:1.27` container):

- `TestConcurrent16Pods`: 16 concurrent admissions for one RS, random persistence delay, 50 trials → exactly 4 base / 12 burst every time
- `TestRollingUpdateTwoReplicaSets`: two RSs × 16 concurrent → 4 base each
- `TestBaseReplacedAfterDeletion`, `TestRejectedPodSelfHealsAfterTTL`, `TestDryRunDoesNotChangeState`, `TestHPALookupFailureDenies`, `TestNoHPAMeansOneBase`, `TestNonReplicaSetPodIgnored`
- patch tests: base on a plain pod, burst appending to existing tolerations/affinity, required expression ANDed into every node selector term

## Production changes (MoMent infra, 2026-10-23)

Ported from the karpenter-spot-lab experiment. Everything above is the lab design; only these changed:

| Change | Why |
|---|---|
| Decision annotation `capacity-split.lab/decision-id` → `capacity-split.moment.io/decision-id`, module path | Remove the lab identifier |
| `FAIL_OPEN=true` (chart default): a decision error admits the pod unmodified instead of denying it | The webhook must stay a single replica (in-memory state, see SPOF note), so fail-closed would block pod creation for every opted-in workload while it is down. `failurePolicy: Ignore` alone does not cover this, because the lab code returns an explicit deny on lookup errors |
| `failurePolicy: Ignore` (was `Fail`) | Same reason: an unreachable webhook must not block pod creation |
| `objectSelector` `capacity-split.moment.io/enabled=true` in addition to the namespace label | Only backend-api opts in. ai-service and batch-job share the namespace but use a single capacity type |
| Certificates from `kube-webhook-certgen` PreSync/PostSync jobs (was `scripts/deploy-webhook.sh` with openssl) | GitOps delivery, no cert-manager in the cluster |

Consequence of fail-open: a pod admitted while the webhook is unavailable keeps the pod template defaults. In backend-api those are the burst defaults (Spot toleration, Karpenter nodes only), so the pod lands on Spot without `pod-deletion-cost`. The base count self-corrects only when base pods are recreated, as described in "Approach" for rejected decisions.

Tests: `main_test.go` adds fail-open, fail-closed and annotation-key checks on top of the lab tests. Run `go test -race ./...` (Go 1.27, as in the lab).
