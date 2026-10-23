# Karpenter On-Demand + Spot 혼합 노드 운영

## 목적

기본 용량(HPA `minReplicas`)은 On-Demand에, HPA 증설분은 Spot에 둔다. Spot 회수나 HPA 축소가 일어나도 기본 On-Demand Pod는 남기고 Spot Pod가 먼저 정리되게 한다.

근거는 karpenter-spot-lab 실험이다(ap-northeast-2, EKS 1.36, Karpenter 1.15.0, 케이스별 n=3).

| 항목 | 케이스 A (대응 없음) | 케이스 D (아래 4가지 설정 묶음) |
| --- | --- | --- |
| FIS Spot 노드 1대 중단 시 비 2xx (400 rps, 10분) | 평균 711.7건 (622~759), 그중 5xx 307~398 | 0 / 0 / 0 |
| 중단 후 Ready 16 복귀 | 평균 190.3초 (190~191) | 평균 46초 (34~70) |
| HPA 16→4 스케일 인 | - | 3회 모두 Spot burst 12개가 먼저 삭제, On-Demand base 4개(AZ 2/2) 유지 |

- 케이스 D는 interruption queue, preStop 20s + grace 60s, AZ topology spread, PDB 50%를 **함께** 켠 결과다. B·C 케이스를 돌리지 않아 **어느 설정이 개선을 만들었는지는 분리되지 않았다.** 개별 설정의 효과로 해석하지 않는다.
- n=3 재현 실측이고 통계 검정이 아니다. 단일 리전, Spot 노드 1대 중단, 경고 2분 조건이다.
- 케이스 A의 에러 수는 k6가 보내지 못한 요청(77~165건)만큼 과소 집계된 하한값이다.

## 구성

| 구성 요소 | 경로 | 비고 |
| --- | --- | --- |
| 컨트롤러 IRSA, 노드 Role, Access Entry, Interruption SQS + EventBridge 규칙 5종 | `terraform/modules/karpenter`, `terraform/environments/<env>/karpenter.tf` | `enable_<env>_karpenter`. 정책은 실험이 쓴 terraform-aws-modules/eks 21.29.0 karpenter 정책 기준, 인라인 정책(관리형 정책 크기 한도 초과) |
| Karpenter 노드 서브넷 `/20 × 2` | `terraform/modules/{prod,dev}-vpc` `karpenter_node_subnet_cidrs` | prod `10.10.32.0/20`, `10.10.48.0/20` / dev `10.20.32.0/20`, `10.20.48.0/20`. 기존 private app 라우트 테이블 사용. `karpenter.sh/discovery` 태그는 이 서브넷에만 있다 |
| 보안 그룹 | 클러스터 primary SG | MNG와 같은 SG. `terraform/modules/karpenter`가 discovery 태그를 붙인다 |
| CRD, 컨트롤러 | `gitops/argocd/<env>/applications/karpenter-crd-<env>.yaml`, `karpenter-<env>.yaml` | 차트 1.15.0(`public.ecr.aws/karpenter`), ops MNG에 배치, `settings.interruptionQueue` |
| EC2NodeClass, NodePool | `gitops/apps/<env>/karpenter/`, `applications/karpenter-nodepools-<env>.yaml` | |
| base/burst 분할 웹훅 | `tools/capacity-split-webhook`(소스), `gitops/charts/capacity-split-webhook`, `applications/capacity-split-webhook-<env>.yaml` | 아래 "base/burst 분할" |

이전 후 남는 관리형 노드그룹은 `core_on_demand`(시스템 애드온)와 `ops_on_demand`(Karpenter, ALB Controller, metrics-server, 웹훅)다. 기존 batch/ai 노드그룹은 `module.<env>_eks_legacy_nodegroups`로 옮겨 두었고 `enable_<env>_legacy_workload_nodegroups`(기본 true)를 false로 바꿔야 제거된다. Karpenter 컨트롤러는 자신이 띄운 노드에 올라가면 안 되기 때문에 MNG에 둔다.

## NodePool

| NodePool | capacity-type | taint | limits.cpu (prod / dev) |
| --- | --- | --- | --- |
| `on-demand-base` | on-demand | `capacity=on-demand:NoSchedule` | 16 / 8 |
| `spot-burst` | spot | `capacity=spot:NoSchedule` | 32 / 8 |

- 공통 requirements: `instance-category In [c,m,r]`, `instance-generation Gt 4`, `instance-size In [large, xlarge]`, `arch In [amd64]`. 인스턴스 타입은 나열하지 않는다. 실험은 `large`만 허용했지만(FIS 사전조건용 실험 전용 제약, deviations.md D-001) 운영 Pod 크기를 고려해 xlarge까지 연다.
- EC2NodeClass: AL2023(prod `al2023@v20261012` 고정, dev `al2023@latest`), gp3 암호화, `kubelet.maxPods: 40`(VPC CNI Prefix Delegation과 한 묶음, [런북](runbooks/vpc-cni-prefix-delegation.md)).
- disruption: `WhenEmptyOrUnderutilized`, `consolidateAfter: 60s`, `expireAfter: 720h`(실험 값).
- **On-Demand taint의 트레이드오프(실험 D-004):** 실험 첫 시도에서 Spot 선호를 preferred affinity로만 줬더니 burst 12개 중 10개가 On-Demand 노드의 빈 자리에 배치됐다. taint로 막은 대신, Spot 용량이 부족하면 burst Pod는 On-Demand로 넘어가지 않고 Pending이 된다.

## 워크로드 배치

| 워크로드 | prod | dev |
| --- | --- | --- |
| backend-api | `capacitySplit.enabled=false`: 전부 on-demand-base / `true`: HPA min까지 on-demand, 초과분 Spot | 동일 |
| ai-service | spot-burst | on-demand-base |
| batch-job (worker) | on-demand-base | spot-burst |

- Karpenter 노드 선택은 `nodeSelector: karpenter.sh/capacity-type`으로 한다. 이 라벨은 Karpenter 노드에만 붙는다. 기존 `capacity` 라벨은 core/ops MNG에도 있어서 MNG로 새는 것을 막지 못한다.
- backend-api, ai-service: `preStop sleep 20s`(네이티브 sleep 액션, 셸 불필요) + `terminationGracePeriodSeconds: 60`, zone topology spread(prod `DoNotSchedule`, dev `ScheduleAnyway`), PDB `minAvailable: 50%`(prod).
- batch-job: SQS worker라 preStop 없이 grace 60s만 둔다.
- backend-api Ingress: `deregistration_delay.timeout_seconds=30`(실험 고정값, preStop 20s < 30s < grace 60s).

이전 운영 기준(`docs/eks.md`)은 "API 서버는 Spot에 배치하지 않는다"였다. 웹훅을 켜면 HPA 증설분(기본 용량 초과분)만 Spot에 간다. 기본 용량은 계속 On-Demand다.

## Spot 회수 흐름 (실험 케이스 D에서 관찰한 순서)

1. EC2가 Spot 중단 경고(2분 전)를 EventBridge로 보낸다 → SQS `moment-<env>-karpenter-interruption`
2. Karpenter가 메시지를 받아 노드를 taint/cordon하고 drain한다(실험에서 경고 후 14~15초)
3. Pod는 preStop 20초 동안 응답을 유지하면서 Service/ALB 대상에서 빠진다. 그동안 대체 Pod가 다른 노드에 뜬다
4. Karpenter가 인스턴스를 종료한다(실험에서 경고 후 37~44초)

## base/burst 분할 (capacity-split 웹훅)

### 동작

`capacity-split=enabled` 라벨이 있는 네임스페이스(`moment-<env>`)에서 `capacity-split.moment.io/enabled=true` 라벨이 붙은 Pod만 대상이다(현재 backend-api, 게이트가 켜졌을 때).

| 역할 | 조건 | 웹훅이 추가하는 것 |
| --- | --- | --- |
| base | ReplicaSet의 살아 있는 base Pod 수 < HPA `minReplicas` | `capacity-role=base`, `pod-deletion-cost: "1000"`, required `karpenter.sh/capacity-type In [on-demand]`, `capacity=on-demand` toleration |
| burst | 그 외 | `capacity-role=burst`, `pod-deletion-cost: "-1000"`, preferred spot, `capacity=spot` toleration |
| 공통 | `ENABLE_TOPOLOGY_SPREAD=true` | 역할·ReplicaSet별 zone(`DoNotSchedule`, `minDomains 2`) / hostname(`ScheduleAnyway`) spread |

동시 생성 경합 처리(ReplicaSet별 직렬화, decision id, 15초 TTL)는 `tools/capacity-split-webhook/DESIGN.md`에 있다.

### 운영 반영 시 바꾼 점

- **replicas 1 + Recreate 유지.** 결정 상태가 메모리에 있어서 replica가 2개면 base 개수가 깨진다. HA로 만들려면 리더 선출이나 API 서버에 상태를 두는 재설계가 필요하다.
- **fail-open.** `failurePolicy: Ignore` + `FAIL_OPEN=true`(조회 실패 시 변경 없이 허용). 웹훅이 없을 때 Pod 생성을 막지 않는다.
- **인증서:** `kube-webhook-certgen` v1.6.9 PreSync(Secret 생성)/PostSync(caBundle 주입) Job. Application은 `caBundle` 차이를 무시한다.

### 알려진 한계

- **웹훅이 내려가 있는 동안 생성된 Pod는 템플릿 기본값(burst)으로 생성된다.** Spot(Karpenter 노드)에 배치되고 `pod-deletion-cost`가 없다. base가 이 상태로 생기면 base Pod가 다시 만들어질 때까지 On-Demand 보장이 없다.
- 웹훅 재시작 직후에는 처리 중이던 결정이 사라져 base가 1개 많아질 수 있다(DESIGN.md).
- Spot 용량이 부족하면 burst Pod는 Pending이다(D-004).
- 실험에 없던 운영 조건: ap-northeast-3 리전, K8s 1.35, xlarge 허용, 실제 서비스 이미지. 실험 수치가 그대로 재현된다고 보장하지 않는다.

### 웹훅이 기본으로 꺼져 있는 이유

1. **이미지가 없다.** 웹훅은 이 레포의 Go 코드(`tools/capacity-split-webhook`)라서 빌드해서 ECR(`moment-<env>-capacity-split-webhook`, 태그 IMMUTABLE)에 올려야 한다. 이미지 없이 켜면 Pod가 `ImagePullBackOff`가 된다. 그래서 차트는 `image.tag`가 비어 있으면 아무 리소스도 만들지 않는다.
2. **fail-open이라 켜는 순서가 중요하다.** 웹훅 Pod가 Ready가 되기 전에 backend-api의 `capacitySplit`을 켜면, 그 사이에 생성된 Pod는 모두 burst로 들어간다. 이 Pod들은 Spot에 배치되고 `pod-deletion-cost`도 없다. 이렇게 생긴 base 부족은 Pod가 다시 만들어질 때까지 고쳐지지 않는다.
3. 이 두 단계를 Git 변경만으로 안전하게 진행할 경로가 없었다. 지금은 `.github/workflows/capacity-split-webhook.yml`로 보완했다.

게이트가 꺼져 있는 동안 backend-api는 전부 `on-demand-base`에 배치된다. 기존과 같은 전부 On-Demand 동작이고, 서비스는 정상이다.

### 활성화 절차 (사용자 승인 후)

| 단계 | 방법 | 확인 |
| --- | --- | --- |
| 1 | GitHub Actions `capacity-split webhook image / activation`, `mode=build-and-deploy`, `environment=<env>` (develop에서 실행): go test → linux/amd64 빌드 → ECR 푸시(`<env>-<sha>`) → webhook values `image.tag` 커밋 | ArgoCD `capacity-split-webhook-<env>` Synced. certgen Job 2개 Complete, 웹훅 Pod Ready, `kubectl get mutatingwebhookconfiguration capacity-split-webhook -o jsonpath='{.webhooks[0].clientConfig.caBundle}'`가 비어 있지 않음 |
| 2 | 같은 워크플로, `mode=enable-backend-split`: backend-api `capacitySplit.enabled=true` 커밋. 웹훅 태그가 비어 있으면 실패한다 | backend-api가 롤링되며 새 Pod에 라벨이 붙음 |
| 3 | 배치 확인 | `kubectl get pods -n moment-<env> -l app.kubernetes.io/name=backend-api -L capacity-role -o wide`에서 base Pod 수가 HPA `minReplicas`(prod 2, dev 1)와 같고 on-demand 노드에 있음. 나머지는 burst(Spot). annotation `controller.kubernetes.io/pod-deletion-cost`가 1000 / -1000 |
| 되돌리기 | 같은 워크플로, `mode=disable-backend-split` | 전부 on-demand-base로 돌아옴 |

워크플로가 커밋하기 전에 `check-capacity-placement.rb`와 `check-karpenter-wiring.rb`를 돌린다. OIDC Role(`moment-<env>-github-actions-role`)은 infra 레포 `develop`만 신뢰하므로 다른 브랜치나 fork에서는 AWS에 접근하지 못한다.

## 적용 순서 (배포 시, 사용자 승인 후)

dev의 서비스 앱(`backend-api-dev` 등)은 `develop` 자동 동기화라서, 서비스 values(`karpenter.sh/capacity-type` nodeSelector)가 머지되는 순간 Pod가 Karpenter 노드로 옮겨 간다. dev는 replica 1에 `maxUnavailable: 1`이라 Karpenter가 준비되지 않았으면 서비스가 내려간다. 그래서 **PR을 나눠 머지**한다.

| 단계 | 내용 | 확인 |
| --- | --- | --- |
| 0 | 배포 전 확인(Karpenter 1.15.x ↔ K8s 1.26–1.37 호환은 공식 매트릭스로 확인 완료): ap-northeast-3 a/c의 Spot 후보 풀(`c/m/r`, 5세대 이후, large/xlarge), EC2 Spot 서비스 연결 역할(`AWSServiceRoleForEC2Spot`) 존재(없으면 `<env>_karpenter_create_spot_service_linked_role = true`), [VPC CNI 런북](runbooks/vpc-cni-prefix-delegation.md)의 `/24` 서브넷 `/28` 여유 | |
| 1 | **PR-A 머지**: Terraform 전체 + Karpenter GitOps(CRD, 컨트롤러, NodePool). 서비스 values와 웹훅 게이트는 제외 | |
| 2 | Terraform `apply -target=module.<env>_eks` 먼저: vpc-cni에 PD가 켜진다. `dev/main.tf`는 노드그룹이 addon보다 먼저 만들어지도록 의존성이 없어서(e02f746), 한 번에 apply하면 maxPods 40 노드가 PD보다 먼저 뜰 수 있다 | aws-node env에 `ENABLE_PREFIX_DELEGATION=true` (런북 "적용 후") |
| 3 | 나머지 Terraform apply: Karpenter 서브넷·IAM·SQS, core/ops MNG maxPods 40(launch template 변경으로 롤링 교체). batch/ai MNG는 `moved` 블록으로 `module.<env>_eks_legacy_nodegroups`로 옮겨지며 유지된다(plan에 destroy가 없어야 한다) | `allocatable.pods`=40 |
| 4 | ArgoCD: Karpenter CRD → 컨트롤러 → NodePool 동기화(dev는 자동, prod는 수동) | EC2NodeClass `Ready`, 테스트 Pod로 노드 생성 |
| 5 | **PR-B 머지**: 서비스 차트·values(배치 이동, preStop/grace/spread/PDB). prod는 수동 동기화 | 서비스 Pod가 Karpenter 노드에서 Running |
| 6 | `enable_<env>_legacy_workload_nodegroups = false` 후 apply: batch/ai MNG 제거 | batch/ai 노드 0 |
| 7 | 웹훅 활성화(위 "활성화 절차" 1~3단계) | base 수 = HPA min, base는 on-demand |

Phase 1의 addon 버그 수정으로 `enableNetworkPolicy=true`가 처음으로 실제 적용된다. `moment-<env>`에 NetworkPolicy(`gitops/apps/<env>/network-policy.yaml`)가 동기화되어 있다면 default-deny가 실제로 동작하기 시작하므로, ALB → Pod(target-type ip, `allow-alb-ingress`)와 DNS(`allow-dns`) 허용이 들어 있는지 함께 점검한다.

## 통합 점검 (2026-10-23, 코드 기준)

apply와 sync를 했을 때 On-Demand 기본 + Spot 확장이 동작하는 구성인지 코드만으로 확인했다. AWS 접근이나 배포는 하지 않았다.

### 배치 정합성: 통과

`scripts/validation/check-capacity-placement.rb`로 확인했다.
- 노드 모델: core/ops/legacy MNG(Terraform)와 NodePool(YAML)의 라벨·taint를 코드에서 읽는다.
- Pod: 서비스 차트를 env values로 렌더링하고, 웹훅 패치(`patch.go`)를 base/burst로 흉내 낸다.
- 비교 대상: nodeSelector, required affinity, taint/toleration. 용량과 topology spread는 시뮬레이션하지 않는다.

| Pod | prod | dev |
| --- | --- | --- |
| backend-api, 게이트 off | on-demand-base | on-demand-base |
| backend-api base (웹훅) | on-demand-base | on-demand-base |
| backend-api burst (웹훅) | spot-burst | spot-burst |
| backend-api, 웹훅 장애(fail-open) | spot-burst | spot-burst |
| ai-service | spot-burst | on-demand-base |
| batch-job | on-demand-base | spot-burst |
| capacity-split 웹훅 | ops MNG | ops MNG |
| legacy batch/ai MNG에 갈 수 있는 워크로드 | 없음 | 없음 |

음성 테스트에서 On-Demand NodePool의 taint를 빼면 burst Pod가 On-Demand에도 갈 수 있게 된다. 이것이 실험의 함정 4(D-004)이고, 체크가 FAIL로 잡는다. `evidence/phase9-*`에 기록했다.

### 점검에서 찾아 보완한 것

| 항목 | 문제 | 보완 |
| --- | --- | --- |
| 웹훅 이미지 배포 경로 | 빌드·푸시·태그 반영 경로가 없어 웹훅을 켤 수 없었다 | `.github/workflows/capacity-split-webhook.yml`(빌드·푸시·태그, 게이트 on/off를 단계 분리) |
| Terraform ↔ ArgoCD 이름 연결 | IRSA Role·노드 Role·큐·클러스터명·ECR 이름이 manifest에 문자열로 들어가 있어서, 오타가 나면 배포 뒤에야 드러난다(AccessDenied, NodeClass NotReady) | `scripts/validation/check-karpenter-wiring.rb` + CI |
| 배치 정합성 회귀 | 라벨·taint·values 변경이 분리 전략을 깨도 CI가 몰랐다 | `scripts/validation/check-capacity-placement.rb` + CI |
| EC2 Spot 서비스 연결 역할 | 실험은 Phase 0에서 확인했다. 없으면 Karpenter가 Spot을 못 띄운다 | `<env>_karpenter_create_spot_service_linked_role`(기본 false, 계정 단위라 없을 때만 true) |
| ALB 헬스체크 | 실험의 고정값(10초 간격, unhealthy 2회, timeout 5초, healthy 2회)이 빠져 있었다 | backend-api Ingress에 반영 |

### 확인했고 문제없는 것

- **egress**: Karpenter 노드 서브넷은 private app 라우트 테이블을 공유한다. 중앙 NAT(TGW) 기본 경로와 S3 게이트웨이 엔드포인트를 같이 쓰므로 SQS, Pricing, ECR, STS에 닿는다.
- **노드 등록과 SG**: 노드 Role의 `EC2_LINUX` Access Entry(인증 모드 API)가 있다. 노드는 클러스터 primary SG를 쓰므로 데이터 계층 SG와 VPC 엔드포인트 SG 규칙이 MNG와 같게 적용된다.
- **DaemonSet**: aws-node, kube-proxy, node-exporter(kube-prometheus-stack 61.3.0 기본 toleration `NoSchedule Exists`)가 taint 있는 Karpenter 노드에서도 돈다. loki/promtail은 비활성이다.
- **스케일 인 순서**: `pod-deletion-cost`는 K8s 1.22+에서 기본 활성이라 EKS 1.35에서 그대로 쓴다.

### 남는 위험 (코드로 해결하지 않음)

- **fail-open의 대가**: 웹훅이 장애 중일 때 생성된 Pod는 burst가 된다. base가 부족해도 base Pod가 다시 만들어질 때까지 자동 복구되지 않는다(DESIGN.md).
- **Spot 용량 부족**: burst Pod는 Pending이 된다(D-004 트레이드오프).
- **Karpenter 컨트롤러 2 replica**: 차트 기본값이 zone `DoNotSchedule` + hostname anti-affinity라서 prod ops MNG 2대가 서로 다른 AZ에 있어야 한다. ASG가 AZ 균형을 맞추지만 보장되지는 않는다.
- **prod 플래그 순서**: `enable_prod_karpenter`는 기본 false다. prod Karpenter 앱과 서비스 values는 Terraform을 적용하기 전에 sync하지 않는다(prod 앱은 수동 sync).
- **core MNG 크기**: core MNG는 시스템 애드온만 남지만 크기(prod 2~4대)는 그대로 뒀다. 이전 후 사용률을 보고 줄인다.
