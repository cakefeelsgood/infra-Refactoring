#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

REGION="${REGION:-ap-northeast-3}"
ACCOUNT_ID="${ACCOUNT_ID:-611058323802}"
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
KUBE_CONTEXT="${KUBE_CONTEXT:-moment-prod}"

BACKEND_DEV_TAG="${BACKEND_DEV_TAG:-dev-22d7c4e}"
BACKEND_PROD_TAG="${BACKEND_PROD_TAG:-prod-22d7c4e}"
AI_DEV_TAG="${AI_DEV_TAG:-dev-62e003b}"
AI_PROD_TAG="${AI_PROD_TAG:-prod-62e003b}"
BATCH_DEV_TAG="${BATCH_DEV_TAG:-dev-22d7c4e}"
BATCH_PROD_TAG="${BATCH_PROD_TAG:-prod-22d7c4e}"

PROMOTE_IMAGES="${PROMOTE_IMAGES:-true}"
APPLY_WORKLOADS="${APPLY_WORKLOADS:-false}"

info() {
  printf '\n===== %s =====\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_base_tools() {
  require_cmd aws
  require_cmd kubectl
  require_cmd terraform
  require_cmd helm
  require_cmd python3

  if [ "${PROMOTE_IMAGES}" = "true" ]; then
    require_cmd docker
  fi
}

use_context() {
  info "USE KUBECTL CONTEXT ${KUBE_CONTEXT}"
  kubectl config use-context "${KUBE_CONTEXT}"
}

align_runtime_db_secret() {
  info "ALIGN PROD RUNTIME DB SECRET FROM RDS MASTER SECRET"

  REPO_ROOT="${REPO_ROOT}" REGION="${REGION}" python3 - <<'PY'
import json
import os
import subprocess
import tempfile
from pathlib import Path

root = Path(os.environ["REPO_ROOT"])
region = os.environ["REGION"]

def run(cmd, cwd=root):
    return subprocess.check_output(cmd, cwd=cwd, text=True).strip()

def get_secret_json(secret_id):
    raw = run([
        "aws", "secretsmanager", "get-secret-value",
        "--region", region,
        "--secret-id", secret_id,
        "--query", "SecretString",
        "--output", "text",
    ])
    return json.loads(raw)

def put_secret_json(secret_id, payload):
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="moment-prod-runtime-", suffix=".json") as f:
        json.dump(payload, f, ensure_ascii=False)
        path = f.name

    try:
        subprocess.check_call([
            "aws", "secretsmanager", "put-secret-value",
            "--region", region,
            "--secret-id", secret_id,
            "--secret-string", f"file://{path}",
        ])
    finally:
        Path(path).unlink(missing_ok=True)

tf_dir = root / "terraform" / "environments" / "prod"

rds_master_secret_arn = run(
    ["terraform", "output", "-raw", "prod_rds_master_user_secret_arn"],
    cwd=tf_dir,
)

runtime_secret_arns = json.loads(run(
    ["terraform", "output", "-json", "prod_runtime_secret_arns"],
    cwd=tf_dir,
))

rds_secret = get_secret_json(rds_master_secret_arn)
username = rds_secret.get("username")
password = rds_secret.get("password")

if not username or not password:
    raise SystemExit("ERROR: RDS master secret does not contain username/password")

for key in ["backend_api", "batch_job"]:
    secret_arn = runtime_secret_arns[key]
    payload = get_secret_json(secret_arn)

    payload["db-username"] = username
    payload["db-password"] = password

    put_secret_json(secret_arn, payload)
    print(f"updated {key} runtime secret db-username/db-password without printing values")
PY
}

apply_external_secrets_crds() {
  info "APPLY EXTERNAL SECRETS CRDS / CONTROLLERS WITH SERVER-SIDE APPLY"

  helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
  helm repo update external-secrets

  helm template external-secrets external-secrets/external-secrets \
    --version 2.5.0 \
    --namespace external-secrets \
    --include-crds \
    --set installCRDs=true \
    --set serviceAccount.create=true \
    --set serviceAccount.name=external-secrets \
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/moment-prod-external-secrets-irsa-role" \
    | kubectl apply --server-side --force-conflicts -f -

  kubectl -n external-secrets rollout restart deploy/external-secrets || true
  kubectl -n external-secrets rollout restart deploy/external-secrets-cert-controller || true
  kubectl -n external-secrets rollout restart deploy/external-secrets-webhook || true

  kubectl -n external-secrets rollout status deploy/external-secrets --timeout=3m || true
  kubectl -n external-secrets rollout status deploy/external-secrets-cert-controller --timeout=3m || true
  kubectl -n external-secrets rollout status deploy/external-secrets-webhook --timeout=3m || true

  kubectl get crd | grep -E 'externalsecrets|secretstores|clustersecretstores'
}

apply_secret_delivery() {
  info "APPLY PROD SECRET DELIVERY AND FORCE REFRESH"

  kubectl apply --server-side --force-conflicts -f "${REPO_ROOT}/gitops/apps/prod/secret-delivery/"

  for name in ai-service-prod-secret backend-api-prod-secret batch-job-prod-secret; do
    kubectl -n moment-prod annotate externalsecret "${name}" force-sync="$(date +%s)" --overwrite || true
  done

  sleep 30

  kubectl get externalsecret,clustersecretstore -A
  kubectl get secrets -n moment-prod
}

promote_image() {
  local src_repo="$1"
  local src_tag="$2"
  local dst_repo="$3"
  local dst_tag="$4"

  info "PROMOTE ${src_repo}:${src_tag} -> ${dst_repo}:${dst_tag}"

  docker buildx imagetools create \
    -t "${ECR}/${dst_repo}:${dst_tag}" \
    "${ECR}/${src_repo}:${src_tag}"
}

promote_images() {
  if [ "${PROMOTE_IMAGES}" != "true" ]; then
    info "SKIP IMAGE PROMOTION"
    return 0
  fi

  info "ECR LOGIN"
  aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${ECR}"

  promote_image moment-dev-backend-api "${BACKEND_DEV_TAG}" moment-prod-backend-api "${BACKEND_PROD_TAG}"
  promote_image moment-dev-ai-service "${AI_DEV_TAG}" moment-prod-ai-service "${AI_PROD_TAG}"
  promote_image moment-dev-batch-job "${BATCH_DEV_TAG}" moment-prod-batch-job "${BATCH_PROD_TAG}"
}

verify_ecr_tags() {
  info "VERIFY PROD ECR TAGS"

  aws ecr describe-images \
    --region "${REGION}" \
    --repository-name moment-prod-backend-api \
    --image-ids imageTag="${BACKEND_PROD_TAG}" \
    --query 'imageDetails[0].{tags:imageTags,pushed:imagePushedAt,digest:imageDigest}' \
    --output table

  aws ecr describe-images \
    --region "${REGION}" \
    --repository-name moment-prod-ai-service \
    --image-ids imageTag="${AI_PROD_TAG}" \
    --query 'imageDetails[0].{tags:imageTags,pushed:imagePushedAt,digest:imageDigest}' \
    --output table

  aws ecr describe-images \
    --region "${REGION}" \
    --repository-name moment-prod-batch-job \
    --image-ids imageTag="${BATCH_PROD_TAG}" \
    --query 'imageDetails[0].{tags:imageTags,pushed:imagePushedAt,digest:imageDigest}' \
    --output table
}

apply_workloads() {
  if [ "${APPLY_WORKLOADS}" != "true" ]; then
    info "SKIP WORKLOAD APPLY"
    return 0
  fi

  info "APPLY PROD WORKLOADS FROM LOCAL GITOPS VALUES"

  helm template backend-api-prod "${REPO_ROOT}/gitops/charts/backend-api" \
    -f "${REPO_ROOT}/gitops/values/prod/backend-api-values.yaml" \
    | kubectl apply --server-side --force-conflicts -f -

  helm template ai-service-prod "${REPO_ROOT}/gitops/charts/ai-service" \
    -f "${REPO_ROOT}/gitops/values/prod/ai-service-values.yaml" \
    | kubectl apply --server-side --force-conflicts -f -

  helm template batch-job-prod "${REPO_ROOT}/gitops/charts/batch-job" \
    -f "${REPO_ROOT}/gitops/values/prod/batch-job-values.yaml" \
    | kubectl apply --server-side --force-conflicts -f -

  kubectl -n moment-prod rollout restart deploy/backend-api
  kubectl -n moment-prod rollout restart deploy/ai-service
  kubectl -n moment-prod rollout restart deploy/batch-job

  kubectl -n moment-prod rollout status deploy/backend-api --timeout=6m || true
  kubectl -n moment-prod rollout status deploy/ai-service --timeout=6m || true
  kubectl -n moment-prod rollout status deploy/batch-job --timeout=6m || true
}

verify_runtime() {
  info "VERIFY PROD RUNTIME"

  kubectl get applications -n argocd || true
  kubectl get pods -n external-secrets -o wide || true
  kubectl get pods -n moment-prod -o wide || true

  kubectl get deploy -n moment-prod \
    -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{range .spec.template.spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' \
    || true

  kubectl get svc,endpoints -n moment-prod || true
  kubectl get events -n moment-prod --sort-by=.lastTimestamp | tail -80 || true
}

main() {
  require_base_tools
  use_context
  align_runtime_db_secret
  apply_external_secrets_crds
  apply_secret_delivery
  promote_images
  verify_ecr_tags
  apply_workloads
  verify_runtime

  info "DONE"
}

main "$@"
