#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

REGION="${REGION:-ap-northeast-3}"
ACCOUNT_ID="${ACCOUNT_ID:-611058323802}"
KUBE_CONTEXT="${KUBE_CONTEXT:-moment-dev}"
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
}

use_context() {
  info "USE KUBECTL CONTEXT ${KUBE_CONTEXT}"
  kubectl config use-context "${KUBE_CONTEXT}"
}

align_runtime_db_secret() {
  info "ALIGN DEV RUNTIME DB SECRET FROM RDS MASTER SECRET"

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
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="moment-dev-runtime-", suffix=".json") as f:
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

tf_dir = root / "terraform" / "environments" / "dev"

rds_master_secret_arn = run(
    ["terraform", "output", "-raw", "dev_rds_master_user_secret_arn"],
    cwd=tf_dir,
)

runtime_secret_arns = json.loads(run(
    ["terraform", "output", "-json", "dev_runtime_secret_arns"],
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
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/moment-dev-external-secrets-irsa-role" \
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
  info "APPLY DEV SECRET DELIVERY AND FORCE REFRESH"

  kubectl apply --server-side --force-conflicts -f "${REPO_ROOT}/gitops/apps/dev/secret-delivery/"

  for name in ai-service-dev-secret backend-api-dev-secret batch-job-dev-secret; do
    kubectl -n moment-dev annotate externalsecret "${name}" force-sync="$(date +%s)" --overwrite || true
  done

  sleep 30

  kubectl get externalsecret,clustersecretstore -A
  kubectl get secrets -n moment-dev
}

apply_workloads() {
  if [ "${APPLY_WORKLOADS}" != "true" ]; then
    info "SKIP WORKLOAD APPLY"
    return 0
  fi

  info "APPLY DEV WORKLOADS FROM LOCAL GITOPS VALUES"

  helm template backend-api-dev "${REPO_ROOT}/gitops/charts/backend-api" \
    -f "${REPO_ROOT}/gitops/values/dev/backend-api-values.yaml" \
    | kubectl apply --server-side --force-conflicts -f -

  helm template ai-service-dev "${REPO_ROOT}/gitops/charts/ai-service" \
    -f "${REPO_ROOT}/gitops/values/dev/ai-service-values.yaml" \
    | kubectl apply --server-side --force-conflicts -f -

  helm template batch-job-dev "${REPO_ROOT}/gitops/charts/batch-job" \
    -f "${REPO_ROOT}/gitops/values/dev/batch-job-values.yaml" \
    | kubectl apply --server-side --force-conflicts -f -

  kubectl -n moment-dev rollout restart deploy/backend-api
  kubectl -n moment-dev rollout restart deploy/ai-service
  kubectl -n moment-dev rollout restart deploy/batch-job

  kubectl -n moment-dev rollout status deploy/backend-api --timeout=6m || true
  kubectl -n moment-dev rollout status deploy/ai-service --timeout=6m || true
  kubectl -n moment-dev rollout status deploy/batch-job --timeout=6m || true
}

verify_runtime() {
  info "VERIFY DEV RUNTIME"

  kubectl get applications -n argocd || true
  kubectl get pods -n external-secrets -o wide || true
  kubectl get pods -n moment-dev -o wide || true

  kubectl get deploy -n moment-dev \
    -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{range .spec.template.spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' \
    || true

  kubectl get svc,endpoints -n moment-dev || true
  kubectl get events -n moment-dev --sort-by=.lastTimestamp | tail -80 || true
}

main() {
  require_base_tools
  use_context
  align_runtime_db_secret
  apply_external_secrets_crds
  apply_secret_delivery
  apply_workloads
  verify_runtime

  info "DONE"
}

main "$@"
