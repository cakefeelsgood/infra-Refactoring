#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
  echo "Usage: $0 dev|prod"
  exit 1
fi

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

if [[ "$ENVIRONMENT" == "dev" ]]; then
  EXPECTED_CONTEXTS="${EXPECTED_CONTEXTS:-moment-dev,moment-dev-eks-cluster}"
  ROOT_APP_NAME="${ROOT_APP_NAME:-moment-dev-root}"
  EXPECTED_NAMESPACE="${EXPECTED_NAMESPACE:-moment-dev}"
  EXPECTED_PROJECT="${EXPECTED_PROJECT:-moment-dev}"
  FORBIDDEN_PATTERN="${FORBIDDEN_PATTERN:-prod|moment-prod}"
fi

if [[ "$ENVIRONMENT" == "prod" ]]; then
  EXPECTED_CONTEXTS="${EXPECTED_CONTEXTS:-moment-prod,moment-prod-eks-cluster}"
  ROOT_APP_NAME="${ROOT_APP_NAME:-moment-prod-root}"
  EXPECTED_NAMESPACE="${EXPECTED_NAMESPACE:-moment-prod}"
  EXPECTED_PROJECT="${EXPECTED_PROJECT:-moment-prod}"
  FORBIDDEN_PATTERN="${FORBIDDEN_PATTERN:-dev|moment-dev}"
fi

echo "===== KUBE CONTEXT CHECK ====="
CURRENT_CONTEXT="$(kubectl config current-context)"

CONTEXT_MATCHED="false"
IFS=',' read -r -a CONTEXT_CANDIDATES <<< "$EXPECTED_CONTEXTS"
for expected_context in "${CONTEXT_CANDIDATES[@]}"; do
  if [[ "$CURRENT_CONTEXT" == "$expected_context" ]]; then
    CONTEXT_MATCHED="true"
  fi
done

if [[ "$CONTEXT_MATCHED" != "true" ]]; then
  echo "ERROR: Wrong kube context. expected one of=[$EXPECTED_CONTEXTS] actual=$CURRENT_CONTEXT"
  exit 1
fi

echo "Current kube context is allowed: $CURRENT_CONTEXT"

echo "===== ARGOCD PODS ====="
kubectl get pods -n "$ARGOCD_NAMESPACE"

echo "===== ARGOCD APPLICATIONS ====="
kubectl get applications -n "$ARGOCD_NAMESPACE"

echo "===== ROOT APPLICATION ====="
kubectl get application "$ROOT_APP_NAME" -n "$ARGOCD_NAMESPACE"

echo "===== APPPROJECT ====="
kubectl get appproject "$EXPECTED_PROJECT" -n "$ARGOCD_NAMESPACE"

echo "===== TARGET NAMESPACE ====="
kubectl get namespace "$EXPECTED_NAMESPACE" --show-labels

echo "===== FORBIDDEN ENV LEAK CHECK ====="
if kubectl get applications -n "$ARGOCD_NAMESPACE" | grep -E "$FORBIDDEN_PATTERN"; then
  echo "ERROR: Forbidden environment application detected by pattern: $FORBIDDEN_PATTERN"
  exit 1
fi

echo "===== RESULT ====="
echo "ArgoCD $ENVIRONMENT bootstrap verification completed."
