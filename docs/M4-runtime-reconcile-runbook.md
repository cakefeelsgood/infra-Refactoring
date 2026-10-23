# M4 Runtime Reconcile Runbook

## 목적

MoMent Dev/Prod EKS 런타임을 비용 절감 후 다시 활성화할 때 반복적으로 발생하는 Secret Delivery, RDS Secret, ECR 이미지 태그, External Secrets CRD 정합성 문제를 표준 절차로 복구한다.

이 Runbook은 임시 Kubernetes Secret 생성이나 수동 patch 중심의 우회가 아니라, Terraform output, Secrets Manager, External Secrets Operator, ECR, GitOps values 기준으로 런타임 상태를 재정합하는 절차를 정의한다.

## 배경

비용 절감을 위해 Dev/Prod EKS, RDS, Redis, OpenSearch, ALB 등 런타임 리소스를 내렸다가 다시 올리면 다음 문제가 반복될 수 있다.

- RDS 재생성으로 RDS master secret ARN/name이 변경됨
- runtime secret에 들어있는 DB username/password가 새 RDS와 불일치함
- ExternalSecret이 예전 rds!db-* secret id를 참조하면 SecretSyncedError가 발생함
- External Secrets CRD가 ArgoCD Helm sync 중 annotations too long 문제로 일부 설치 실패할 수 있음
- Prod GitOps values가 바라보는 image tag가 Prod ECR에 없으면 ImagePullBackOff가 발생함
- Mac arm64 환경에서 docker pull/tag/push 방식은 linux/amd64 image manifest를 직접 pull하지 못할 수 있음

## 이번에 확인한 장애 증상

### Prod Secret Delivery 장애

backend-api-prod-secret, batch-job-prod-secret이 다음 이유로 SecretSyncedError 상태가 되었다.

- ExternalSecret이 존재하지 않는 예전 RDS secret id를 참조함
- stable runtime secret으로 바꾼 뒤에도 property 이름이 username/password로 되어 있어 실제 runtime secret key인 db-username/db-password와 불일치함

해결 방향:

- ExternalSecret remoteRef key를 moment/prod/backend-api, moment/prod/batch-job으로 변경
- DB property를 db-username, db-password로 변경
- RDS master secret 값을 runtime secret에 db-username/db-password로 동기화
- ExternalSecret force-sync 수행

### Prod ImagePullBackOff

Prod values가 다음 태그를 바라봤지만 Prod ECR에 해당 태그가 없어서 ImagePullBackOff가 발생했다.

- backend-api: prod-704952a
- ai-service: prod-62e003b
- batch-job: prod-22d7c4e 또는 기존 prod-11d667f와 불일치 가능

해결 방향:

- Dev ECR의 검증된 이미지 태그를 Prod ECR 태그로 승격
- Mac arm64 docker pull/tag/push 방식 대신 docker buildx imagetools create 사용
- GitOps values의 Prod image tag를 실제 Prod ECR 태그와 맞춤

## 관련 스크립트

### Dev

scripts/runtime/dev/reconcile-runtime.sh

역할:

- Dev RDS master secret에서 username/password를 읽음
- moment/dev/backend-api, moment/dev/batch-job runtime secret에 db-username/db-password를 갱신
- External Secrets CRD/Controller를 server-side apply로 복구
- Dev Secret Delivery를 apply 후 ExternalSecret force-sync
- 선택적으로 Dev workload를 Helm render 후 apply/restart

실행 예시:

APPLY_WORKLOADS=true scripts/runtime/dev/reconcile-runtime.sh

### Prod

scripts/runtime/prod/reconcile-runtime.sh

역할:

- Prod RDS master secret에서 username/password를 읽음
- moment/prod/backend-api, moment/prod/batch-job runtime secret에 db-username/db-password를 갱신
- External Secrets CRD/Controller를 server-side apply로 복구
- Prod Secret Delivery를 apply 후 ExternalSecret force-sync
- Dev ECR image tag를 Prod ECR image tag로 승격
- Prod ECR tag 존재 여부 검증
- 선택적으로 Prod workload를 Helm render 후 apply/restart

실행 예시:

PROMOTE_IMAGES=true APPLY_WORKLOADS=true BACKEND_DEV_TAG=dev-22d7c4e BACKEND_PROD_TAG=prod-22d7c4e AI_DEV_TAG=dev-62e003b AI_PROD_TAG=prod-62e003b BATCH_DEV_TAG=dev-22d7c4e BATCH_PROD_TAG=prod-22d7c4e scripts/runtime/prod/reconcile-runtime.sh

## 실행 전 조건

공통:

- AWS 인증이 완료되어 있어야 함
- kubectl context가 생성되어 있어야 함
- Terraform state 접근이 가능해야 함
- Helm repo 접근이 가능해야 함
- External Secrets IRSA Role이 Terraform으로 생성되어 있어야 함
- moment-dev 또는 moment-prod namespace가 존재하거나 GitOps/Helm으로 생성 가능해야 함

Prod 추가 조건:

- Dev ECR source image tag가 존재해야 함
- Prod ECR repository가 존재해야 함
- docker buildx 사용 가능해야 함
- ECR login 가능해야 함

## 검증 명령

### ExternalSecret 상태

kubectl get externalsecret,clustersecretstore -A
kubectl get secrets -n moment-dev
kubectl get secrets -n moment-prod

정상 기준:

- ClusterSecretStore STATUS Valid
- READY True
- ai-service SecretSynced True
- backend-api SecretSynced True
- batch-job SecretSynced True

### Workload 상태

kubectl get pods -n moment-dev -o wide
kubectl get pods -n moment-prod -o wide

정상 기준:

- backend-api Running
- ai-service Running
- batch-job Running
- ImagePullBackOff 없음
- CreateContainerConfigError 없음
- SecretSyncedError 없음

### Image tag 상태

kubectl get deploy -n moment-prod -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{range .spec.template.spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'

정상 기준:

- backend-api가 의도한 prod tag 사용
- ai-service가 의도한 prod tag 사용
- batch-job이 의도한 prod tag 사용

### ECR tag 확인

aws ecr describe-images --region ap-northeast-3 --repository-name moment-prod-backend-api --image-ids imageTag=prod-22d7c4e
aws ecr describe-images --region ap-northeast-3 --repository-name moment-prod-ai-service --image-ids imageTag=prod-62e003b
aws ecr describe-images --region ap-northeast-3 --repository-name moment-prod-batch-job --image-ids imageTag=prod-22d7c4e

정상 기준:

- ImageNotFoundException이 없어야 함
- imageDigest가 출력되어야 함

## 주의사항

- kubectl create secret 방식으로 임시 Secret을 만들지 않는다.
- rds!db-* secret id를 GitOps manifest에 직접 박지 않는다.
- RDS master secret ARN/name은 재생성 시 바뀔 수 있으므로 runtime secret을 stable source로 사용한다.
- runtime secret에는 실제 secret value를 출력하지 않는다.
- Docker pull/tag/push 방식은 Mac arm64 환경에서 platform mismatch가 날 수 있으므로 Prod 승격은 docker buildx imagetools create 방식을 우선 사용한다.
- ArgoCD OutOfSync가 남으면 live에 수동 apply한 내용과 Git desired가 다른 상태일 수 있으므로 변경 파일을 반드시 PR로 병합한다.

## 재발 방지 기준

- GitOps ExternalSecret은 stable runtime secret name을 참조한다.
- DB credential key 이름은 db-username, db-password로 통일한다.
- runtime reconcile script를 통해 RDS master secret 값을 runtime secret에 주입한다.
- Prod image tag는 ECR 존재 여부를 먼저 검증한다.
- 비용 절감 후 재기동 시 Dev/Prod reconcile script를 먼저 실행한 뒤 smoke/monitoring 검증을 진행한다.

## 이번 작업 결과 요약

- Prod ExternalSecret 3개가 SecretSynced True 상태로 복구됨
- moment-prod-backend-api-secret 생성됨
- moment-prod-batch-job-secret 생성됨
- Prod backend-api, ai-service, batch-job 이미지 태그가 실제 Prod ECR에 생성됨
- Prod backend-api, ai-service, batch-job Deployment rollout 성공
- 기존 ImagePullBackOff와 CreateContainerConfigError 원인 제거됨
