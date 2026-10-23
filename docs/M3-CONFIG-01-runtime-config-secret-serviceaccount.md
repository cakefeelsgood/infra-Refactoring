# M3-CONFIG-01 Runtime Config / Secret / ServiceAccount 정리

## 1. 대상 Workload

| Workload | Chart Path | Dev Values | Prod Values |
|---|---|---|---|
| Backend API | `gitops/charts/backend-api` | `gitops/values/dev/backend-api-values.yaml` | `gitops/values/prod/backend-api-values.yaml` |
| AI Service | `gitops/charts/ai-service` | `gitops/values/dev/ai-service-values.yaml` | `gitops/values/prod/ai-service-values.yaml` |
| Batch Job | `gitops/charts/batch-job` | `gitops/values/dev/batch-job-values.yaml` | `gitops/values/prod/batch-job-values.yaml` |

---

## 2. Namespace

| Environment | Namespace |
|---|---|
| Dev | `moment-dev` |
| Prod | `moment-prod` |

Dev namespace는 EKS 클러스터에 생성 완료했다.

```bash
kubectl get ns moment-dev
```

Prod namespace는 비용 절감을 위해 prod 인프라를 상시 운영하지 않으므로, prod 활성화 시점에 생성 및 검증한다.

---

## 3. ConfigMap 관리 항목

Secret 값은 ConfigMap에 넣지 않는다.
ConfigMap에는 환경별로 달라지는 non-secret runtime 설정만 둔다.

### Backend API

| Key | Dev 값 | Secret 여부 |
|---|---|---|
| `SPRING_PROFILES_ACTIVE` | `dev` | No |
| `AWS_REGION` | `ap-northeast-3` | No |
| `ENVIRONMENT` | `dev` | No |
| `DB_HOST` | Dev RDS endpoint | No |
| `DB_PORT` | `5432` | No |
| `DB_NAME` | `moment` | No |
| `REDIS_HOST` | Dev Redis endpoint | No |
| `REDIS_PORT` | `6379` | No |
| `OPENSEARCH_HOST` | Dev OpenSearch endpoint | No |
| `S3_PROFILE_IMAGE_BUCKET` | Dev profile image bucket | No |
| `SQS_QUEUE_NAME` | Dev public data queue | No |
| `AI_SERVICE_URL` | `http://ai-service:8000` | No |

### AI Service

| Key | Dev 값 | Secret 여부 |
|---|---|---|
| `ENVIRONMENT` | `dev` | No |
| `AWS_REGION` | `ap-northeast-3` | No |
| `LOG_LEVEL` | `DEBUG` | No |
| `OPENSEARCH_HOST` | Dev OpenSearch endpoint | No |
| `BACKEND_API_URL` | `http://backend-api:8080` | No |

### Batch Job

| Key | Dev 값 | Secret 여부 |
|---|---|---|
| `SPRING_PROFILES_ACTIVE` | `dev` | No |
| `AWS_REGION` | `ap-northeast-3` | No |
| `SQS_QUEUE_NAME` | Dev public data queue | No |
| `SQS_QUEUE_URL` | Dev public data queue URL | No |
| `S3_RAW_BUCKET` | Dev raw data bucket | No |
| `DB_HOST` | Dev RDS endpoint | No |
| `DB_PORT` | `5432` | No |
| `DB_NAME` | `moment` | No |
| `OPENSEARCH_HOST` | Dev OpenSearch endpoint | No |

---

## 4. Secret 관리 항목

Secret 값은 GitOps Repository에 평문으로 저장하지 않는다.
Manifest에는 Secret name과 Secret key name만 참조한다.

### Backend API

| Env Name | Secret Name | Secret Key |
|---|---|---|
| `DB_USERNAME` | `moment-dev-backend-api-secret` | `db-username` |
| `DB_PASSWORD` | `moment-dev-backend-api-secret` | `db-password` |
| `JWT_SECRET` | `moment-dev-backend-api-secret` | `jwt-secret` |
| `TOSS_SECRET` | `moment-dev-backend-api-secret` | `toss-secret` |

### AI Service

| Env Name | Secret Name | Secret Key |
|---|---|---|
| `OPENAI_API_KEY` | `moment-dev-ai-service-secret` | `openai-api-key` |

### Batch Job

| Env Name | Secret Name | Secret Key |
|---|---|---|
| `DB_USERNAME` | `moment-dev-batch-job-secret` | `db-username` |
| `DB_PASSWORD` | `moment-dev-batch-job-secret` | `db-password` |
| `PUBLIC_DATA_API_KEY` | `moment-dev-batch-job-secret` | `public-data-api-key` |

---

## 5. Prod Secret 기준

Prod는 비용 절감을 위해 상시 운영하지 않고, 발표 또는 최종 검증 기간에만 활성화할 예정이다.
따라서 prod values에는 Secret 구조만 미리 정의하고 실제 Secret 값은 prod 인프라 활성화 시점에 등록한다.

| Workload | Prod Secret Name | 주요 Key |
|---|---|---|
| Backend API | `moment-prod-backend-api-secret` | `db-username`, `db-password`, `jwt-secret`, `toss-secret` |
| AI Service | `moment-prod-ai-service-secret` | `openai-api-key` |
| Batch Job | `moment-prod-batch-job-secret` | `db-username`, `db-password`, `public-data-api-key` |

Prod Secret 값은 Git에 커밋하지 않는다.

---

## 6. ServiceAccount

| Workload | Dev ServiceAccount | Prod ServiceAccount |
|---|---|---|
| Backend API | `moment-dev-backend-api-sa` | `moment-prod-backend-api-sa` |
| AI Service | `moment-dev-ai-service-sa` | `moment-prod-ai-service-sa` |
| Batch Job | `moment-dev-batch-job-sa` | `moment-prod-batch-job-sa` |

각 Deployment / CronJob은 default ServiceAccount를 사용하지 않고, workload별 ServiceAccount를 명시적으로 참조한다.

---

## 7. IRSA 상태

현재 IAM Role 목록에서 아래 IRSA Role을 확인했다.

- `moment-dev-alb-controller-irsa-role`
- `moment-dev-ebs-csi-irsa-role`
- `moment-dev-backend-api-irsa-role`
- `moment-dev-ai-service-irsa-role`
- `moment-dev-batch-job-irsa-role`

M3-CONFIG-01 범위에서 Backend API, AI Service, Batch Job 전용 IRSA Role을 생성하고 각 ServiceAccount annotation에 Role ARN을 반영했다.

| Workload | ServiceAccount | IRSA Role |
|---|---|---|
| Backend API | `moment-dev-backend-api-sa` | `moment-dev-backend-api-irsa-role` |
| AI Service | `moment-dev-ai-service-sa` | `moment-dev-ai-service-irsa-role` |
| Batch Job | `moment-dev-batch-job-sa` | `moment-dev-batch-job-irsa-role` |

values 반영 예시는 다음과 같다.

```yaml
serviceAccount:
  create: true
  name: moment-dev-backend-api-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::611058323802:role/moment-dev-backend-api-irsa-role
```

## 8. Dev Secret 생성 현황

Dev EKS cluster의 `moment-dev` namespace에 아래 Secret을 생성했다.

| Secret Name | Data 개수 |
|---|---:|
| `moment-dev-backend-api-secret` | 4 |
| `moment-dev-ai-service-secret` | 1 |
| `moment-dev-batch-job-secret` | 3 |

확인 명령어:

```bash
kubectl get secret -n moment-dev
```

Secret 값은 PR, Git diff, 로그, 캡처에 노출하지 않는다.

---

## 9. Node Scheduling 기준

현재 Dev EKS node는 아래 label을 가진다.

| Key | Value |
|---|---|
| `workload` | `core` |
| `capacity` | `on-demand` |

따라서 Dev 환경에서는 Backend API, AI Service, Batch Job 모두 아래 nodeSelector를 사용한다.

```yaml
nodeSelector:
  workload: core
  capacity: on-demand
```

Prod 환경에서는 AI Service와 Batch Job을 별도 spot node로 분리하는 구조를 values에 유지한다.
다만 prod node group은 비용 절감을 위해 prod 인프라 활성화 시점에 검증한다.

---

## 10. Prod 운영 기준

Prod 환경은 비용 절감을 위해 상시 운영하지 않는다.
발표 또는 최종 검증 기간에 약 3일 정도만 활성화하는 운영 방식을 기준으로 한다.

따라서 현재 prod values는 아래 항목을 placeholder로 유지한다.

- RDS endpoint
- Redis endpoint
- OpenSearch endpoint
- ACM certificate ARN
- workload별 IRSA Role ARN
- prod Secret 실제 값

Prod 활성화 시점에 다음을 반영해야 한다.

1. Prod RDS endpoint
2. Prod Redis endpoint
3. Prod OpenSearch endpoint
4. Prod ACM certificate ARN
5. Prod backend / AI / batch Secret 생성
6. Prod backend / AI / batch IRSA Role ARN 연결
7. Prod namespace 생성
8. Prod Helm render 및 server dry-run
9. ArgoCD Sync 및 Pod Running 검증

---

## 11. 검증 명령어

### Dev Helm Render

```bash
helm template backend-api gitops/charts/backend-api -f gitops/values/dev/backend-api-values.yaml
helm template ai-service gitops/charts/ai-service -f gitops/values/dev/ai-service-values.yaml
helm template batch-job gitops/charts/batch-job -f gitops/values/dev/batch-job-values.yaml
```

### Dev Kubernetes Server Dry-run

```bash
helm template backend-api gitops/charts/backend-api -f gitops/values/dev/backend-api-values.yaml | kubectl apply --dry-run=server -f -
helm template ai-service gitops/charts/ai-service -f gitops/values/dev/ai-service-values.yaml | kubectl apply --dry-run=server -f -
helm template batch-job gitops/charts/batch-job -f gitops/values/dev/batch-job-values.yaml | kubectl apply --dry-run=server -f -
```

검증 결과:

```text
serviceaccount/moment-dev-backend-api-sa created (server dry run)
configmap/backend-api-config created (server dry run)
service/backend-api created (server dry run)
deployment.apps/backend-api created (server dry run)
ingress.networking.k8s.io/backend-api created (server dry run)

serviceaccount/moment-dev-ai-service-sa created (server dry run)
configmap/ai-service-config created (server dry run)
service/ai-service created (server dry run)
deployment.apps/ai-service created (server dry run)

serviceaccount/moment-dev-batch-job-sa created (server dry run)
configmap/batch-job-config created (server dry run)
cronjob.batch/batch-job created (server dry run)
```

### Prod Helm Render

```bash
helm template backend-api gitops/charts/backend-api -f gitops/values/prod/backend-api-values.yaml
helm template ai-service gitops/charts/ai-service -f gitops/values/prod/ai-service-values.yaml
helm template batch-job gitops/charts/batch-job -f gitops/values/prod/batch-job-values.yaml
```

Prod는 인프라 비활성 상태이므로, 현재 단계에서는 Helm render 기준으로 구조만 검증한다.

---

## 12. 장애 대응 기준

### ConfigMap 누락

- Pod describe에서 `configmap not found` 이벤트 확인
- values 파일의 `config` 항목 확인
- Helm render 결과의 ConfigMap name과 Deployment/CronJob의 configMapRef name 일치 여부 확인

### Secret 누락

- Pod describe에서 `secret not found` 이벤트 확인
- Secret name / key name 확인
- Secret 값은 출력하지 않고 `kubectl get secret`으로 존재 여부와 DATA 개수만 확인

### ServiceAccount 누락

- Pod describe에서 `serviceaccount not found` 이벤트 확인
- values 파일의 `serviceAccount.name` 확인
- Helm render 결과의 ServiceAccount name과 workload의 `serviceAccountName` 일치 여부 확인

### IRSA 권한 문제

- ServiceAccount annotation의 `eks.amazonaws.com/role-arn` 확인
- IAM Role trust policy의 namespace/serviceAccount subject 확인
- AWS API 호출 실패 시 `AccessDenied` 로그 확인

### Node Scheduling 문제

- Pod가 Pending이면 `kubectl describe pod`로 scheduling event 확인
- nodeSelector와 실제 node label이 일치하는지 확인
- Dev 기준 현재 node label은 `workload=core`, `capacity=on-demand`

---

## 13. M3-DEPLOY 인수인계

M3-DEPLOY-01에서는 Backend API가 아래 조건을 만족하는지 확인한다.

- Pod Running
- ConfigMap env 로드
- Secret env 로드
- ServiceAccount 적용
- Health check 통과
- Service/Ingress 생성

M3-DEPLOY-02에서는 AI Service와 Batch Job이 아래 조건을 만족하는지 확인한다.

- AI Service Pod Running
- Batch CronJob 생성
- ConfigMap env 로드
- Secret env 로드
- ServiceAccount 적용
- 필요한 AWS 접근 권한은 workload별 IRSA Role 기준으로 검증

---

## 14. Dev 기준 추가 검토 결과

### AI Service non-secret 설정

Dev AI Service ConfigMap에는 다음 non-secret runtime 설정을 포함한다.

| Key | 값 | 설명 |
|---|---|---|
| `ENVIRONMENT` | `dev` | 실행 환경 |
| `RUNTIME_PROFILE` | `dev` | AI Service runtime profile |
| `SERVER_PORT` | `8000` | AI Service container port 기준 |
| `AWS_REGION` | `ap-northeast-3` | AWS region |
| `LOG_LEVEL` | `DEBUG` | Dev log level |
| `MODEL_NAME` | `default` | 기본 모델명 placeholder |
| `OPENSEARCH_HOST` | Dev OpenSearch endpoint | 검색/벡터 저장소 endpoint |
| `BACKEND_API_URL` | `http://backend-api:8080` | 내부 Backend API endpoint |

`MODEL_NAME`은 현재 Dev 기본값으로 `default`를 사용한다. 실제 모델명이 확정되면 AI Service values에서 교체한다.

### Batch Job 운영 메타데이터

Dev Batch Job ConfigMap에는 다음 non-secret 운영 메타데이터를 포함한다.

| Key | 값 | 설명 |
|---|---|---|
| `BATCH_JOB_NAME` | `public-data-collector` | 배치 작업 식별 이름 |
| `TRIGGER_TYPE` | `cron` | 실행 방식 |
| `UPDATE_FREQUENCY` | `hourly` | 갱신 주기 |
| `SCHEDULE_CRON` | `0 * * * *` | CronJob schedule 기준 |

실제 CronJob schedule은 Helm values의 `schedule` 값으로도 관리한다.

### Secrets Manager read 권한 기준

현재 M3-CONFIG-01에서는 Kubernetes Secret 수동 생성 방식을 선택했다.

따라서 Backend API, AI Service, Batch Job Pod가 런타임에 AWS Secrets Manager에서 Secret 값을 직접 읽는 구조가 아니다.
이에 따라 workload별 IRSA Role에는 Secrets Manager read 권한을 기본 포함하지 않는다.

추후 External Secrets Operator 또는 애플리케이션 직접 조회 방식으로 전환할 경우, 각 workload IRSA Role에 `secretsmanager:GetSecretValue` 권한을 추가한다.

### CloudWatch Logs write 권한 기준

현재 Pod 로그는 애플리케이션이 stdout/stderr로 출력하고, 클러스터 로그 수집 계층에서 처리하는 구조를 기준으로 한다.

따라서 애플리케이션 Pod가 AWS CloudWatch Logs API를 직접 호출하는 구조가 아니므로 workload별 IRSA Role에는 `logs:PutLogEvents` 등 CloudWatch Logs write 권한을 기본 포함하지 않는다.

추후 애플리케이션이 CloudWatch Logs SDK를 직접 호출하는 구조로 변경될 경우, 해당 workload IRSA Role에 필요한 logs 권한을 추가한다.

### OpenSearch credential 기준

현재 Dev OpenSearch 접근은 VPC 내부 endpoint 기준으로 구성하며, 별도 username/password credential을 Secret으로 주입하지 않는다.

따라서 OpenSearch credential secretKeyRef는 현재 미사용으로 정리한다.
추후 OpenSearch fine-grained access control 또는 별도 인증 방식이 활성화되면 Secret key를 추가한다.

### Mock profile / OpenAI API Key 기준

AI Service는 `OPENAI_API_KEY`를 Secret으로 참조한다.

Dev 환경에서 실제 LLM 호출이 필요한 경우 `moment-dev-ai-service-secret`에 실제 OpenAI API Key를 등록한다.
Mock profile로 실행할 경우에는 애플리케이션 코드에서 mock profile 기준을 별도로 제공해야 하며, 현재 GitOps values는 실제 Secret reference 구조를 기준으로 작성한다.

실제 LLM 호출 검증은 배포 이후 smoke test 범위에서 수행한다.
