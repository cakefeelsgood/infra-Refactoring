# 결과: Karpenter Spot 혼합 운영 + VPC CNI Prefix Delegation 고도화

- 브랜치 `feat/karpenter-spot-vpc-cni`(develop a2e4de6 기준), 커밋 11개(7절), **푸시하지 않음**
- **배포하지 않음**: `terraform apply/plan/import/state`, `kubectl`, `helm install/upgrade`, `argocd`, AWS CLI를 한 번도 실행하지 않았다. 실행한 것은 로컬 정적 검증(`terraform fmt/init -backend=false/validate`, `helm lint/template/pull`), 공개 레지스트리 조회(Karpenter 차트·certgen 이미지 태그 존재 확인), 로컬 스크립트뿐이다
- 계획·결정: [`PLAN.md`](../../PLAN.md)(D1~D7), 규칙: [`CLAUDE.md`](../../CLAUDE.md), 증거: [`evidence/`](evidence/)

## 1. 목표별 반영 결과

### 목표 1. Karpenter On-Demand + Spot 혼합 운영과 장애 대응

| 실험(케이스 D) 설정 | 반영 위치 | 상태 |
| --- | --- | --- |
| NodePool `on-demand-base`(taint `capacity=on-demand`) / `spot-burst`(taint `capacity=spot`) | `gitops/apps/<env>/karpenter/nodepools.yaml` | 반영 |
| EC2NodeClass AL2023, gp3 암호화 | `gitops/apps/<env>/karpenter/ec2nodeclass.yaml` | 반영 |
| Interruption queue: SQS + EventBridge → `settings.interruptionQueue` | `terraform/modules/karpenter`, `gitops/argocd/<env>/applications/karpenter-<env>.yaml` | 반영 |
| preStop sleep 20s, `terminationGracePeriodSeconds: 60` | 차트 슬롯 추가 + backend-api·ai-service values (batch-job은 grace만) | 반영 |
| zone topology spread | values `topologySpreadConstraints` + 웹훅 `ENABLE_TOPOLOGY_SPREAD=true` | 반영 |
| PDB `minAvailable: 50%` | backend-api·ai-service prod (replica 1인 곳은 drain을 막으므로 비활성 유지) | 반영 |
| base/burst 분할 웹훅, `pod-deletion-cost` 1000 / -1000 | `tools/capacity-split-webhook`, `gitops/charts/capacity-split-webhook` | 반영, **게이트 off**(이미지 미빌드, 6절) |
| Karpenter 컨트롤러 IAM·노드 Role·Access Entry | `terraform/modules/karpenter` (IRSA, 기존 방식) | 반영 |

### 목표 2. VPC CNI Prefix Delegation + maxPods 정합성

| 항목 | 반영 위치 | 상태 |
| --- | --- | --- |
| `ENABLE_PREFIX_DELEGATION=true`, `WARM_IP_TARGET=1`, `MINIMUM_IP_TARGET=3` | `terraform/environments/<env>/main.tf` vpc-cni `configuration_values` | 반영 |
| `kubelet.maxPods: 40` (Karpenter) | `ec2nodeclass.yaml` | 반영 |
| `maxPods: 40` (남는 MNG core/ops) | `node_groups.*.max_pods` → `modules/eks-nodegroup` launch template user_data(nodeadm `NodeConfig`) | 반영 |
| 정합성 검증 장치 | `scripts/validation/check-pd-maxpods.sh` + CI `.github/workflows/static-validation.yml` + 런북 | 반영 |
| 서브넷 크기 결정 | Karpenter 전용 `/20 × 2` 추가(D2), 기존 `/24` 유지 + /28 확인 절차 | 반영 |

### 선행 버그 수정

- `terraform/modules/eks`: addons 타입에 `configuration_values`가 없어 `enableNetworkPolicy`가 조용히 버려지던 문제를 고쳤다. **다음 apply에서 NetworkPolicy enforcement가 처음으로 실제 적용된다**(`docs/M5-SEC-03-network-policy.md` 정정 기록).

## 2. 주요 결정 (상세 근거는 PLAN.md 3절)

| # | 결정 |
| --- | --- |
| D1 | Karpenter 1.15.0(실험 버전). VPC CNI는 v1.21.1 유지(PD는 1.9+ 지원, v1.23.2 ↔ K8s 1.35 호환을 AWS 조회 없이 확인할 수 없음). 리전·K8s 버전 유지 |
| D2 | 기존 `/24` 서브넷은 바꾸지 않고(재생성 시 컨트롤 플레인 ENI·노드 교체) Karpenter 노드 서브넷 `/20 × 2`를 추가. discovery 태그는 새 서브넷에만 |
| D3 | On-Demand taint 유지(실험 D-004). Spot 부족 시 burst Pod는 Pending |
| D4 | 웹훅 replicas 1 + Recreate 유지(메모리 상태), `failurePolicy: Ignore` + 코드 `FAIL_OPEN`, objectSelector opt-in, 서비스 게이트 기본 off |
| D5 | MNG는 최종적으로 core/ops만. batch/ai MNG는 `module.<env>_eks_legacy_nodegroups`로 옮기고(`moved`, 재생성 없음) `enable_<env>_legacy_workload_nodegroups`(기본 true)로 제거 시점 분리 |
| D6 | c/m/r, 5세대 이후, large/xlarge, amd64. 타입 나열 없음 |
| D7 | 워크로드 배치: backend-api OD(게이트 on 시 분할), ai-service prod Spot / dev OD, batch-job prod OD / dev Spot (기존 배치 유지) |

추가로 코드와 대조하며 바꾼 점:

- 노드 선택 라벨: 기존 `capacity` 라벨은 core/ops MNG에도 붙어 있어 Karpenter 노드만 고를 수 없다. 서비스 values는 `karpenter.sh/capacity-type`(Karpenter 노드에만 붙음)으로 선택한다.
- 웹훅 분할 모드의 burst Pod에는 `karpenter.sh/capacity-type In [on-demand, spot]` required affinity를 둔다(taint 없는 core MNG로 새는 것 방지). base Pod는 웹훅이 on-demand 조건을 AND로 더한다.
- 불변식 2 재정의: 이 레포의 aws-node는 IRSA가 아니라 노드 Role의 `AmazonEKS_CNI_Policy`를 쓴다. 그래서 새 Karpenter 노드 Role에 CNI 정책을 넣었고, 검증 스크립트가 두 노드 Role을 모두 확인한다.

## 3. 검증 결과

| 검증 | 결과 | 증거 |
| --- | --- | --- |
| 베이스라인(변경 전) fmt / validate(dev, prod, network, shared) / helm lint·template | 전부 통과 | `evidence/00-baseline-*` |
| Phase 1~8 각 단계 `terraform fmt -check`, dev/prod `terraform validate`, 전 차트 × env `helm lint`·`helm template` | 전부 PASS | `evidence/phase{1,2,4,5,6,7}-validate.log`, `evidence/phase8-final-validate.log` |
| Karpenter 매니페스트 구조 검증(karpenter-crd 1.15.0 스키마 대비 필드·필수값·enum, AMI alias CEL 규칙) | 6/6 OK, 음성 테스트(오타·잘못된 enum) FAIL 확인 | `evidence/phase3-gitops-validate.log` |
| Karpenter 1.15.0 차트 렌더링(Application values) | 통과, IRSA 주석·`CLUSTER_NAME`·`INTERRUPTION_QUEUE`·ops 배치 확인 | `evidence/phase3-gitops-validate.log` |
| PD/maxPods 정합성 스크립트 | 실제 레포 PASS, 음성 테스트 6종(PD off+40, MNG 누락, NodeClass 17, CNI 정책 누락, legacy MNG 누락, 모듈이 max_pods 미렌더링) 모두 FAIL(exit 1) | `evidence/phase4-check-pd-maxpods.log` |
| MNG user_data 렌더링(terraform console) + NodeConfig YAML 파싱 | `maxPods: 40` 확인 | `evidence/phase4-mng-userdata.log` |
| 서비스 차트 렌더링 결과(nodeSelector, toleration, affinity, preStop, grace, spread, PDB, ALB 속성), 게이트 on/off | 의도대로 | `evidence/phase5-rendered-scheduling.log` |
| 웹훅 차트(이미지 태그 없음 → 0개, 태그 있음 → 13개 리소스, failurePolicy·selector·certgen 인자) | 의도대로 | `evidence/phase6-webhook.log` |
| legacy 노드그룹 분리(모듈·플래그·moved 블록), 서비스 쪽 `workload: ai/batch` 참조 | 분리 확인, 참조 없음 | `evidence/phase7-nodegroup-refs.log` |
| 불변식 1~3, 추가된 줄의 서브넷/SG ID·시크릿, TODO/skip | 통과(계정 ID는 CLAUDE.md 예외 범위의 IRSA ARN·ECR 주소 4줄만) | `evidence/phase8-final-invariants.log` |
| 런북의 /28 계산 스니펫 | 가짜 데이터로 기대값 11 확인 | `evidence/phase8-runbook-snippet.log` |
| GitHub Actions `static-validation.yml` (fork PR #2, 커밋 `8727980`, run 39922770973) | terraform fmt/validate, PD/maxPods, helm, 웹훅 gofmt·vet·`go test -race` 전부 pass. 첫 실행(`3d15ca6`)은 gofmt 필드 정렬로 실패 → `8727980`에서 수정 | GitHub Actions 로그 |
| 독립 리뷰(code-reviewer 에이전트) | REQUEST CHANGES → 전부 반영 후 재검증 PASS | 8절 |

## 4. 검증하지 못한 것

| 항목 | 이유 | 대신 한 것 / 남은 방법 |
| --- | --- | --- |
| 웹훅 Go 단위 테스트(`go test -race`), gofmt, go vet | 로컬에는 Go·Docker가 없어 실행하지 못함 | **CI에서 실행해 통과**(아래 3절 마지막 행) |
| kubeconform | 미설치 | CRD 스키마 기반 구조 검사(Ruby)로 대체 |
| `terraform plan` | 자격 증명·원격 상태 필요(금지) | validate까지만 |
| ~~Karpenter 1.15.0 ↔ EKS 1.35 호환~~ | **확인 완료**: aws/karpenter-provider-aws `hack/docs/compatibilitymatrix_gen/compatibility.yaml`(main, 2026-10-23 조회): 1.15.x는 K8s 1.26–1.37 지원. 1.35 지원 | - |
| ap-northeast-3 Spot 후보 풀 | AWS 조회 금지 | requirements 범위로만 표현 |
| MNG 노드에서 user_data의 `maxPods`가 EKS 생성 설정보다 우선하는지 | 실제 노드 필요 | 런북 "적용 후: 노드 확인"으로 `allocatable.pods` 확인 |
| 실험 수치의 운영 재현 | 실험 조건(리전, 버전, 인스턴스, 앱)과 다름 | 문서에 n=3·묶음 효과·/28 미재현을 명시 |

## 5. 배포 전 확인 목록 (사용자)

1. ~~Karpenter 1.15.0이 EKS 1.35를 지원하는지~~ 확인 완료(aws/karpenter-provider-aws `hack/docs/compatibilitymatrix_gen/compatibility.yaml`(main, 2026-10-23 조회): 1.15.x는 K8s 1.26–1.37 지원)
2. ap-northeast-3 a/c에서 `c/m/r` 5세대 이후 large/xlarge Spot 후보가 충분한지 확인
3. EC2 Spot 서비스 연결 역할(`AWSServiceRoleForEC2Spot`)이 계정에 있는지 확인(기존 Spot MNG 때문에 있을 가능성이 높음)
4. 실제 `terraform.tfvars`에 `enable_prod_karpenter = true`(prod 기본값 false, dev 기본값 true). **prod 서비스 values는 Karpenter 노드를 요구하므로, prod에서 Karpenter를 켜기 전에 서비스 values(PR-B)를 동기화하지 않는다**
5. [`docs/runbooks/vpc-cni-prefix-delegation.md`](../runbooks/vpc-cni-prefix-delegation.md)의 `/24` 서브넷 `/28` 여유 확인(core/ops MNG)
6. NetworkPolicy enforcement가 실제로 켜지므로 `moment-<env>`의 NetworkPolicy 동기화 상태와 ALB→Pod, DNS 허용 확인
7. 적용 순서는 [`docs/karpenter.md`](../karpenter.md) "적용 순서"를 따른다: PR-A(Terraform + Karpenter) 머지 → `apply -target=module.<env>_eks`(PD 먼저) → 나머지 apply(plan에 batch/ai MNG destroy가 없어야 함) → Karpenter 동기화 → PR-B(서비스 values) 머지 → `enable_<env>_legacy_workload_nodegroups = false`
8. prod EC2NodeClass AMI는 `al2023@v20261012`로 고정했다. 배포 시점에 올릴지 정한다

## 6. 남은 작업 (코드 밖)

- **웹훅 활성화는 실행만 남았다.** 코드 경로는 9절에서 보완했다. GitHub Actions `capacity-split webhook image / activation`을 `build-and-deploy`로 돌리고, 웹훅이 Ready인지 확인한 뒤 `enable-backend-split`으로 켠다. 실행 전까지 backend-api는 전부 On-Demand다(현재와 같은 동작).
- AWS 조회가 필요한 배포 전 확인(5절)

## 7. 커밋 내역

브랜치 `feat/karpenter-spot-vpc-cni`, 저장소 컨벤션(`type(scope): 한국어 설명`)을 따랐다. 푸시하지 않았다.

| PR 묶음 | 커밋 | 메시지 |
| --- | --- | --- |
| A | `e2da9fb` | docs: Karpenter·VPC CNI 고도화 작업 규칙과 계획 추가 |
| A | `3ec562d` | fix(eks): addon configuration_values 전달 누락 수정 |
| A | `f1c5a20` | feat(karpenter): Karpenter AWS 리소스와 노드 전용 서브넷 추가 |
| A | `fb8ecc3` | feat(karpenter): Karpenter 컨트롤러와 NodePool GitOps 구성 추가 |
| A | `ca526b6` | feat(vpc-cni): Prefix Delegation과 maxPods 40을 함께 적용 |
| A | `3addcd8` | refactor(eks): batch/ai 노드그룹을 legacy 모듈로 분리 |
| A | `663963b` | docs: Karpenter Spot 혼합 운영 문서와 적용 순서 추가 |
| B | `79113d6` | feat(workloads): 서비스 워크로드를 Karpenter NodePool로 배치하고 Spot 중단 대응 설정 적용 |
| B | `69295fb` | feat(webhook): base/burst 분할 capacity-split 웹훅 추가 |
| B | `79cef8c` | ci: 정적 검증 워크플로 추가 |
| B | (이 커밋) | docs: 고도화 결과와 검증 증거 추가 |

- PD와 maxPods는 `ca526b6` 한 커밋에 함께 있다(불변식 1). Karpenter 변경과 VPC CNI 변경은 다른 커밋이다.
- 여러 커밋에 걸친 파일(env `main.tf`·`variables.tf`, `ec2nodeclass.yaml`)은 중간 버전을 인덱스에 직접 올려 나눴다. 각 커밋을 단독으로 체크아웃해 fmt/validate/정합성 스크립트/helm template을 다시 돌렸고 모두 통과했다(`evidence/commits-per-commit-validate.log`).
- **PR 분할:** dev 서비스 앱이 자동 동기화이므로 A(`e2da9fb`..`663963b`)를 먼저 머지·적용하고, Karpenter가 준비된 뒤 B(`79113d6`..)를 머지한다(`docs/karpenter.md` 적용 순서). CI 워크플로는 웹훅 테스트를 포함해서 B에 두었다.

## 8. 독립 리뷰 (oh-my-claudecode code-reviewer, 읽기 전용)

판정: **REQUEST CHANGES** → 아래를 모두 반영한 뒤 전체 정적 검증을 다시 돌려 PASS(`evidence/phase8-final-validate.log`, `phase8-final-invariants.log`, `phase4-check-pd-maxpods.log`).

| 심각도 | 지적 | 조치 |
| --- | --- | --- |
| HIGH | dev 서비스 앱은 `develop` 자동 동기화. values가 머지되면 Karpenter 준비 전에 dev Pod가 Pending(replica 1, `maxUnavailable: 1`) | dev Karpenter·웹훅 앱도 다른 dev 인프라 앱처럼 자동 동기화로 변경. 서비스 values는 PR-B로 분리해 Karpenter 준비 후 머지(7절, `docs/karpenter.md` 적용 순서) |
| HIGH | batch/ai MNG 제거가 Karpenter 도입과 같은 apply에서 일어남. prod는 `enable_prod_karpenter` 기본 false인데 MNG는 무조건 제거 | batch/ai MNG를 `module.<env>_eks_legacy_nodegroups`로 옮기고 `moved` 블록으로 상태 유지, `enable_<env>_legacy_workload_nodegroups`(기본 true)로 제거 시점 분리 |
| MEDIUM | 한 apply 안에서 maxPods 40 노드가 PD보다 먼저 뜰 수 있음(e02f746로 노드그룹 → addon 의존성 없음) | `apply -target=module.<env>_eks` 먼저 하는 순서를 문서화(`docs/karpenter.md`, 런북). 의존성은 e02f746의 의도 때문에 추가하지 않음 |
| MEDIUM | `al2023@latest`는 AMI 릴리스마다 모든 노드를 drift로 교체 | prod `al2023@v20261012` 고정(awslabs/amazon-eks-ami 릴리스 노트에서 K8s 1.33–1.35 포함 확인, CRD CEL 규칙 통과). dev는 latest 유지 |
| LOW | 웹훅 decode/patch 직렬화 오류는 fail-open에서도 deny | `handler.fail()`로 통합, 테스트 추가(`TestReviewFailOpenAllowsUndecodablePod`) |
| LOW | Karpenter 노드 Role의 SSM 정책 ARN partition 하드코딩 | 모듈 내부에서 `local.partition`으로 생성 |
| LOW | 검증 스크립트: 불변식 2가 존재 여부만 확인, 모듈의 max_pods 렌더링 미확인 | CNI 정책이 MNG가 쓰는 역할(`aws_iam_role.eks_node` → `eks_node_role_arn`)에 붙는지, 모든 MNG가 그 역할을 쓰는지, 모듈이 `maxPods`를 렌더링하는지 확인 추가. legacy 모듈도 검사. 음성 테스트 2종 추가 |
| LOW | 웹훅 ClusterRole이 Pod를 클러스터 전체에서 list | 유지(리뷰어도 허용 가능 판단). 네임스페이스 Role로 좁히는 것은 후속 개선 |
| 질문 | EC2 Spot 서비스 연결 역할, NetworkPolicy가 ALB→Pod·DNS 허용하는지 | 5절 배포 전 확인 목록에 추가 |

리뷰어가 문제없다고 본 영역: Karpenter IAM(terraform-aws-modules 21.29 대비), SQS/EventBridge/Access Entry/SG 태그, /20 서브넷과 라우팅, `configuration_values` 전달과 `service_account_role_arn` 로직, nodeadm MIME, Karpenter 차트 렌더링과 AppProject, 웹훅 차트(certgen·RBAC·selector·ignoreDifferences), 서비스 스케줄링(core/ops로 새지 않음), Go 코드(컴파일·테스트 예상 통과), 문서의 근거 표현.

## 9. 통합 점검 (On-Demand 기본 + Spot 확장이 apply·sync 후 실제로 동작하는가)

코드만 검토했고 AWS 접근은 없다. 상세는 [`docs/karpenter.md`](../karpenter.md) "통합 점검"에 있다.

- **배치 정합성: 통과.** 노드 모델은 Terraform MNG와 NodePool에서, Pod는 helm 렌더링과 웹훅 패치 에뮬레이션에서 가져왔다. 그 결과 다음을 정적으로 확인했다. 결과는 `evidence/phase9-placement.log`에 있다.
  - base는 on-demand-base, burst와 fail-open Pod는 spot-burst에만 배치된다.
  - ai-service와 batch-job은 기존 배치를 유지한다.
  - 웹훅은 ops MNG에 배치된다.
  - legacy MNG에 의존하는 워크로드는 없다.
- **음성 테스트**: 5종 모두 FAIL로 잡았다(`evidence/phase9-placement-wiring-negative.log`).
  - OD taint 제거: 실험의 함정 4가 재현된다.
  - Karpenter 전용 affinity 제거: burst Pod가 core MNG로 샌다.
  - ai-service nodeSelector 제거.
  - 노드 Role 이름 오타.
  - 큐 이름 오타.
- **Terraform ↔ ArgoCD 이름 연결**: 26개 항목이 모두 일치한다(`evidence/phase9-wiring.log`).
- **보완한 것**:
  - 웹훅 이미지 빌드·푸시·태그 반영과 게이트 on/off 워크플로
  - 배치 정합성 체크와 이름 연결 체크, 그리고 둘의 CI 연결
  - EC2 Spot 서비스 연결 역할 옵션
  - 실험의 ALB 헬스체크 고정값
- **남는 위험**:
  - fail-open일 때 base 부족이 자동 복구되지 않는다.
  - Spot이 부족하면 burst Pod가 Pending이 된다.
  - Karpenter 2 replica를 서로 다른 AZ의 ops 노드에 띄워야 한다.
  - prod 플래그 순서.
  - core MNG 크기 재조정.
