# M2-VALID-A App / EKS / Ingress / Endpoint / Edge 검증 및 운영 Runbook

## 1. 목적

본 문서는 MoMent 프로젝트의 M2 Infra Bootstrap 단계에서 구성한 App 계층, EKS 실행 환경, Ingress / ALB, ECR, VPC Endpoint, Security Group, Redis, RDS, OpenSearch, S3, Edge Layer의 검증 결과와 운영 절차를 정리한다.

개발 및 실습 기간에는 Dev 환경을 기본 검증 대상으로 사용한다.

Prod 환경과 Edge Layer는 비용 통제를 위해 기본적으로 선택 활성화 구조로 관리하며, 최종 시연 또는 운영 리허설 기간에만 명시적으로 활성화한다.

---

## 2. 프로젝트 기본 정보

| 항목 | 값 |
| --- | --- |
| 프로젝트 | MoMent |
| Repository | msp-team04-infra |
| Region | ap-northeast-3, Osaka |
| AWS Account | 611058323802 |
| EKS Cluster | moment-dev-eks-cluster |
| 작업 이슈 | M2-VALID-A #319 |

---

## 3. 매일 아침 Dev 환경 복구 절차

Dev 환경은 비용 절감을 위해 필요 시 destroy 후 재생성할 수 있다.

```bash
aws sts get-caller-identity
```

EKS가 destroy된 상태라면 Dev 환경에서 다시 apply한다.

```bash
cd terraform/environments/dev
terraform apply
```

kubeconfig를 갱신한다.

```bash
aws eks update-kubeconfig \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster
```

현재 접속 IP를 기준으로 EKS Public Access CIDR을 갱신한다.

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo $MY_IP

aws eks update-cluster-config \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster \
  --resources-vpc-config \
  endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="${MY_IP}/32"
```

노드 상태를 확인한다.

```bash
kubectl get nodes
kubectl get pods -A
```

---

## 4. ECR 검증 절차

ECR Repository 생성 상태를 확인한다.

```bash
aws ecr describe-repositories \
  --region ap-northeast-3 \
  --query 'repositories[*].{Name:repositoryName,Uri:repositoryUri}' \
  --output table
```

확인 대상 Repository는 다음과 같다.

| Repository | 용도 |
| --- | --- |
| moment-dev-backend-api | Dev Backend API 이미지 |
| moment-dev-ai-service | Dev AI Service 이미지 |
| moment-dev-batch-job | Dev Batch Job 이미지 |

이미지 push 테스트 예시는 다음과 같다.

```bash
aws ecr get-login-password --region ap-northeast-3 | \
docker login --username AWS --password-stdin 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com
```

```bash
docker tag moment-dev-ai-service:test-v1 \
611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-ai-service:test-v1

docker push 611058323802.dkr.ecr.ap-northeast-3.amazonaws.com/moment-dev-ai-service:test-v1
```

이미지 push 결과 확인:

```bash
aws ecr describe-images \
  --region ap-northeast-3 \
  --repository-name moment-dev-ai-service \
  --query 'imageDetails[*].{Tags:imageTags,PushedAt:imagePushedAt}' \
  --output table
```

### destroy 전 ECR 이미지 보존 절차

ECR은 애플리케이션 이미지 저장소이므로, destroy 전 다음 기준으로 보존 여부를 확인한다.

1. 최종 시연에 사용할 이미지 태그가 있는지 확인한다.
2. `latest`, `test-v1`, Git SHA 태그 등 재사용 가능한 이미지가 있는지 확인한다.
3. 이미지가 재빌드 가능하면 삭제 가능하다.
4. 재빌드가 어렵거나 최종 시연에 필요한 이미지는 삭제하지 않는다.
5. Terraform destroy 전에 ECR Repository가 삭제 대상인지 plan에서 반드시 확인한다.

확인 명령어:

```bash
aws ecr describe-images \
  --region ap-northeast-3 \
  --repository-name moment-dev-ai-service \
  --query 'imageDetails[*].{Tags:imageTags,Size:imageSizeInBytes,PushedAt:imagePushedAt}' \
  --output table
```

---

## 5. Dev EKS / NodeGroup 검증 절차

EKS Cluster 상태를 확인한다.

```bash
aws eks describe-cluster \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster \
  --query 'cluster.{name:name,status:status,version:version,endpoint:endpoint}' \
  --output table
```

NodeGroup 상태를 확인한다.

```bash
aws eks list-nodegroups \
  --region ap-northeast-3 \
  --cluster-name moment-dev-eks-cluster \
  --output table
```

```bash
aws eks describe-nodegroup \
  --region ap-northeast-3 \
  --cluster-name moment-dev-eks-cluster \
  --nodegroup-name moment-dev-core-on-demand-ng \
  --query 'nodegroup.{status:status,scalingConfig:scalingConfig,instanceTypes:instanceTypes}' \
  --output table
```

노드 label을 확인한다.

```bash
kubectl get nodes --show-labels
kubectl get nodes -L workload,capacity
```

On-Demand / Spot NodeGroup 분리 기준:

| NodeGroup | 용도 |
| --- | --- |
| core-on-demand | Backend API 등 핵심 워크로드 |
| batch-spot | Batch Job |
| ai-spot | AI Service |
| ops-on-demand | 운영/모니터링 워크로드 |

---

## 6. Dev Ingress / ALB 검증 절차

AWS Load Balancer Controller 상태를 확인한다.

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

IngressClass를 확인한다.

```bash
kubectl get ingressclass
```

Ingress 상태를 확인한다.

```bash
kubectl get ingress -A
```

ALB 생성 여부를 확인한다.

```bash
aws elbv2 describe-load-balancers \
  --region ap-northeast-3 \
  --query 'LoadBalancers[*].{Name:LoadBalancerName,DNS:DNSName,State:State.Code,Scheme:Scheme}' \
  --output table
```

Target Group을 확인한다.

```bash
aws elbv2 describe-target-groups \
  --region ap-northeast-3 \
  --query 'TargetGroups[*].{Name:TargetGroupName,Type:TargetType,Port:Port,Protocol:Protocol}' \
  --output table
```

Target Health를 확인한다.

```bash
aws elbv2 describe-target-health \
  --region ap-northeast-3 \
  --target-group-arn <TARGET_GROUP_ARN> \
  --output table
```

검증 후 테스트 리소스는 삭제한다.

```bash
kubectl delete -f ~/nginx-test.yaml
```

---

## 7. VPC Endpoint 검증 절차

Dev VPC Endpoint 상태를 확인한다.

```bash
aws ec2 describe-vpc-endpoints \
  --region ap-northeast-3 \
  --filters "Name=vpc-id,Values=vpc-03a0d4dcb2dd66af8" \
  --query 'VpcEndpoints[*].{Service:ServiceName,Type:VpcEndpointType,State:State}' \
  --output table
```

확인 대상:

| Endpoint | Type |
| --- | --- |
| S3 | Gateway |
| ECR DKR | Interface |
| ECR API | Interface |
| STS | Interface |
| SSM | Interface |
| CloudWatch Logs | Interface |
| KMS | Interface |
| Secrets Manager | Interface |

Endpoint Security Group을 확인한다.

```bash
aws ec2 describe-security-groups \
  --region ap-northeast-3 \
  --group-ids <VPC_ENDPOINT_SG_ID> \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json
```

---

## 8. Security Group 검증 절차

검증 대상 관계:

| 흐름 | 확인 내용 |
| --- | --- |
| ALB → EKS | ALB SG에서 EKS 워커 노드 접근 가능 |
| EKS → RDS | PostgreSQL 5432 접근 가능 |
| EKS → Redis | Redis 6379 접근 가능 |
| EKS → OpenSearch | HTTPS 443 접근 가능 |
| EKS → Endpoint | VPC Endpoint 443 접근 가능 |

Security Group 확인 명령어:

```bash
aws ec2 describe-security-groups \
  --region ap-northeast-3 \
  --group-ids <SECURITY_GROUP_ID> \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json
```

### EKS Cluster SG 관련 트러블슈팅

문제:

EKS NodeGroup 생성 및 데이터 리소스 접근 과정에서 Terraform으로 생성한 EKS Node SG가 아니라, EKS가 자동 생성한 Cluster SG가 실제 노드 ENI에 연결되어 있었다.

결과적으로 Redis, RDS, OpenSearch Security Group이 Terraform Node SG만 허용하고 있어 테스트 Pod에서 timeout이 발생했다.

확인 명령어:

```bash
aws ec2 describe-instances \
  --region ap-northeast-3 \
  --filters "Name=private-ip-address,Values=<NODE_PRIVATE_IP>" \
  --query 'Reservations[0].Instances[0].NetworkInterfaces[*].{ENI:NetworkInterfaceId,SGs:Groups[*].GroupId}' \
  --output json
```

해결:

`terraform/modules/security-group/main.tf`에 `eks_cluster_sg_id` 변수를 추가하고, RDS / Redis / OpenSearch 인바운드 규칙에 EKS Cluster SG를 추가했다.

검증 결과:

| 서비스 | 포트 | 결과 |
| --- | --- | --- |
| Redis | 6379 | connected |
| RDS | 5432 | connected |
| OpenSearch | 443 | connected |

---

## 9. 데이터 접근 검증 절차

테스트 Pod를 확인한다.

```bash
kubectl get pod test-pod -o wide
```

Redis 연결 확인:

```bash
kubectl exec test-pod -- bash -c "echo > /dev/tcp/moment-dev-redis.o0zxzf.ng.0001.apn3.cache.amazonaws.com/6379 && echo 'connected'"
```

RDS 연결 확인:

```bash
kubectl exec test-pod -- bash -c "echo > /dev/tcp/moment-dev-postgres.c3qggqseuzcb.ap-northeast-3.rds.amazonaws.com/5432 && echo 'connected'"
```

OpenSearch 연결 확인:

```bash
kubectl exec test-pod -- bash -c "echo > /dev/tcp/vpc-moment-dev-opensearch-hdseoos3ibawg6xwwlaa4hff3u.ap-northeast-3.es.amazonaws.com/443 && echo 'connected'"
```

S3 접근 확인:

```bash
kubectl exec test-pod -- bash -c "curl -s --connect-timeout 10 -o /dev/null -w '%{http_code}' https://s3.ap-northeast-3.amazonaws.com"
```

S3 응답 코드 기준:

| 응답 코드 | 의미 |
| --- | --- |
| 200 | 접근 성공 |
| 307 | 리전 리다이렉트 응답, 네트워크 접근 성공 |
| 403 | 인증 없이 접근하여 거부됨, 네트워크 접근 성공 |
| timeout | 네트워크 또는 Endpoint 경로 확인 필요 |

---

## 10. Prod 선택 활성화 검증

Prod 비용 리소스가 기본 apply에서 생성되지 않는지 확인한다.

RDS:

```bash
aws rds describe-db-instances \
  --region ap-northeast-3 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `prod`)].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}' \
  --output table
```

ElastiCache:

```bash
aws elasticache describe-cache-clusters \
  --region ap-northeast-3 \
  --query 'CacheClusters[?contains(CacheClusterId, `prod`)].{ID:CacheClusterId,Status:CacheClusterStatus}' \
  --output table
```

OpenSearch:

```bash
aws es list-domain-names \
  --region ap-northeast-3 \
  --query 'DomainNames[?contains(DomainName, `prod`)]' \
  --output table
```

아무 결과도 나오지 않으면 기본 apply에서 Prod 비용 리소스가 생성되지 않은 것이다.

### Prod 활성화 원칙

Prod App 경로는 최종 시연 또는 운영 리허설 기간에만 명시적으로 활성화한다.

활성화 대상:

- Prod ALB
- Prod Ingress
- Prod EKS NodeGroup
- CloudFront Origin 연결
- Edge Layer 연결 검증

종료 후에는 비용 통제를 위해 다음 중 하나를 수행한다.

1. `terraform destroy`
2. enable flag 비활성화
3. Prod 관련 tfvars 값을 false로 변경 후 apply

---

## 11. Edge Layer 검증 절차

CloudFront Distribution 확인:

```bash
aws cloudfront list-distributions \
  --query 'DistributionList.Items[*].{Domain:DomainName,Id:Id,Status:Status,Enabled:Enabled}' \
  --output table
```

CloudFront 접근 확인:

```bash
curl -sv --connect-timeout 10 -o /dev/null -w '%{http_code}' https://d3thdar7t21331.cloudfront.net
```

검증 기준:

| 결과 | 의미 |
| --- | --- |
| HTTPS/TLS 연결 성공 | CloudFront 접근 가능 |
| WAF 통과 | WAF Web ACL 연결 정상 |
| 502 | Prod ALB 미연결 상태에서는 예상 가능한 응답 |
| 200 | Origin 연결까지 정상 |

WAF Web ACL 확인:

```bash
aws wafv2 list-web-acls \
  --region us-east-1 \
  --scope CLOUDFRONT \
  --output table
```

ACM 인증서 확인:

```bash
aws acm list-certificates \
  --region us-east-1 \
  --query 'CertificateSummaryList[*].{Domain:DomainName,Arn:CertificateArn}' \
  --output table
```

CloudFront용 ACM 인증서는 반드시 `us-east-1`에 있어야 한다.

---

## 12. App 계층 장애 발생 시 1차 확인 순서

장애 발생 시 아래 순서대로 확인한다.

1. AWS 인증 상태 확인
2. EKS Cluster ACTIVE 여부 확인
3. NodeGroup ACTIVE 여부 확인
4. `kubectl get nodes`
5. `kubectl get pods -A`
6. AWS Load Balancer Controller Pod 상태 확인
7. IngressClass 확인
8. Ingress 주소 확인
9. ALB Listener 확인
10. Target Group Healthy 확인
11. Security Group 인바운드 / 아웃바운드 확인
12. VPC Endpoint 상태 확인
13. Redis / RDS / OpenSearch 연결 확인
14. S3 접근 확인
15. CloudFront / WAF / ACM 상태 확인

---

## 13. 비용 발생 리소스 삭제 확인 절차

검증 후 다음 리소스의 생성 여부를 확인한다.

```bash
aws eks list-clusters --region ap-northeast-3
aws elbv2 describe-load-balancers --region ap-northeast-3 --output table
aws rds describe-db-instances --region ap-northeast-3 --output table
aws elasticache describe-cache-clusters --region ap-northeast-3 --output table
aws es list-domain-names --region ap-northeast-3 --output table
aws ec2 describe-nat-gateways --region ap-northeast-3 --output table
```

비용 발생 가능성이 큰 리소스:

- EKS Cluster
- EKS NodeGroup
- ALB
- NAT Gateway
- RDS
- ElastiCache Redis
- OpenSearch
- CloudFront
- WAF
- VPC Endpoint

---

## 14. 후속 이슈 분리 기준

아래 항목은 최종 시연 또는 운영 리허설 기간에 별도 이슈로 추적한다.

- Prod ALB / Ingress 실제 활성화
- Prod Edge Layer 실제 Origin 연결
- Prod 최종 시연 캡처 정리
- CloudFront → Prod ALB HTTP 200 검증
- 실제 운영 도메인 Route53 연결
- 운영용 ACM 인증서 DNS 검증
- Backend / Batch 최종 이미지 태그 push 검증

---

## 15. M2-VALID-A 검증 결과 요약

| 구분 | 결과 |
| --- | --- |
| ECR Repository 확인 | 완료 |
| ECR 이미지 push 테스트 | 완료 |
| Dev EKS Cluster 확인 | 완료 |
| Dev NodeGroup 확인 | 완료 |
| AWS Load Balancer Controller 확인 | 완료 |
| IngressClass 확인 | 완료 |
| Dev ALB 생성 확인 | 완료 |
| VPC Endpoint 확인 | 완료 |
| Security Group 관계 확인 | 완료 |
| Redis 연결 | 완료 |
| RDS 연결 | 완료 |
| OpenSearch 연결 | 완료 |
| S3 접근 | 완료 |
| Prod 비용 리소스 미생성 확인 | 완료 |
| Edge Layer 확인 | 완료 |
| 장애 확인 순서 문서화 | 완료 |
| 비용 리소스 삭제 절차 문서화 | 완료 |
| 후속 이슈 분리 기준 정리 | 완료 |
