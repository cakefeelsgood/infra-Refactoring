# M5-HA-01 EKS Workload 고가용성 기준 구성

## 목표

Backend API, AI Service, Batch Worker가 장애 상황에서도 안정적으로 동작할 수 있도록
Deployment replica, RollingUpdate, PodDisruptionBudget, podAntiAffinity, probe, resource 기준을
GitOps 원본 values 기준으로 보완한다.

> Batch는 CronJob이 아닌 SQS polling Worker Deployment(`mode: worker`) 모드로 운영된다.

---

## 노드그룹 구성

| NodeGroup | 타입 | Zone | workload label | 용도 |
|-----------|------|------|----------------|------|
| moment-prod-core-on-demand-ng | t3.medium × 2 | 3a, 3c | core | backend-api |
| moment-prod-ops-on-demand-ng | t3.medium × 2 | 3a, 3c | ops | monitoring |
| moment-prod-batch-on-demand-ng | t3.medium × 1 | 3c | batch | batch-worker |
| moment-prod-ai-spot-ng | t3.large × 1 | 3c | ai | ai-service |

---

## HA 기준 요약

### Backend API

| 항목 | Dev | Prod |
|------|-----|------|
| replicaCount | 1 (HPA min:1 max:2) | 2 (HPA 비활성) |
| RollingUpdate maxSurge | 1 | 1 |
| RollingUpdate maxUnavailable | 1 | 0 (무중단) |
| PDB minAvailable | 비활성 (replica 1) | 1 |
| nodeSelector | workload:core / capacity:on-demand | workload:core / capacity:on-demand |
| podAntiAffinity | preferred / zone 분산 | preferred / zone 분산 |
| readinessProbe | tcpSocket:8080 | tcpSocket:8080 |
| livenessProbe | tcpSocket:8080 | tcpSocket:8080 |
| resources requests | cpu:250m / memory:512Mi | cpu:500m / memory:1Gi |
| resources limits | cpu:500m / memory:1Gi | cpu:1000m / memory:2Gi |

**결정 근거:**
- Prod replica 2 + core 노드 2개(3a/3c) → podAntiAffinity로 AZ 분산 보장
- maxUnavailable:0 → Rolling Update 중 항상 2개 Pod 유지
- PDB minAvailable:1 → 노드 drain 시에도 최소 1개 서비스 유지
- Dev는 replica 1이므로 PDB 적용 시 drain 불가 → 비활성

---

### AI Service

| 항목 | Dev | Prod |
|------|-----|------|
| replicaCount | 1 | 2 |
| RollingUpdate maxSurge | 1 | 1 |
| RollingUpdate maxUnavailable | 1 | 0 (무중단) |
| PDB minAvailable | 비활성 (replica 1) | 1 |
| nodeSelector | workload:core / capacity:on-demand | workload:ai / capacity:spot |
| tolerations | 없음 | workload:ai, capacity:spot NoSchedule |
| readinessProbe | httpGet /health:8000 | httpGet /health:8000 |
| livenessProbe | httpGet /health:8000 | httpGet /health:8000 |
| resources requests | cpu:250m / memory:512Mi | cpu:500m / memory:1Gi |
| resources limits | cpu:500m / memory:1Gi | cpu:1000m / memory:2Gi |

**결정 근거:**
- Prod는 Spot 노드 배치 → Spot 중단 시 재스케줄 보장을 위해 PDB 적용
- maxUnavailable:0 → Spot 중단 + Rolling Update 겹쳐도 서비스 유지
- Dev는 core On-Demand 배치 (Spot 노드 없음)

---

### Batch Worker

| 항목 | Dev | Prod |
|------|-----|------|
| mode | worker (Deployment) | worker (Deployment) |
| replicaCount | 1 | 1 |
| RollingUpdate maxSurge | 1 | 1 |
| RollingUpdate maxUnavailable | 1 | 1 |
| PDB | 비활성 | 비활성 |
| nodeSelector | workload:batch / capacity:spot | workload:batch / capacity:on-demand |
| tolerations | workload:batch NoSchedule | workload:batch NoSchedule |
| resources requests | cpu:250m / memory:512Mi | cpu:500m / memory:1Gi |
| resources limits | cpu:500m / memory:1Gi | cpu:1000m / memory:2Gi |

**결정 근거:**
- Batch는 SQS polling worker → 재시작 시 메시지 재처리 가능 (at-least-once)
- replica 1에 PDB minAvailable:1 적용 시 노드 drain 불가 → 의도적으로 비활성
- maxUnavailable:1 허용 → 잠깐 중단되어도 SQS에서 재처리
- Prod는 On-Demand 배치 (안정적 장시간 polling), Dev는 Spot 허용

---

## Helm Chart 변경 사항

### 신규 추가 파일

- `gitops/charts/backend-api/templates/pdb.yaml`
- `gitops/charts/ai-service/templates/pdb.yaml`

### 수정 파일

- `gitops/charts/backend-api/templates/deployment.yaml` — `strategy` 블록 추가
- `gitops/charts/ai-service/templates/deployment.yaml` — `strategy` 블록 추가
- `gitops/charts/*/values.yaml` — chart 기본값 기준 정비
- `gitops/values/dev/*.yaml` — dev 환경 HA 기준 반영
- `gitops/values/prod/*.yaml` — prod 환경 HA 기준 반영

---

## helm template 검증 결과

```bash
# backend-api prod
helm template backend-api-prod gitops/charts/backend-api \
  -f gitops/values/prod/backend-api-values.yaml

# ai-service prod
helm template ai-service-prod gitops/charts/ai-service \
  -f gitops/values/prod/ai-service-values.yaml

# batch-job prod
helm template batch-job-prod gitops/charts/batch-job \
  -f gitops/values/prod/batch-job-values.yaml
```

검증 항목:

| 항목 | backend-api prod | ai-service prod | batch-job prod |
|------|:---:|:---:|:---:|
| PodDisruptionBudget | ✅ | ✅ | ✅ 비활성 |
| strategy RollingUpdate | ✅ | ✅ | ✅ |
| maxUnavailable:0 | ✅ | ✅ | N/A |
| nodeSelector | ✅ core/on-demand | ✅ ai/spot | ✅ batch/on-demand |
| tolerations | N/A | ✅ spot | ✅ |
| podAntiAffinity | ✅ | N/A | N/A |
| mode: worker (Deployment) | N/A | N/A | ✅ |

---

## 후행 작업

- M5-HA-02: HPA 검증 시 본 문서의 replica 기준 참조
- M5-DRILL-01: 장애 주입 테스트 시 PDB/RollingUpdate 동작 확인
- M5-SEC-03: NetworkPolicy 작성 시 replica 구조 참조
