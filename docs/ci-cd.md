# CI/CD 구조 문서
 
## 개요
 
M3-CICD-01에서 구성한 GitHub Actions 기반 CI 품질 게이트 문서입니다.
PR 생성 시 자동으로 빌드/테스트/타입체크를 실행하고, 실패 시 merge를 차단합니다.
 
---
 
## 레포 구조
 
| 레포 | 서비스 | 언어/프레임워크 |
|------|--------|----------------|
| msp-team04-backend | Backend API + Batch Job | Java 17 / Spring Boot |
| msp-team04-ai | AI Service | Python 3.13 / FastAPI |
| moment-app-base | Frontend | TypeScript / Expo React Native |
| msp-team04-infra | 인프라/GitOps | - |
 
---
 
## CI 품질 게이트 구조
 
### Backend (msp-team04-backend)
 
- **workflow 파일**: `.github/workflows/backend-ci.yml`
- **trigger**: `pull_request` → develop, main / `push` → develop / `workflow_dispatch`
- **job name**: `Backend API - Build & Test`
- **CI 검증 명령어**:
  ```bash
  ./gradlew clean test
  ./gradlew bootJar
  ```
- **Spring profile**: `ci` (`application-ci.properties` 사용)
- **제외 테스트**: `MomentBackendApplicationTests`, `publicdata/**`, `RecommendationIntegrationTest`, `TestMomentBackendApplication`
- **빌드 산출물**: `build/libs/*.jar`
### AI Service (msp-team04-ai)
 
- **workflow 파일**: `.github/workflows/ai-ci.yml`
- **trigger**: `pull_request` → develop, main / `push` → develop
- **job name**: `AI Service - Install & Import Check`
- **CI 검증 명령어**:
  ```bash
  pip install -r requirements.txt
  python -c "from main import app"
  curl http://localhost:8000/health
  ```
- **환경변수**: `OPENAI_API_KEY=ci-dummy-key` (실제 API 호출 없음)
### Frontend (moment-app-base)
 
- **workflow 파일**: `.github/workflows/frontend-ci.yml`
- **trigger**: `pull_request` → develop, main / `push` → develop
- **job name**: `Frontend - Install & Typecheck & Lint`
- **CI 검증 명령어**:
  ```bash
  npm ci
  npx tsc --noEmit
  npx eslint .
  ```
- **환경변수**: `EXPO_PUBLIC_API_BASE_URL=http://localhost:8080`
---
 
## Branch Protection 설정
 
develop 브랜치에 required status check 등록 완료.
CI 통과 안 하면 merge 불가.
 
| 레포 | Required Status Check |
|------|-----------------------|
| msp-team04-backend | `Backend API - Build & Test` |
| msp-team04-ai | `AI Service - Install & Import Check` |
| moment-app-base | `Frontend - Install & Typecheck & Lint` |
 
---
 
## M3-CICD-02 연결 기준 (Docker Build & ECR Push)
 
| 서비스 | 빌드 산출물 | 비고 |
|--------|------------|------|
| backend-api | `build/libs/*.jar` | `./gradlew bootJar` |
| ai-service | - | `uvicorn main:app` entrypoint |
| batch-job | `build/libs/*.jar` | Backend와 동일 jar 사용 |
 
- **ECR Push workflow**: `.github/workflows/backend-build-push.yml`
- **trigger**: `push` → develop only (PR 시 미실행)
---
 
## M3-CICD-03 연결 기준 (Image Tag)
 
| 구분 | tag 기준 | 예시 |
|------|---------|------|
| dev | short sha | `abc1234` |
| dev latest | latest | `latest` |
| prod | 추후 결정 | `v1.0.0` 또는 `release-sha` |
 
- short sha 추출: `github.sha` 사용 (backend-build-push.yml 참고)
---
 
## M3-GITOPS-02 서비스 이름
 
| 서비스 | 이름 |
|--------|------|
| Backend API | `backend-api` |
| AI Service | `ai-service` |
| Batch Job | `batch-job` |
 
---
 
## M3-VALID-A CI 검증 절차
 
### 로컬 검증 명령어
 
**Backend**
```bash
./gradlew clean test
./gradlew bootJar
```
 
**AI Service**
```bash
pip install -r requirements.txt
python -c "from main import app"
```
 
**Frontend**
```bash
npm ci
npx tsc --noEmit
npx eslint .
```
 
### GitHub Actions 로그 확인 절차
 
1. PR 생성 후 Actions 탭 이동
2. 해당 workflow run 클릭
3. 실패한 step 클릭 → 로그 확인
4. Backend의 경우 Artifacts에서 `backend-gradle-test-report` 다운로드 가능
---
 
## 보안 정책
 
- AWS Access Key, OpenAI API Key, DB password, JWT secret 등 모든 민감정보는 GitHub Secrets 또는 CI용 dummy값 사용
- `.env` 파일 커밋 금지 (`.gitignore` 적용)
- CI에서 실제 외부 API 호출 없음
- Actions 로그에 secret 값 마스킹 처리됨

- Role ARN: `arn:aws:iam::611058323802:role/moment-dev-github-actions-role`
- 허용 레포: `msp-team04-backend`, `msp-team04-ai` (develop 브랜치)
- 권한 범위: ECR 3개 레포 Push/Pull만 허용 (관리자 권한 없음)
- workflow 설정:
```yaml
  permissions:
    id-token: write
    contents: read
```

---

### ECR Repository 매핑

| 서비스 | ECR Repository | 비고 |
|--------|---------------|------|
| Backend API | `moment-dev-backend-api` | Spring Boot |
| AI Service | `moment-dev-ai-service` | FastAPI |
| Batch Job | `moment-dev-batch-job` | Backend와 동일 Dockerfile |

- 태그 정책: **IMMUTABLE** (동일 tag 재Push 불가)
- scan on push: 활성화

---

### Image Tag 정책

| 환경 | tag 형식 | 예시 | 기준 |
|------|---------|------|------|
| Dev | `dev-{short_sha}` | `dev-8e073f4` | develop push 시 |
| Prod | `prod-{version}` | `prod-v1.0.0` | release tag 시 (추후 구성) |

- `latest` 태그 사용 안 함
- short SHA: `${GITHUB_SHA::7}`

---

### Workflow 구조

| 레포 | workflow 파일 | trigger | 동작 |
|------|-------------|---------|------|
| msp-team04-backend | `backend-build-push.yml` | develop push | Backend API + Batch Job 빌드/Push |
| msp-team04-ai | `ai-ci-build-push.yml` | develop push | AI Service 빌드/Push |

- PR 시: Docker Build 미실행 (CI 품질 게이트만 실행)
- develop push 시: Dev ECR Push 실행
- Prod Push: 추후 release tag 기준으로 별도 workflow 구성 예정
- 멀티 레포 구조로 path filter 없이도 서비스별 독립 빌드 가능

---

### Docker Build 설정

#### Backend API / Batch Job

- Dockerfile: `msp-team04-backend/Dockerfile`
- 멀티스테이지 빌드 (Gradle build → eclipse-temurin:17-jre-alpine)
- EXPOSE: 8080
- health endpoint: `/health`
- Docker Buildx + GHA cache 적용 (`scope=backend`, `scope=batch`)

#### AI Service

- Dockerfile: `msp-team04-ai/Dockerfile`
- Python 3.13-slim
- EXPOSE: 8000
- 실행 command: `uvicorn main:app --host 0.0.0.0 --port 8000`
- Docker Buildx + GHA cache 적용 (`scope=ai-service`)
- OpenAI API Key 없이 빌드 가능 (빌드 시 외부 API 호출 없음)

---

### Image Metadata (OCI Label)

모든 이미지에 아래 label 포함:

| Label | 값 |
|-------|-----|
| `org.opencontainers.image.revision` | commit SHA |
| `org.opencontainers.image.source` | GitHub repository URL |
| `org.opencontainers.image.created` | 빌드 시간 |
| `service` | `backend-api` / `ai-service` / `batch-job` |

---

### M3-CICD-03 연계 산출물

각 workflow 실행 후 artifact로 저장됨 (retention: 7일)

| artifact 이름 | 파일 | 변수 |
|--------------|------|------|
| `backend-image-info` | `image-info.env` | `BACKEND_IMAGE_URI`, `BATCH_JOB_IMAGE_URI`, `IMAGE_TAG`, `BACKEND_DIGEST`, `BATCH_DIGEST` |
| `ai-image-info` | `image-info.env` | `AI_SERVICE_IMAGE_URI`, `IMAGE_TAG`, `AI_DIGEST` |

M3-CICD-03에서 사용할 변수명:
- `BACKEND_IMAGE_URI`
- `AI_SERVICE_IMAGE_URI`
- `BATCH_JOB_IMAGE_URI`
- `IMAGE_TAG`

---

### 트러블슈팅

#### OIDC Assume Role 실패 시
1. workflow `permissions: id-token: write` 설정 확인
2. Role trust policy에 해당 레포/브랜치 허용 여부 확인
3. `aws sts get-caller-identity` step 로그 확인
4. GitHub Actions → Settings → OIDC 설정 확인

#### ECR Push 실패 시
1. OIDC 인증 성공 여부 확인
2. ECR Login step 성공 여부 확인
3. IAM Role ECR Push 권한 확인
4. ECR Repository 이름 오타 확인

#### Docker Build 실패 시
1. Dockerfile 경로 확인 (`context: .`)
2. `.dockerignore` 확인
3. 빌드 로그에서 실패 step 확인
4. Backend: Gradle bootJar 성공 여부 확인
5. AI: `requirements.txt` 패키지 설치 오류 확인

#### Tag Immutable 충돌 발생 시
- 동일 commit SHA로 재실행 시 tag 충돌 발생
- 대응 방법: 새 커밋 생성 후 재실행
- 또는 workflow_dispatch로 수동 실행 시 run number를 tag에 포함하는 방식 검토
- 같은 tag 재사용 금지

---

### ECR Scan 결과 확인 방법

1. AWS ECR 콘솔 → 해당 레포지토리 → 이미지 선택
2. **세부 정보** 클릭 → **스캐닝 및 취약성** 섹션 확인
3. 취약성 등급: 중요 / 높음 / 보통 / 낮음 / 정보
4. scan on push로 자동 실행 (24시간 1회 제한)

### Prod Image Push 전략 (예정)

- Prod ECR은 release 시점(3일 운영)에 생성 예정
- Prod Push trigger: release tag (`v*.*.*`) 또는 `workflow_dispatch`
- Prod image tag: `prod-{version}` 또는 `prod-{git_tag}`
- Prod Push workflow는 Dev workflow와 분리하여 별도 파일로 구성
- Prod OIDC Role 권한은 Dev와 동일하게 ECR 범위로만 제한
- Prod 자동 배포는 M3-PROMOTE-01에서 수행
---

## Image Tag Update 흐름 (M3-CICD-03)

### 전체 흐름

develop push
    -> backend-build-push.yml / ai-ci-build-push.yml (ECR Push)
    -> Trigger Helm values update (workflow_dispatch -> infra 레포)
    -> update-helm-values.yml (values 파일 image tag 갱신)
    -> [skip ci] commit -> develop push
    -> ArgoCD가 변경 감지 -> 자동 배포

### Image Tag Update workflow

- workflow 파일: msp-team04-infra/.github/workflows/update-helm-values.yml
- trigger: workflow_dispatch (backend/ai build workflow에서 자동 호출)
- 수정 대상 파일:

| 서비스 | 파일 |
|--------|------|
| backend-api | gitops/values/dev/backend-api-values.yaml |
| ai-service | gitops/values/dev/ai-service-values.yaml |
| batch-job | gitops/values/dev/batch-job-values.yaml |

- 수정 필드: .image.tag, .image.repository (필요 시)
- tag 형식: dev-{short_sha}
- yq 명령 예시:

IMAGE_TAG="dev-abc1234" yq -i '.image.tag = strenv(IMAGE_TAG)' gitops/values/dev/backend-api-values.yaml
IMAGE_REPOSITORY="xxx.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-backend-api" yq -i '.image.repository = strenv(IMAGE_REPOSITORY)' gitops/values/dev/backend-api-values.yaml

### 렌더링 검증 항목

update-helm-values.yml 내에서 values 수정 후 자동으로 아래 항목 검증:

| 검증 항목 | 방법 |
|-----------|------|
| image tag 반영 | helm template 결과에서 tag grep |
| namespace | moment-dev 포함 여부 확인 |
| Secret 평문 노출 | secretKeyRef/valueFrom 제외 후 pattern match |
| credential 노출 | AWS_ACCESS_KEY_ID 등 grep |
| selector/label 일치 | matchLabels vs labels grep |
| ServiceAccount 참조 | kind: ServiceAccount 존재 여부 |

- 검증 실패 시 commit 미실행 (exit 1)
- 렌더링 결과는 artifact로 저장 (retention: 7일)

---

## 무한 루프 방지 정책

### 방지 전략

| 전략 | 적용 여부 | 설명 |
|------|-----------|------|
| [skip ci] commit message | 적용 | infra values update commit에 [skip ci] 포함 |
| GitOps 레포 분리 | 적용 | msp-team04-infra 별도 레포 -> backend/ai workflow 트리거 안 됨 |
| PR trigger 미사용 | 적용 | build workflow는 push만 trigger, PR 시 미실행 |
| Prod 자동 trigger 없음 | 적용 | Prod values update는 M3-PROMOTE-01에서만 수행 |

### 루프 방지 흐름

backend push -> build workflow -> infra workflow_dispatch 호출
infra workflow -> [skip ci] commit push
-> GitHub Actions가 [skip ci] 감지 -> workflow 실행 안 함

### 주의사항

- infra 레포 commit message에서 [skip ci] 제거 시 무한 루프 발생 가능
- backend/ai workflow에서 workflow_dispatch로 infra를 호출하는 구조이므로
  infra의 push가 다시 backend/ai를 트리거하지 않음 (레포 분리)
- gitops 경로 path ignore는 레포 분리로 인해 불필요

---

## 장애 대응 절차 (M3-CICD-03)

### ECR Push 성공 후 values update가 실행되지 않을 때

1. backend/ai 레포 Actions 탭에서 build workflow 로그 확인
2. Trigger Helm values update step 성공 여부 확인
3. GITOPS_TOKEN secret 등록 여부 확인 (backend, ai 레포 둘 다)
4. infra 레포 Actions 탭에서 update-helm-values.yml 실행 여부 확인
5. GITOPS_TOKEN 권한 확인 (infra 레포 write 권한 필요)

### yq 수정 실패 시

1. workflow 로그에서 Install yq step 성공 여부 확인
2. yq 버전 확인: yq --version
3. values 파일 경로 확인: ls gitops/values/dev/
4. 수동 테스트: IMAGE_TAG="dev-abc1234" yq -i '.image.tag = strenv(IMAGE_TAG)' gitops/values/dev/backend-api-values.yaml

### values 파일 path 오류 시

1. workflow 로그에서 ERROR: values file not found 메시지 확인
2. infra 레포 develop 브랜치에서 파일 존재 여부 확인: ls gitops/values/dev/
3. service 입력값 오타 확인 (backend-api, ai-service, batch-job, all)

### image tag field path 오류 시

1. values 파일에서 .image.tag 필드 존재 여부 확인
2. 로컬에서 yq 직접 테스트: yq '.image.tag' gitops/values/dev/backend-api-values.yaml
3. YAML 들여쓰기 오류 확인

### Helm lint 실패 시

1. workflow 로그에서 helm lint 오류 메시지 확인
2. 로컬에서 직접 실행: helm lint gitops/charts/backend-api -f gitops/values/dev/backend-api-values.yaml
3. Chart.yaml 필드 누락 여부 확인
4. templates 디렉토리 파일 문법 오류 확인

### Helm template 렌더링 실패 시

1. workflow 로그에서 helm template 오류 메시지 확인
2. 로컬에서 직접 실행: helm template backend-api gitops/charts/backend-api -f gitops/values/dev/backend-api-values.yaml
3. values 파일에서 필수 필드 누락 여부 확인
4. template 파일에서 존재하지 않는 values 참조 여부 확인

### 렌더링 결과에 image tag가 반영되지 않을 때

1. values 파일에서 image.tag 값 직접 확인: yq '.image.tag' gitops/values/dev/backend-api-values.yaml
2. deployment.yaml이 templates 디렉토리에 존재하는지 확인: ls gitops/charts/backend-api/templates/
3. template 파일에서 image 필드 확인: cat gitops/charts/backend-api/templates/deployment.yaml

### Git commit 또는 push 실패 시

1. workflow 로그에서 git push 오류 메시지 확인
2. GITHUB_TOKEN 권한 확인 (contents: write 필요)
3. develop 브랜치 protection rule 확인
4. 충돌 발생 시 infra 레포 develop 브랜치 최신화 후 재실행

### GitOps update commit 무한 루프 발생 시

1. infra 레포 Actions 탭에서 연속 실행 여부 확인
2. commit message에 [skip ci] 포함 여부 확인: git log --oneline -5
3. [skip ci] 없으면 update-helm-values.yml commit 메시지 수정 후 재배포
4. 레포 분리 구조 확인 (infra push가 backend/ai workflow 트리거하지 않아야 함)

### ArgoCD가 values 변경을 감지하지 못할 때

1. ArgoCD Application targetRevision이 develop인지 확인: argocd app get backend-api-dev
2. ArgoCD repo connection 상태 확인: argocd repo list
3. infra 레포 develop 브랜치에 실제 변경이 push 됐는지 확인: git log --oneline -3
4. ArgoCD UI에서 Refresh 수동 실행
5. automated sync 설정 확인: cat gitops/argocd/dev/applications/backend-api-dev.yaml

---

## M3-PROMOTE-01 연계용 Prod values 승격 기준

Prod values 파일은 develop push로 자동 변경되지 않는다.
Prod values 변경은 M3-PROMOTE-01 승격 workflow에서 승인 기반으로 수행한다.

| 서비스 | Prod values 파일 | 수정 필드 |
|--------|-----------------|-----------|
| backend-api | gitops/values/prod/backend-api-values.yaml | .image.tag, .image.repository |
| ai-service | gitops/values/prod/ai-service-values.yaml | .image.tag, .image.repository |
| batch-job | gitops/values/prod/batch-job-values.yaml | .image.tag, .image.repository |

Prod image tag 형식: prod-{version} 또는 prod-{short_sha}
Prod ArgoCD manual sync 대상: backend-api-prod, ai-service-prod, batch-job-prod (M3-ARGO-03에서 구성)
Prod rollback: Git revert로 이전 tag로 되돌린 후 Prod ArgoCD sync

## ArgoCD values 변경 감지 흐름

develop push
    -> build workflow (ECR Push)
    -> update-helm-values.yml (values image tag 갱신)
    -> [skip ci] commit -> infra 레포 develop push
    -> Dev ArgoCD가 develop 브랜치 변경 감지 (polling 또는 webhook)
    -> backend-api-dev / ai-service-dev / batch-job-dev OutOfSync 감지
    -> automated sync 실행 (selfHeal: true)
    -> moment-dev namespace에 새 image 배포

ArgoCD refresh 수동 실행: argocd app refresh backend-api-dev
ArgoCD sync 수동 실행: argocd app sync backend-api-dev
