#!/usr/bin/env bash
# Static check: VPC CNI Prefix Delegation and kubelet maxPods must agree (CLAUDE.md invariant 1)
# and every node role must carry AmazonEKS_CNI_Policy (invariant 2).
#
# In the VPC CNI experiment, PD off + maxPods 40 left 44 of 100 pods in ContainerCreating
# and Karpenter did not add nodes; PD on + maxPods 17 doubled the node count.
#
# Reads only files in this repository. No AWS or cluster access.
# Usage: scripts/validation/check-pd-maxpods.sh [env ...]   (default: dev prod)
# Env:   REPO_ROOT (default: repo of this script), EXPECTED_MAX_PODS (default 40),
#        SECONDARY_MAX_PODS (default 17 = t3.medium ENI limit, smallest node type in use)
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
EXPECTED_MAX_PODS="${EXPECTED_MAX_PODS:-40}"
SECONDARY_MAX_PODS="${SECONDARY_MAX_PODS:-17}"
ENVS=("$@")
[[ ${#ENVS[@]} -gt 0 ]] || ENVS=(dev prod)

fail=0
err() { echo "FAIL [$1] $2"; fail=1; }
ok() { echo "OK   [$1] $2"; }

# Prints the body of a top-level HCL block whose header line matches $2.
hcl_block() {
  awk -v hdr="$2" '
    index($0, hdr) == 1 { inside = 1 }
    inside { print; depth += gsub(/\{/, "{"); depth -= gsub(/\}/, "}"); if (depth == 0 && seen) exit; if (depth > 0) seen = 1 }
  ' "$1"
}

for env in "${ENVS[@]}"; do
  main="$REPO_ROOT/terraform/environments/$env/main.tf"
  nodeclass_dir="$REPO_ROOT/gitops/apps/$env/karpenter"
  [[ -f "$main" ]] || { err "$env" "missing $main"; continue; }

  # 1. Prefix Delegation flag in the vpc-cni add-on configuration_values.
  eks_block="$(hcl_block "$main" "module \"${env}_eks\" {")"
  cni_block="$(printf '%s\n' "$eks_block" | awk '/vpc-cni = \{/ { inside = 1 } inside { print } inside && /^    \}/ { exit }')"
  [[ -n "$cni_block" ]] || { err "$env" "vpc-cni add-on block not found in module ${env}_eks"; continue; }
  if printf '%s\n' "$cni_block" | grep -Eq 'ENABLE_PREFIX_DELEGATION[[:space:]]*=[[:space:]]*"true"'; then
    pd=true
  else
    pd=false
  fi
  echo "INFO [$env] ENABLE_PREFIX_DELEGATION=$pd (vpc-cni add-on)"

  # 2. maxPods sources: managed node groups (max_pods) and EC2NodeClasses (kubelet.maxPods).
  # Every managed node group module instance (core/ops and the legacy batch/ai instance).
  ng_block="$(hcl_block "$main" "module \"${env}_eks_nodegroups\" {"; hcl_block "$main" "module \"${env}_eks_legacy_nodegroups\" {")"
  ng_count="$(printf '%s\n' "$ng_block" | grep -Ec '^[[:space:]]+instance_types[[:space:]]*=' || true)"
  ng_values="$(printf '%s\n' "$ng_block" | sed -nE 's/^[[:space:]]+max_pods[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p')"
  ng_set="$(printf '%s\n' "$ng_values" | grep -c . || true)"
  echo "INFO [$env] managed node groups=$ng_count with max_pods=$ng_set values=[$(echo $ng_values)]"

  nc_count=0; nc_values=""
  if [[ -d "$nodeclass_dir" ]]; then
    nc_count="$(cat "$nodeclass_dir"/*.yaml | grep -Ec '^kind:[[:space:]]*EC2NodeClass' || true)"
    nc_values="$(cat "$nodeclass_dir"/*.yaml | sed -nE 's/^[[:space:]]+maxPods:[[:space:]]*([0-9]+).*/\1/p')"
  fi
  nc_set="$(printf '%s\n' "$nc_values" | grep -c . || true)"
  echo "INFO [$env] EC2NodeClasses=$nc_count with kubelet.maxPods=$nc_set values=[$(echo $nc_values)]"

  all_values="$(printf '%s\n%s\n' "$ng_values" "$nc_values" | grep . || true)"

  if [[ "$pd" == true ]]; then
    [[ "$ng_set" -eq "$ng_count" ]] && ok "$env" "every managed node group sets max_pods" \
      || err "$env" "PD on but $((ng_count - ng_set)) managed node group(s) keep the ENI-based default maxPods"
    [[ "$nc_set" -eq "$nc_count" ]] && ok "$env" "every EC2NodeClass sets kubelet.maxPods" \
      || err "$env" "PD on but $((nc_count - nc_set)) EC2NodeClass(es) keep the ENI-based default maxPods"
    bad="$(printf '%s\n' "$all_values" | grep -v "^${EXPECTED_MAX_PODS}\$" || true)"
    [[ -z "$bad" ]] && ok "$env" "all maxPods values equal $EXPECTED_MAX_PODS" \
      || err "$env" "maxPods values differ from $EXPECTED_MAX_PODS: [$(echo $bad)]"
  else
    bad="$(printf '%s\n' "$all_values" | awk -v lim="$SECONDARY_MAX_PODS" '$1 > lim' || true)"
    [[ -z "$bad" ]] && ok "$env" "PD off and no maxPods above the secondary-IP limit $SECONDARY_MAX_PODS" \
      || err "$env" "PD off but maxPods [$(echo $bad)] exceeds the secondary-IP limit $SECONDARY_MAX_PODS (pods would stick in ContainerCreating)"
  fi
done

# 3. max_pods must actually reach the node: modules/eks-nodegroup renders it into the nodeadm NodeConfig.
if [[ -f "$REPO_ROOT/terraform/modules/eks-nodegroup/main.tf" ]]; then
  grep -Eq 'maxPods:[[:space:]]*\$\{each\.value\.max_pods\}' "$REPO_ROOT/terraform/modules/eks-nodegroup/main.tf" \
    && ok all "modules/eks-nodegroup renders max_pods into the launch template NodeConfig" \
    || err all "modules/eks-nodegroup does not render max_pods into user_data (max_pods would be ignored)"
fi

# 4. Invariant 2: aws-node has no IRSA in this repo, so every node role needs the CNI policy.
# MNG: the CNI attachment must target the role the node groups use (module.<env>_iam eks_node_role_arn).
cni_block="$(hcl_block "$REPO_ROOT/terraform/modules/iam/main.tf" 'resource "aws_iam_role_policy_attachment" "eks_node_cni" {')"
if printf '%s\n' "$cni_block" | grep -Eq 'role[[:space:]]*=[[:space:]]*aws_iam_role\.eks_node\.name' \
  && printf '%s\n' "$cni_block" | grep -q 'AmazonEKS_CNI_Policy' \
  && grep -Eq 'value[[:space:]]*=[[:space:]]*aws_iam_role\.eks_node\.arn' "$REPO_ROOT/terraform/modules/iam/outputs.tf"; then
  ok all "MNG node role (modules/iam aws_iam_role.eks_node) has AmazonEKS_CNI_Policy"
else
  err all "MNG node role (modules/iam aws_iam_role.eks_node) is missing AmazonEKS_CNI_Policy"
fi
for env in "${ENVS[@]}"; do
  main="$REPO_ROOT/terraform/environments/$env/main.tf"
  bad_role="$( { hcl_block "$main" "module \"${env}_eks_nodegroups\" {"; hcl_block "$main" "module \"${env}_eks_legacy_nodegroups\" {"; } \
    | grep -E '^[[:space:]]+node_role_arn' | grep -v "module.${env}_iam\[0\].eks_node_role_arn" || true)"
  [[ -z "$bad_role" ]] && ok "$env" "managed node groups use module.${env}_iam eks_node_role_arn" \
    || err "$env" "managed node group uses another role: $bad_role"
done
grep -Eq 'AmazonEKS_CNI_Policy[[:space:]]*=' "$REPO_ROOT/terraform/modules/karpenter/main.tf" \
  && ok all "Karpenter node role has AmazonEKS_CNI_Policy (modules/karpenter)" \
  || err all "Karpenter node role is missing AmazonEKS_CNI_Policy (modules/karpenter)"

if [[ $fail -eq 0 ]]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; fi
exit $fail
