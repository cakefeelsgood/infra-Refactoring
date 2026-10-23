# vpc-cni-prefix-delegation

## Summary

VPC CNI Prefix Delegation(PD)과 kubelet `maxPods`의 정합성, 적용 전 서브넷 확인, 적용 후 노드 확인 절차다. 아래 명령은 모두 조회 전용이며, 운영 계정에서 실행할 때는 승인을 받는다.

### PD가 하는 일

- PD는 **IP를 아끼는 기능이 아니라 노드당 Pod 수를 늘려 노드 수를 줄이는 기능**이다. 서브넷 IP는 오히려 더 쓴다.
- VPC CNI 실험(t3.medium, Pod 100개, 3회 중앙값):

| 항목 | Secondary IP (기본) | PD + maxPods 40 | PD + maxPods 40 + `WARM_IP_TARGET=1`, `MINIMUM_IP_TARGET=3` |
| --- | --- | --- | --- |
| 노드당 Pod 상한 (`allocatable.pods`) | 17 | 40 | 40 |
| 필요 노드 수 (Karpenter) | 8 | 4 | 4 |
| 서브넷 IP 소비 (합) | 138 | 164 (+19%) | 148 (+7%) |
| 동시 40개 생성 p95 (노드 고정) | 13초 (`WARM_IP_TARGET=1`만 낮추면 66초) | 2초 | 3초 |

- 실험 서브넷은 `/19`였고 **서브넷 고갈(`InsufficientFreeAddressesInSubnet`)과 `/28` 단편화(`InsufficientCidrBlocks`)는 한 번도 재현되지 않았다.** 운영 서브넷에서 안전하다는 근거가 아니다.

## 설정 위치

| 값 | 위치 |
| --- | --- |
| `ENABLE_PREFIX_DELEGATION=true`, `WARM_IP_TARGET=1`, `MINIMUM_IP_TARGET=3`, `enableNetworkPolicy` | `terraform/environments/<env>/main.tf` `module "<env>_eks"` vpc-cni `configuration_values` |
| Karpenter 노드 `maxPods: 40` | `gitops/apps/<env>/karpenter/ec2nodeclass.yaml` `spec.kubelet.maxPods` |
| MNG(core/ops) `maxPods: 40` | `terraform/environments/<env>/main.tf` `node_groups.*.max_pods` → launch template user_data(nodeadm `NodeConfig`) |
| 정적 검증 | `scripts/validation/check-pd-maxpods.sh` (CI `.github/workflows/static-validation.yml`) |

**PD와 maxPods는 항상 같은 변경에서 바꾸고, 적용은 PD(addon) → maxPods(노드) 순서로 한다.** dev 환경은 노드그룹이 addon보다 먼저 만들어지도록 의존성이 없어서(e02f746), 한 번에 apply하면 maxPods 40 노드가 PD보다 먼저 뜰 수 있다. `terraform apply -target=module.<env>_eks`로 addon을 먼저 적용한다([karpenter.md](../karpenter.md) 적용 순서). 한쪽만 바꾸면 실험에서 다음이 재현됐다.

- PD off + maxPods 40: Pod 100개 중 44개가 `ContainerCreating`에 멈췄고(`failed to assign an IP address`), 스케줄러 기준으로는 자리가 있어서 Karpenter가 노드를 추가하지 않았다.
- PD on + maxPods 17: 실패는 없지만 노드 8대, 서브넷 IP 264개로 가장 낭비가 컸다.

## 적용 전: 서브넷 여유와 /28 단편화 확인

PD는 노드마다 연속된 `/28`(16 IP) 블록을 잡는다. 남은 IP 수가 충분해도 정렬된 `/28` 블록이 없으면 할당이 실패한다.

1. 서브넷별 남은 IP:
   ```bash
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" \
     --query 'Subnets[].{id:SubnetId,cidr:CidrBlock,az:AvailabilityZone,free:AvailableIpAddressCount,name:Tags[?Key==`Name`]|[0].Value}' --output table
   ```
2. 서브넷의 사용 중 주소(보조 IP, 할당된 prefix)를 모아 비어 있는 정렬 `/28` 블록 수를 센다:
   ```bash
   aws ec2 describe-network-interfaces --filters "Name=subnet-id,Values=<subnet-id>" \
     --query 'NetworkInterfaces[].{ips:PrivateIpAddresses[].PrivateIpAddress,prefixes:Ipv4Prefixes[].Ipv4Prefix}' --output json > eni.json
   python3 - <<'EOF'
   import ipaddress, json
   subnet = ipaddress.ip_network("<subnet-cidr>")
   used = {subnet[i] for i in range(4)} | {subnet[-1]}  # AWS reserved addresses
   for eni in json.load(open("eni.json")):
       used.update(ipaddress.ip_address(i) for i in eni["ips"])
       for p in eni["prefixes"] or []:
           used.update(ipaddress.ip_network(p))
   free = [b for b in subnet.subnets(new_prefix=28) if not any(a in used for a in b)]
   print(f"{subnet}: free aligned /28 blocks = {len(free)} of {2 ** (28 - subnet.prefixlen)}")
   EOF
   ```
3. 판단 기준: 노드 1대는 Pod 40개를 위해 최대 3개(48 IP)의 `/28`을 잡고, Warm 설정 때문에 유휴 상태에서도 1개를 쥔다. 빈 `/28` 수가 (예상 노드 수 × 3)보다 적으면 서브넷을 늘리거나 `/28` CIDR reservation을 검토한다.
   - Karpenter 노드 서브넷(`/20`, `/28` 블록 256개)은 여유가 크다.
   - **core/ops MNG가 있는 private app 서브넷(`/24`, `/28` 블록 16개)은 VPC 엔드포인트·컨트롤 플레인 ENI·내부 ALB와 공간을 나눠 쓴다.** 적용 전 반드시 2번을 확인한다.

## 적용 후: 노드 확인

1. `allocatable.pods`가 40인지(PD 적용 전에 뜬 노드는 17로 남는다):
   ```bash
   kubectl get nodes -L karpenter.sh/nodepool,eks.amazonaws.com/nodegroup,node.kubernetes.io/instance-type \
     -o custom-columns='NAME:.metadata.name,PODS:.status.allocatable.pods,POOL:.metadata.labels.karpenter\.sh/nodepool,NG:.metadata.labels.eks\.amazonaws\.com/nodegroup'
   ```
2. aws-node에 PD가 실제 반영됐는지:
   ```bash
   kubectl -n kube-system get ds aws-node -o jsonpath='{range .spec.template.spec.containers[?(@.name=="aws-node")].env[*]}{.name}={.value}{"\n"}{end}' \
     | grep -E 'ENABLE_PREFIX_DELEGATION|WARM_IP_TARGET|MINIMUM_IP_TARGET|WARM_PREFIX_TARGET'
   ```
3. 노드 ENI에 prefix가 붙었는지:
   ```bash
   aws ec2 describe-network-interfaces --filters "Name=attachment.instance-id,Values=<instance-id>" \
     --query 'NetworkInterfaces[].Ipv4Prefixes[].Ipv4Prefix'
   ```
4. MNG 노드는 PD 적용 후 롤링 교체(launch template 변경)가 끝나야 40이 된다. 교체 전 노드에서 17이면 정상이다.

## 장애 증상과 대응

| 증상 | 확인 | 원인 후보 | 대응 |
| --- | --- | --- | --- |
| Pod가 `ContainerCreating`, 이벤트 `failed to assign an IP address to container` | `kubectl describe pod`, `allocatable.pods` | PD off인데 maxPods 40 | addon 설정과 maxPods를 다시 맞춘다. `scripts/validation/check-pd-maxpods.sh` |
| ipamd 로그 `InsufficientCidrBlocks` | `kubectl -n kube-system logs ds/aws-node -c aws-node` | 서브넷에 정렬된 `/28` 없음 | 위 "/28 단편화 확인", 서브넷 확장 또는 CIDR reservation |
| aws-node `CrashLoopBackOff`, 로그 403 / `UnauthorizedOperation` | aws-node 로그, 노드 Role 정책 | 노드 Role에 `AmazonEKS_CNI_Policy` 없음, 또는 IRSA를 쓰던 addon이 `service_account_role_arn` 없이 갱신됨 | 아래 주의사항 |

## addon 갱신 시 주의 (IRSA / 노드 Role)

- VPC CNI 실험에서 `configuration-values`를 `OVERWRITE`로 갱신하면서 `--service-account-role-arn`을 함께 넘기지 않아 aws-node IRSA 연결이 사라졌고, CNI 정책이 없는 노드의 aws-node가 403 CrashLoop에 빠졌다.
- 이 레포의 vpc-cni addon은 IRSA를 쓰지 않고 **노드 Role의 `AmazonEKS_CNI_Policy`**로 동작한다. 따라서:
  - 모든 노드 Role에 CNI 정책이 있어야 한다: MNG(`terraform/modules/iam` `eks_node_cni`), Karpenter(`terraform/modules/karpenter` `AmazonEKS_CNI_Policy`). 정적 검증 스크립트가 확인한다.
  - 나중에 vpc-cni에 IRSA를 도입하면 `addons.vpc-cni.service_account_role_arn`으로 넘긴다. `terraform/modules/eks`는 이 값을 갱신 때마다 그대로 전달한다.
  - CLI로 직접 갱신하지 않는다(`aws eks update-addon --configuration-values ...`). Terraform 소스가 기준이다.
