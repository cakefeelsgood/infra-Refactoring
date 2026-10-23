# PLAN.md — Karpenter Spot 혼합 운영 + VPC CNI Prefix Delegation 고도화

> 코드 수정만 한다. 배포 없음. 규칙은 `CLAUDE.md`를 따른다.
> 경로는 develop(a2e4de6) 기준이다. 2026-10-23에 실제 코드와 대조해 경로·줄 번호·전제를 고쳤다(4절 각 Phase의 "코드 대조" 참고).
> 작업 브랜치: `feat/karpenter-spot-vpc-cni`. 증거: `docs/karpenter-vpc-cni-refactoring/evidence/`, 결과: `docs/karpenter-vpc-cni-refactoring/RESULT.md`.

## 1. 목표

### 목표 1. Karpenter 기반 On-Demand + Spot 혼합 노드 운영과 장애 대응
문제
- 모든 Worker Node를 OD로 운영하면 HPA 증설 용량까지 높은 비용을 부담한다.
- Spot을 섞으면 노드 회수나 HPA 스케일 인 때 기본 OD Pod가 삭제되어 가용성이 떨어질 수 있다.
- 초기 부하 테스트에서 Spot에 가야 할 증설 Pod 12개 중 10개가 OD에 배치됐다. Spot 우선 배치를 설정했지만 강제하지 않아 생긴 문제다.

해결 (코드로 반영할 것)
- 기본 용량과 증설 용량 분리: NodePool을 OD와 Spot으로 분리, Mutating Webhook으로 HPA 최소 복제본은 OD, 초과분은 Spot에 배치
- OD 노드에 taint, 기본 Pod에만 toleration → Spot 증설 Pod가 OD에 배치되지 않게 강제
- `pod-deletion-cost`: 기본 Pod `1000`, 증설 Pod `-1000` → HPA 축소 시 Spot Pod 우선 삭제
- Spot 회수 대응: EventBridge + SQS 기반 Karpenter interruption queue, `preStop 20s`, `terminationGracePeriodSeconds 60`
- 가용성: Topology Spread + Pod Anti-Affinity로 노드·AZ 분산, PDB로 자발적 중단 시 가용 Pod 보호

기대 결과(실험 수치, n=3, 4가지 설정 묶음 효과): 스케일 인 시 Spot 12개 우선 삭제·OD 4개 유지 / FIS Spot 중단 시 비 2xx 평균 711.7 → 0 / 16개 Pod Ready 복귀 평균 190.3초 → 46초

### 목표 2. VPC CNI Pod 수용량 한계 개선: PD 적용과 maxPods 정합성
문제
- Secondary IP 방식은 노드당 Pod 수가 ENI/IP 한도에 묶인다(t3.medium 17개).
- `WARM_IP_TARGET=1`만 낮추면 Pod 동시 생성 시 IP를 하나씩 받아와 p95가 66초까지 늘었다.
- PD와 kubelet maxPods가 어긋나면 Pod가 `ContainerCreating`에 멈추고 Karpenter도 노드를 추가하지 않는다.

해결 (코드로 반영할 것)
- `ENABLE_PREFIX_DELEGATION=true` + EC2NodeClass `kubelet.maxPods=40`을 **같은 변경으로 묶어서** 반영
- 노드 생성 시 `allocatable.pods`와 PD 적용 여부가 맞는지 확인할 수 있는 장치(정적 검증 스크립트 + 런북)
- `WARM_IP_TARGET=1`, `MINIMUM_IP_TARGET=3` 적용
- PD는 /28 단위로 서브넷 IP를 더 쓰므로 적용 전 서브넷 여유 확인 절차를 문서화하고, 서브넷 크기를 결정

기대 결과(실험 수치, t3.medium, Pod 100개): 노드당 최대 Pod 17 → 40, 필요 노드 8 → 4 / 동시 생성 p95 66초(Secondary + WARM_IP 1) → 3초(PD + Warm 조정) / 서브넷 IP 소비는 Secondary 대비 PD 기본값 +19%, Warm 조정 후 +7%

## 2. 현재 상태 (develop a2e4de6 분석 결과)
| 영역 | 현재 |
|---|---|
| 구조 | `terraform/{environments/{dev,prod,network,shared},modules/*}`, `gitops/{argocd,apps,charts,values}`, `monitoring/`, `docs/` |
| 노드 | Karpenter 없음. `modules/eks-nodegroup` MNG만 있음. prod 5개(core / batch OD / batch spot / ai spot / ops), dev 4개(core / batch spot / ai spot / ops), 모두 t3 |
| EKS | 1.35, ap-northeast-3. `modules/eks`에 관리형 애드온만 있음. EC2NodeClass·NodePool·Karpenter IAM·SQS 없음 |
| VPC CNI | v1.21.1-eksbuild.1. PD, WARM_*, maxPods 설정 없음. **IRSA 없음**(노드 Role의 `AmazonEKS_CNI_Policy` 사용) |
| 기존 버그 | `modules/eks` addons 타입에 `configuration_values`가 없어 `enableNetworkPolicy`가 조용히 버려짐 |
| 서브넷 | prod/dev private app `/24 × 2`. `karpenter.sh/discovery` 태그 없음. 노드 SG를 따로 만들지 않고 EKS 클러스터 primary SG 사용 |
| IAM 방식 | 컨트롤러는 모두 IRSA(`modules/iam`, `workload-irsa`, `external-secrets-irsa`, `*-irsa.tf`). Pod Identity 에이전트 애드온 없음 |
| GitOps | App-of-Apps(`gitops/argocd/<env>/root-application.yaml`가 `gitops/argocd/<env>` 재귀 동기화). 앱별 AppProject, CRD는 별도 앱 |
| Helm | 자체 차트 `backend-api`, `ai-service`, `batch-job`. `tolerations`/`nodeSelector`/`affinity` 슬롯은 있음. `terminationGracePeriodSeconds`, `lifecycle.preStop`, `topologySpreadConstraints` 슬롯 없음. PDB 템플릿은 backend-api·ai-service만 있음. HPA는 backend-api만 있음 |
| CI | `.github/workflows/update-helm-values.yml` 하나(이미지 태그 갱신 시 helm lint/template). Terraform·정합성 검증 CI 없음 |

실험 환경과의 차이: 리전(실험 ap-northeast-2 / 현재 ap-northeast-3), K8s 버전(실험 1.36·1.37 / 현재 1.35), 서브넷 크기(실험 /19 / 현재 /24). 실험 값을 그대로 옮기지 않는다.

## 3. 결정 (2026-10-23, 사용자 위임에 따라 결정하고 근거를 기록)
| # | 결정 | 근거 |
|---|---|---|
| D1 | Karpenter **1.15.0**(실험 버전, `public.ecr.aws/karpenter/karpenter` 1.15.0 차트 존재 확인). 리전·K8s 버전은 변경 없음. **VPC CNI 버전은 v1.21.1 유지** | PD는 CNI 1.9.0+에서 지원되므로 버전 변경이 목표에 필요 없다. v1.23.2와 K8s 1.35의 호환은 AWS 조회 없이 확인할 수 없다(조회 금지). Karpenter 1.15 ↔ K8s 1.35 호환은 배포 전 공식 호환 표로 확인해야 한다(RESULT.md 배포 전 확인 목록) |
| D2 | 기존 `/24` private app 서브넷은 **그대로 두고**, Karpenter 노드 전용 서브넷 `/20 × 2`를 같은 VPC CIDR 안에 추가한다(prod `10.10.32.0/20`, `10.10.48.0/20` / dev `10.20.32.0/20`, `10.20.48.0/20`). `karpenter.sh/discovery` 태그는 새 서브넷에만 붙인다 | 기존 서브넷 CIDR을 바꾸면 서브넷이 재생성되고, 그 위의 EKS 컨트롤 플레인 ENI·노드·VPC 엔드포인트가 함께 교체된다. 새 서브넷은 기존 private app 라우트 테이블에 연결해 egress·S3 게이트웨이 엔드포인트 경로를 그대로 쓴다. 데이터 계층 SG는 클러스터 primary SG를 소스로 허용하므로 CIDR 규칙 추가가 필요 없다. /24에 남는 MNG(core/ops)는 PD 적용 후 /28 여유를 런북으로 확인한다 |
| D3 | OD NodePool taint 유지(실험 D-004) | Spot 용량 부족 시 증설 Pod는 OD로 넘어가지 않고 Pending이 된다. 문서에 트레이드오프를 적는다 |
| D4 | 웹훅은 **replicas 1 + Recreate 유지**, `failurePolicy: Ignore` + 코드에 `FAIL_OPEN`(조회 실패 시 변경 없이 허용) 추가, `objectSelector`로 opt-in 라벨이 붙은 Pod만 대상. 서비스 차트에 `capacitySplit.enabled` 게이트를 두고 **기본값 false**(웹훅 이미지가 ECR에 올라간 뒤 켠다) | 실험 `DESIGN.md`: 결정 상태가 메모리에 있어서 replica 2개면 base 개수가 깨진다 → replicas ≥ 2는 재설계 없이 불가. `failurePolicy: Ignore`만으로는 코드가 명시적으로 deny하는 경우를 못 막으므로 코드도 fail-open으로 바꾼다. fail-open이면 Pod는 템플릿 기본값(Spot toleration)으로 생성되고 deletion-cost가 없다. 이미지가 없는 상태에서 게이트를 켜면 모든 Pod가 이 상태가 되므로 기본값은 끔(현재와 같은 전부 OD) |
| D5 | MNG는 최종적으로 `core`(시스템 애드온)와 `ops`(컨트롤러, Karpenter 포함)만 남긴다. prod `batch_on_demand`·`batch_spot`·`ai_spot`, dev `batch_spot`·`ai_spot`은 `module.<env>_eks_legacy_nodegroups`로 옮기고(`moved` 블록, 재생성 없음) `enable_<env>_legacy_workload_nodegroups`(기본 true)로 제거 시점을 분리한다(리뷰 반영). 모든 MNG에 maxPods 40(launch template user_data, nodeadm `NodeConfig`) | Karpenter 컨트롤러는 Karpenter가 띄운 노드에 올라가면 안 된다(차트 기본 affinity가 `karpenter.sh/nodepool DoesNotExist`) |
| D6 | NodePool requirements: `instance-category In [c,m,r]`, `instance-generation Gt 4`, `instance-size In [large, xlarge]`, `arch In [amd64]`. 인스턴스 타입은 나열하지 않는다. limits: prod OD 16 / Spot 32 vCPU(실험 값), dev OD 8 / Spot 8 | 실험의 `large`만 허용(D-001)은 FIS 사전조건(burst가 Spot 노드 2대 이상에 분산)을 위한 실험 전용 제약이었다. 운영 Pod(500m/1Gi)에는 xlarge까지 허용한다. 현재 리전 Spot 풀은 사용자가 확인한다 |
| D7 | 워크로드 배치 | 아래 표 |

### D7. 워크로드 배치 (Karpenter 전환 후)
| 워크로드 | prod | dev | 근거 |
|---|---|---|---|
| backend-api | 게이트 off: 전부 `on-demand-base` / 게이트 on: HPA min까지 OD, 초과분 Spot(웹훅) | 동일 | 실험 대상 구성. 기존에도 core OD에만 배치 |
| ai-service | `spot-burst` | `on-demand-base` | 기존 배치 유지(prod ai spot, dev core OD) |
| batch-job(worker) | `on-demand-base` | `spot-burst` | 기존 배치 유지(prod batch OD, dev batch spot). SQS 재처리 가능 |
| 시스템 애드온 | core MNG | core MNG | 변경 없음 |
| Karpenter, ALB Controller, metrics-server | ops MNG | ops MNG | 변경 없음(Karpenter 추가) |

라벨 체계: 기존 `workload`/`capacity` 커스텀 라벨 중 **`capacity`(on-demand/spot)만** NodePool 템플릿 라벨로 이어간다. `workload` 라벨·taint는 core/ops MNG에만 남는다. 서비스 values의 `nodeSelector.workload`는 제거한다.

## 4. Phase별 작업

### Phase 0. 준비
- [x] `git switch -c feat/karpenter-spot-vpc-cni develop`
- [x] 베이스라인 검증 기록: `terraform fmt -check`, 환경별 `terraform validate`, 차트별 `helm lint`/`helm template` → `evidence/00-baseline-*`
- [x] 실험 zip을 레포 밖(세션 scratchpad)에 풀고 위치를 부록에 메모

### Phase 1. 기존 버그 수정: addon `configuration_values` 전달 경로
- [x] `terraform/modules/eks/variables.tf`: addons 객체 타입에 `configuration_values`(optional) 추가
- [x] `terraform/modules/eks/main.tf`: `aws_eks_addon`에 `configuration_values` 전달
- [x] `service_account_role_arn` 전달 경로 유지 확인(기존 로직 그대로). vpc-cni는 IRSA 없이 노드 Role 사용(불변식 2)
- [x] 동작 변경 보고: 이 수정으로 `enableNetworkPolicy=true`가 처음으로 실제 전달된다 → RESULT.md에 기록
- [x] 검증: `terraform fmt`, dev/prod `terraform validate`

### Phase 2. Karpenter AWS 인프라 (Terraform)
- [x] 신규 `terraform/modules/karpenter/`: 컨트롤러 IRSA Role + 정책(실험이 쓴 terraform-aws-modules/eks 21.29.0 karpenter 정책 기준), 노드 Role(WorkerNode, **CNI**, ECR ReadOnly, SSM), 노드 Role Access Entry(`EC2_LINUX`)
- [x] Interruption SQS 큐 + 큐 정책 + EventBridge 규칙 5종(Health, Spot 중단 경고, 재조정 권고, 상태 변경, 용량 예약 중단)
- [x] discovery 태그: 새 Karpenter 노드 서브넷(D2, `modules/prod-vpc`, `modules/dev-vpc`) + 클러스터 primary SG(`aws_ec2_tag`, karpenter 모듈 안)
- [x] `environments/{dev,prod}/main.tf`에서 모듈 호출(`enable_<env>_karpenter` 플래그), 출력(큐 이름, 노드 Role 이름, 컨트롤러 Role ARN)
- [x] 웹훅 이미지용 ECR 저장소 추가(기존 `*_ecr` 모듈)
- [x] 검증: `terraform fmt`, dev/prod `terraform validate`

### Phase 3. Karpenter GitOps (컨트롤러 + EC2NodeClass + NodePool)
- [x] `gitops/argocd/<env>/karpenter-project.yaml`, OCI Helm 저장소 등록 Secret, `applications/karpenter-crd-<env>.yaml`, `applications/karpenter-<env>.yaml`(ops MNG 배치, `settings.interruptionQueue`, IRSA)
- [x] `gitops/apps/<env>/karpenter/`: EC2NodeClass(AL2023, gp3 암호화, 태그 셀렉터), NodePool `on-demand-base`(taint `capacity=on-demand`), `spot-burst`(taint `capacity=spot`), `applications/karpenter-nodepools-<env>.yaml`
- [x] NodePool 템플릿 라벨 `capacity: on-demand|spot`
- [x] **maxPods는 이 Phase에 넣지 않는다**(Phase 4에서 PD와 함께)
- [x] 검증: YAML 파싱, `helm template`(Karpenter 차트 1.15.0 + values) — kubeconform 미설치

### Phase 4. VPC CNI PD + maxPods 정합 (원자적 변경, 한 커밋)
- [x] vpc-cni addon `configuration_values`: `enableNetworkPolicy` + `env.ENABLE_PREFIX_DELEGATION=true`, `WARM_IP_TARGET=1`, `MINIMUM_IP_TARGET=3` (dev/prod)
- [x] EC2NodeClass `kubelet.maxPods: 40`
- [x] 남기는 MNG launch template user_data(nodeadm `NodeConfig`)에 maxPods 40 (`modules/eks-nodegroup`, 노드그룹별 `max_pods`)
- [x] VPC CNI 버전: 변경 없음(D1)
- [x] 서브넷: D2(Phase 2에서 추가한 /20 Karpenter 서브넷). 기존 /24는 변경 없음
- [x] 불변식 2 재확인(노드 Role 둘 다 CNI 정책)
- [x] 검증: `terraform fmt`, dev/prod `terraform validate`, 정합성 스크립트

### Phase 5. 워크로드 차트와 values
- [x] `gitops/charts/{backend-api,ai-service,batch-job}/templates/deployment.yaml`: `terminationGracePeriodSeconds`, `lifecycle`, `topologySpreadConstraints` 슬롯 추가(기존 tolerations/nodeSelector/affinity 슬롯은 있음)
- [x] backend-api: `capacitySplit` 게이트(on이면 opt-in 라벨 + Spot toleration 기본값, nodeSelector 생략)
- [x] batch-job: PDB 템플릿 추가(values의 `pdb` 키가 템플릿 없이 쓰이지 않던 상태)
- [x] values(dev/prod): preStop sleep 20s(트래픽 받는 backend-api, ai-service), grace 60, zone topology spread, PDB `minAvailable: 50%`(replica ≥ 2인 곳), D7 배치
- [x] 차트 기본 values의 `nodeSelector.workload` 제거(Helm map 병합으로 env values에서 지워지지 않음)
- [x] preStop은 실험과 같은 네이티브 `sleep` 액션(셸 불필요, K8s 1.30+ 기본 활성)
- [x] 검증: `helm lint`, 환경별 `helm template` 렌더링 확인

### Phase 6. base/burst 분할 Mutating Webhook
- [x] 소스 이식: `tools/capacity-split-webhook/`(실험 `webhook/` 기준). 변경: annotation 접두사, `FAIL_OPEN`, 모듈 경로. 단위 테스트 이식 + fail-open 테스트 추가
- [x] 차트 `gitops/charts/capacity-split-webhook/`: replicas 1 + Recreate, RBAC, Service, MutatingWebhookConfiguration(`failurePolicy: Ignore`, namespaceSelector + objectSelector), 인증서는 `kube-webhook-certgen`(v1.6.9) PreSync/PostSync Job. `image.tag`가 비어 있으면 아무것도 렌더링하지 않는다
- [x] ArgoCD Application + AppProject, `moment-<env>` 네임스페이스에 `capacity-split=enabled` 라벨
- [x] 알려진 한계 문서화(fail-open 시 Spot 배치·deletion-cost 미부여, Spot 부족 시 Pending, SPOF)
- [x] 검증: `helm lint`/`helm template`. Go 단위 테스트는 로컬에 Go·Docker가 없어 **실행 못 함**(RESULT.md 기록)

### Phase 7. 기존 MNG 축소
- [x] `environments/prod/main.tf` `prod_eks_nodegroups`(577-702), `environments/dev/main.tf` `dev_eks_nodegroups`(407-518): batch/ai 노드그룹을 `module.<env>_eks_legacy_nodegroups`로 분리(`moved-legacy-workload-nodegroups.tf`), `enable_<env>_legacy_workload_nodegroups`로 제거 시점 제어, core/ops 유지 + maxPods
- [x] values에서 제거된 노드그룹 라벨(`workload: ai|batch`)·taint 참조가 없는지 grep 교차 확인
- [x] 검증: dev/prod `terraform validate`

### Phase 8. 정합성 검증 장치와 문서
- [x] `scripts/validation/check-pd-maxpods.sh`: Terraform `ENABLE_PREFIX_DELEGATION`과 EC2NodeClass·MNG `max_pods`를 비교, 불일치 시 실패. 음성 테스트(일부러 어긋난 사본) 포함
- [x] CI: `.github/workflows/static-validation.yml`(PR에서 terraform fmt, 정합성 스크립트, helm lint)
- [x] 런북 `docs/runbooks/vpc-cni-prefix-delegation.md`(allocatable.pods 확인, 서브넷 여유와 /28 단편화 확인, addon 갱신 시 IRSA·노드 Role 주의), `docs/karpenter.md`(구성, 웹훅 활성화 절차, 한계)
- [x] `docs/eks.md`의 "Karpenter M4/M5 예정" 서술 갱신, `docs/M5-SEC-03-network-policy.md`의 "활성화 완료" 서술 정정
- [x] 문서에 근거 표현 규칙 적용(n=3, 묶음 효과, /28 미재현)
- [x] 최종 점검: 베이스라인 대비 fmt/validate/helm 전부 통과, 불변식 1~3, 변경 파일 목록 → RESULT.md

### 리뷰 반영 (독립 code-reviewer, 2026-10-23)
- [x] HIGH: dev 서비스 앱 자동 동기화 → dev Karpenter·웹훅 앱도 자동 동기화, PR 분할 적용 순서 문서화
- [x] HIGH: batch/ai MNG 제거를 Karpenter 도입과 분리(legacy 모듈 + 플래그 + moved)
- [x] MEDIUM: PD(addon) → maxPods(노드) 적용 순서(`-target=module.<env>_eks` 먼저) 문서화
- [x] MEDIUM: prod EC2NodeClass AMI 고정 `al2023@v20261012`(K8s 1.33–1.35 포함 확인)
- [x] LOW: 웹훅 decode/marshal 오류도 fail-open, Karpenter 노드 Role SSM 정책 partition, 검증 스크립트(legacy 모듈, 역할 연결, 모듈의 max_pods 렌더링)

## 5. 완료 기준
- [x] 모든 Phase 체크 완료, 정적 검증 전부 통과
- [x] PD와 maxPods가 같은 커밋에 있음 (`ca526b6`)
- [x] 정합성 검증 스크립트 통과
- [x] 노드 Role(MNG, Karpenter) 모두 `AmazonEKS_CNI_Policy`, `service_account_role_arn` 전달 경로 유지
- [x] 결정 D1~D7 기록
- [x] 배포 관련 명령을 한 번도 실행하지 않음

## 부록. 실험 자료 위치 (레포 밖, 세션 scratchpad)
| 항목 | karpenter-spot-lab | vpc-cni-exp |
|---|---|---|
| NodePool / EC2NodeClass | `k8s/karpenter/nodepools.yaml`, `nodeclass.yaml` | `manifests/ec2nodeclass-*.yaml`, `nodepool-test*.yaml` |
| 웹훅 | `webhook/*.go`, `webhook/DESIGN.md`, `webhook/deploy/webhook.yaml`, `scripts/deploy-webhook.sh` | - |
| Interruption queue | `infra/main.tf` `module "karpenter"`(terraform-aws-modules/eks 21.29.0 `modules/karpenter`) | `cluster/karpenter-cfn.yaml` |
| Helm 설정 | `scripts/install-addons.sh` | `cluster/create.sh` |
| 앱 설정(preStop, grace, PDB) | `k8s/app/base`, `k8s/app/components/{graceful,pdb}`, `k8s/app/overlays/case-d` | - |
| VPC CNI 설정 | - | `results/02-warm-ip.md`, `results/03-prefix-delegation.md`, `scripts/run_scenario.sh` |
| 측정 결과 | `results/summary.md`, `results/MORNING_REPORT.md`, `deviations.md` | `results/summary.md`, `results/raw/` |
