#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
  echo "Usage: $0 dev|prod"
  exit 1
fi

AWS_REGION="${AWS_REGION:-ap-northeast-3}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-611058323802}"
GITOPS_REPO_URL="${GITOPS_REPO_URL:-https://github.com/Team-msp-architect-2026/msp-team04-infra.git}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argocd}"
ARGOCD_CHART="${ARGOCD_CHART:-argo/argo-cd}"
ARGOCD_HELM_TIMEOUT="${ARGOCD_HELM_TIMEOUT:-10m}"

if [[ "$ENVIRONMENT" == "dev" ]]; then
  EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-moment-dev-eks-cluster}"
  KUBE_ALIAS="${KUBE_ALIAS:-moment-dev}"
  ROOT_APP_NAME="${ROOT_APP_NAME:-moment-dev-root}"
  ROOT_APP_MANIFEST="${ROOT_APP_MANIFEST:-gitops/argocd/dev/root-application.yaml}"
  EXPECTED_NAMESPACE="${EXPECTED_NAMESPACE:-moment-dev}"
  FORBIDDEN_PATTERN="${FORBIDDEN_PATTERN:-prod|moment-prod}"
fi

if [[ "$ENVIRONMENT" == "prod" ]]; then
  EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-moment-prod-eks-cluster}"
  KUBE_ALIAS="${KUBE_ALIAS:-moment-prod}"
  ROOT_APP_NAME="${ROOT_APP_NAME:-moment-prod-root}"
  ROOT_APP_MANIFEST="${ROOT_APP_MANIFEST:-gitops/argocd/prod/root-application.yaml}"
  EXPECTED_NAMESPACE="${EXPECTED_NAMESPACE:-moment-prod}"
  FORBIDDEN_PATTERN="${FORBIDDEN_PATTERN:-dev|moment-dev}"

  if [[ "${CONFIRM_PROD:-}" != "prod" ]]; then
    echo "ERROR: Prod bootstrap requires CONFIRM_PROD=prod"
    exit 1
  fi
fi

if [[ ! -f "$ROOT_APP_MANIFEST" ]]; then
  echo "ERROR: Root Application manifest not found: $ROOT_APP_MANIFEST"
  echo "Create the App of Apps manifests first, then rerun this bootstrap."
  exit 1
fi

echo "===== AWS ACCOUNT GUARD ====="
CURRENT_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$CURRENT_ACCOUNT_ID" != "$AWS_ACCOUNT_ID" ]]; then
  echo "ERROR: Wrong AWS account. expected=$AWS_ACCOUNT_ID actual=$CURRENT_ACCOUNT_ID"
  exit 1
fi

echo "===== UPDATE KUBECONFIG ====="
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --alias "$KUBE_ALIAS"

echo "===== KUBE CONTEXT GUARD ====="
CURRENT_CONTEXT="$(kubectl config current-context)"
if [[ "$CURRENT_CONTEXT" != "$KUBE_ALIAS" ]]; then
  echo "ERROR: Wrong kube context. expected=$KUBE_ALIAS actual=$CURRENT_CONTEXT"
  exit 1
fi

echo "===== EKS CLUSTER GUARD ====="
CLUSTER_STATUS="$(aws eks describe-cluster \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER_NAME" \
  --query 'cluster.status' \
  --output text)"

if [[ "$CLUSTER_STATUS" != "ACTIVE" ]]; then
  echo "ERROR: EKS cluster is not ACTIVE. status=$CLUSTER_STATUS"
  exit 1
fi

echo "===== NODE CHECK ====="
kubectl get nodes

echo "===== INSTALL ARGOCD BY HELM ====="
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update

helm upgrade --install "$ARGOCD_RELEASE_NAME" "$ARGOCD_CHART" \
  --namespace "$ARGOCD_NAMESPACE" \
  --wait \
  --timeout "$ARGOCD_HELM_TIMEOUT" \
  --set server.service.type=ClusterIP

echo "===== WAIT ARGOCD COMPONENTS ====="
kubectl wait --for=condition=Available deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=300s
kubectl wait --for=condition=Available deployment/argocd-applicationset-controller -n "$ARGOCD_NAMESPACE" --timeout=300s || true

echo "===== CHECK ARGOCD CRDS ====="
kubectl get crd applications.argoproj.io
kubectl get crd appprojects.argoproj.io

echo "===== CONFIGURE REPOSITORY CREDENTIAL IF TOKEN EXISTS ====="
if [[ -n "${GITOPS_REPO_TOKEN:-}" ]]; then
  kubectl create secret generic moment-infra-gitops-repo \
    -n "$ARGOCD_NAMESPACE" \
    --from-literal=type=git \
    --from-literal=url="$GITOPS_REPO_URL" \
    --from-literal=username="${GITOPS_REPO_USERNAME:-x-access-token}" \
    --from-literal=password="$GITOPS_REPO_TOKEN" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
else
  echo "GITOPS_REPO_TOKEN is empty. Skip repository credential secret creation."
  echo "If the repository is private, export GITOPS_REPO_TOKEN locally and rerun."
fi

echo "===== APPLY ROOT APPLICATION ====="
kubectl apply -f "$ROOT_APP_MANIFEST"

echo "===== WAIT ROOT APPLICATION RECONCILE ====="
kubectl get application "$ROOT_APP_NAME" -n "$ARGOCD_NAMESPACE"

echo "ArgoCD CLI sync is intentionally skipped in bootstrap."
echo "Dev Root Application uses automated sync."
echo "Prod sync must be performed manually after approval."

echo "===== VERIFY BOOTSTRAP RESULT ====="
"$(dirname "$0")/verify.sh" "$ENVIRONMENT"
