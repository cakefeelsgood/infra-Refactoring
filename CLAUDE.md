# CLAUDE.md — infra-refactoring 고도화 작업 규칙

## 이 작업이 무엇인가
- `develop` 브랜치의 **기존 인프라 코드를 고도화**하는 리팩토링이다. 새 프로젝트를 만드는 작업이 아니다.
- 목표 두 가지 (상세 내용과 단계는 `PLAN.md`):
  1. Karpenter 기반 On-Demand + Spot 혼합 노드 운영과 장애 대응
  2. AWS VPC CNI Prefix Delegation(PD)과 kubelet maxPods 정합성 개선
- 근거는 사전에 진행한 실험이다. 실험 자료는 `karpenter-spot-lab.zip`, `vpc-cni-exp.zip`.
  - zip은 **레포 밖 임시 디렉터리**에 풀어서 읽는다. 레포 안에 풀거나 커밋하지 않는다.
- **이번 작업은 코드 수정만 한다. 배포하지 않는다.**

## 절대 금지
- 클러스터·AWS에 영향을 주거나 자격 증명이 필요한 명령 일체:
  `terraform apply|destroy|import|state ...`, `kubectl apply|delete|patch|edit ...`,
  `helm install|upgrade`, `argocd app sync`, 변경 계열 `aws` CLI.
- 읽기 전용 AWS/클러스터 조회도 사용자 승인 없이 하지 않는다. (예: Spot 가용 인스턴스 조회는 사용자가 직접 한다. 코드에서는 인스턴스 타입을 나열하지 말고 `requirements`의 범위 조건으로 표현한다.)
- `develop`에 직접 수정하지 않는다. 작업 브랜치(`feat/karpenter-spot-vpc-cni`)에서만 작업한다.
- 계정 ID, 실제 ARN, 서브넷 ID, 시크릿을 새로 하드코딩하지 않는다. 기존 코드가 값을 넘기는 방식(변수, remote state, values)을 따른다.
  - 예외(2026-10-23 결정): ArgoCD Application/values는 Terraform 출력을 받을 경로가 없어서, 기존 앱들(`aws-load-balancer-controller-*`, 서비스 values)이 IRSA Role ARN·ECR 주소를 직접 적는다. 새 앱도 **Terraform이 결정적 이름으로 만드는 Role ARN·큐 이름·ECR 주소**에 한해 같은 방식으로 적는다. 서브넷·SG ID는 적지 않고 태그 셀렉터로 찾는다. 시크릿은 어떤 경우에도 적지 않는다.
- 커밋은 사용자가 요청할 때만 한다. 요청 시 Phase 단위로 나누고, Karpenter 변경과 VPC CNI 변경은 같은 커밋에 섞지 않는다.

## 허용되는 검증 (로컬 정적 검증만)
- `terraform fmt -check -recursive`
- `terraform init -backend=false` 후 `terraform validate` (환경별 디렉터리에서)
- `helm lint`, `helm template` (환경별 values로 렌더링)
- `kubeconform` 등 매니페스트 스키마 검증 (설치되어 있을 때)
- `git status`, `git diff`, `git log`
- 각 Phase가 끝나면 위 검증을 돌리고 결과를 요약 보고한다. 설치되지 않은 도구는 설치하지 말고 "검증 못 함"으로 보고한다.

## 변경 원칙
- **기존 아키텍처 유지**: 디렉터리 구조(`terraform/{environments,modules}`, `gitops/{argocd,apps,charts,values}`), ArgoCD GitOps 흐름, 모듈/차트 단위, 네이밍 규칙을 따른다. 새 모듈·차트가 필요하면 기존 것과 같은 구조로 만든다.
- **환경 설정은 실험에 맞춰 바꿔도 된다.** 기존 값은 당시 제약 때문에 정해진 것이다. 단, 값을 바꾸는 이유가 실험 근거이거나 PLAN.md의 결정 사항일 때만 바꾼다.
- 최소 diff. 목표와 무관한 정리, 포맷 변경, 의존성 업그레이드를 섞지 않는다.
- 기존 코드 스타일(변수 네이밍, 태그 규칙, 주석 언어)을 모방한다.
- 실험 코드를 가져올 때는 환경 종속 값(리전, 계정, 클러스터명, 서브넷/SG ID, 도메인)을 제거하고 변수화한다.
- 모르는 것은 추측해서 채우지 않는다. PLAN.md의 "결정 필요"에 적고 해당 지점에서 멈춰 사용자에게 묻는다.

## 불변식 (어기면 안 되는 것)
1. **PD와 maxPods는 반드시 같은 변경(같은 Phase, 같은 커밋)에서 바꾼다.**
   - `ENABLE_PREFIX_DELEGATION=true`(Terraform의 vpc-cni addon `configuration_values`)와
     `kubelet.maxPods=40`(EC2NodeClass, 그리고 남기는 관리형 노드그룹의 launch template user_data)는 한 묶음이다.
   - 한쪽만 바꾸면 Pod가 `ContainerCreating`에 멈추고 Karpenter도 노드를 추가하지 않는다. (실험으로 재현됨)
   - 두 값이 어긋나면 실패하는 정적 검증 스크립트를 Phase 8에서 만든다.
2. **aws-node의 AWS 권한 경로를 끊지 않는다.** 실험에서는 `service_account_role_arn` 없이 `configuration_values`를 갱신해 IRSA가 사라졌고, aws-node가 403 CrashLoop에 빠졌다.
   - 이 레포의 vpc-cni addon은 IRSA를 쓰지 않는다. aws-node는 **노드 Role의 `AmazonEKS_CNI_Policy`**로 동작한다(`modules/iam/main.tf` `eks_node_cni`). 따라서 (a) addon에 `service_account_role_arn`을 넘기는 경우 `modules/eks`가 그 값을 그대로 유지해야 하고, (b) **모든 노드 Role(MNG, Karpenter)에 `AmazonEKS_CNI_Policy`가 붙어 있어야 한다.** 두 조건을 매번 확인한다.
3. **기본 용량(OD)과 증설 용량(Spot)의 분리를 깨지 않는다.** OD NodePool의 taint, 기본 Pod에만 toleration, `pod-deletion-cost` 값(기본 Pod `1000`, 증설 Pod `-1000`)을 유지한다.

## 실험에서 확정된 기준값
| 항목 | 값 |
|---|---|
| PD | `ENABLE_PREFIX_DELEGATION=true` |
| Warm 설정 | `WARM_IP_TARGET=1`, `MINIMUM_IP_TARGET=3` |
| maxPods | `40` |
| preStop | sleep `20s` |
| terminationGracePeriodSeconds | `60` |
| pod-deletion-cost | 기본 Pod `1000`, 증설 Pod `-1000` |
| PDB | `minAvailable: 50%` |
| Topology Spread | zone 기준 |
| NodePool | `on-demand-base`(taint `capacity=on-demand`), `spot-burst`(taint `capacity=spot`) |
| EC2NodeClass | AL2023, gp3 암호화 |
| Interruption | SQS + EventBridge → Karpenter `settings.interruptionQueue` |

## 근거를 쓸 때 지켜야 할 것 (문서·주석·커밋 메시지)
- 실험 결과는 **n=3**이다. 일반화하거나 보장하는 표현을 쓰지 않는다.
- Karpenter 실험은 B, C 케이스를 돌리지 않았다. **interruption queue, preStop/grace, topology spread, PDB 중 어느 설정이 개선을 만들었는지는 분리되지 않았다.** "X 덕분에 개선됐다"고 쓰지 않는다. 묶음 효과로만 쓴다.
- VPC CNI 실험은 서브넷이 /19라서 **서브넷 고갈과 /28 단편화는 재현하지 못했다.** 운영 서브넷(/24)에 대해 안전하다고 쓰지 않는다.
- PD는 IP를 아끼는 기능이 아니라 **노드 수를 줄이는 기능**이다. 서브넷 IP는 오히려 더 쓴다. 이 점을 문서에 정확히 쓴다.

## 작업 방식
- `PLAN.md`의 Phase 순서를 따른다. 한 Phase를 끝내면 체크박스를 갱신하고 검증 결과를 증거 파일로 남긴다.
  - 2026-10-23 사용자 지시("알아서 수정하고 다 끝내라"): Phase 사이에 사용자 확인을 기다리지 않고 끝까지 진행한다. 결정 필요 항목은 PLAN.md 3절에 근거와 함께 결정을 기록하고 진행한다.
  - 증거와 결과: `docs/karpenter-vpc-cni-refactoring/evidence/`(Phase별 검증 로그), `docs/karpenter-vpc-cni-refactoring/RESULT.md`(최종 결과).
- 실험 코드(웹훅 등)는 원 설계를 따르되, 운영 반영을 위해 바꾼 부분은 PLAN.md 결정 사항과 코드 주석에 근거를 남긴다.
- 계획과 실제 코드가 다르면(경로, 변수명, 구조) 코드를 기준으로 하고 PLAN.md를 먼저 고친 뒤 보고한다.
- 작업 중 발견한 기존 버그는 고치기 전에 보고한다. 목표 달성의 전제조건이면 PLAN.md의 해당 Phase에 이미 포함되어 있다.
