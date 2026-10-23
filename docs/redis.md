# Redis Dev/Prod 구성 기준
 
> 관련 이슈: M2-REDIS-02  
> 담당: @armddi
 
---
 
## 1. Dev/Prod 스펙 비교
 
| 항목 | Dev | Prod |
|------|-----|------|
| `node_type` | `cache.t3.micro` | `cache.t3.small` |
| `num_cache_clusters` | 1 (Single) | 2 (Primary + Replica) |
| `automatic_failover_enabled` | false | true |
| `multi_az_enabled` | false | true |
| `snapshot_retention_limit` | 0일 | 3일 |
| `at_rest_encryption_enabled` | true | true |
| `transit_encryption_enabled` | false | false (후속 이슈) |
 
---
 
## 2. Prod Redis HA 구성
 
Prod Redis는 `aws_elasticache_replication_group` 기준으로 아래 구조로 구성한다.
 
```
[ Primary Node ]  ←→  [ Replica Node ]
   ap-northeast-3a       ap-northeast-3c
```
 
- **num_cache_clusters = 2**: Primary 1 + Replica 1
- **automatic_failover_enabled = true**: Primary 장애 시 Replica 자동 승격
- **multi_az_enabled = true**: Primary/Replica를 서로 다른 AZ에 배치
- **snapshot_retention_limit = 3**: 최근 3일 스냅샷 보관
### Subnet Group Multi-AZ 확인
 
Dev 기준 검증 결과, private data 서브넷이 2개 AZ에 걸쳐 있어 Multi-AZ 구성 가능하다.
 
| Subnet ID | AZ | CIDR |
|-----------|-----|------|
| subnet-097283f14f213411b | ap-northeast-3a | 10.20.20.0/24 |
| subnet-08151ff55d38ef95c | ap-northeast-3c | 10.20.21.0/24 |
 
Prod도 동일하게 `10.10.20.0/24` (3a), `10.10.21.0/24` (3c) 2개 AZ 구성이라 Multi-AZ 적용 가능하다.
 
---
 
## 3. Security Group 구성
 
Redis SG는 **EKS Node SG 기준 6379 포트만 허용**한다. 다른 인바운드 트래픽은 허용하지 않는다.
 
```
EKS Node SG  →  6379/tcp  →  Redis SG
EKS Cluster SG  →  6379/tcp  →  Redis SG
```
 
관련 SG Rule (`modules/security-group/main.tf`):
- `redis_ingress_from_eks_node`: EKS Node SG → Redis 6379 허용
- `redis_ingress_from_eks_cluster_sg`: EKS Cluster SG → Redis 6379 허용
- `eks_node_egress_to_redis`: EKS Node → Redis 6379 이그레스 허용
---
 
## 4. transit_encryption_enabled (TLS) 검토
 
| 항목 | 내용 |
|------|------|
| 현재 설정 | `false` |
| 이유 | M2 단계에서 redis-cli 직접 검증 필요, Spring Boot client 설정 변경 미포함 |
| 후속 조치 | TLS 활성화 시 Backend 후속 이슈로 분리 처리 |
 
### TLS 활성화 시 Spring Boot 영향
 
`transit_encryption_enabled = true`로 변경할 경우 아래 설정이 필요하다.
 
**application.yml 변경 필요 사항:**
 
```yaml
spring:
  data:
    redis:
      ssl:
        enabled: true     # TLS 활성화
      host: <primary-endpoint>
      port: 6379
```
 
**Lettuce client (기본값) 추가 설정:**
 
```java
RedisStandaloneConfiguration config = new RedisStandaloneConfiguration();
LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
    .useSsl()
    .build();
```
 
> TLS 전환은 Backend 후속 이슈로 분리. 실제 Prod 전환 전 별도 검토 필요.
 
---
 
## 5. Terraform 변수 구조
 
### modules/redis/variables.tf 주요 변수
 
| 변수 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `num_cache_clusters` | number | 1 | 클러스터 노드 수 (2 이상 시 HA) |
| `automatic_failover_enabled` | bool | false | 자동 페일오버 여부 |
| `multi_az_enabled` | bool | false | Multi-AZ 배포 여부 |
| `snapshot_retention_limit` | number | 0 | 스냅샷 보관 일수 |
| `transit_encryption_enabled` | bool | false | TLS 암호화 여부 |
 
### environments/prod/variables.tf Prod 기본값
 
| 변수 | 기본값 |
|------|--------|
| `prod_redis_node_type` | `cache.t3.small` |
| `prod_redis_num_cache_clusters` | `2` |
| `prod_redis_automatic_failover_enabled` | `true` |
| `prod_redis_multi_az_enabled` | `true` |
| `prod_redis_snapshot_retention_limit` | `3` |
 
---
 
## 6. Read Replica
 
이번 범위에서 Read Replica 실제 생성은 제외한다.  
`num_cache_clusters = 2` 구성이 Primary + Replica 역할을 수행한다.  
추가 Replica가 필요한 경우 `num_cache_clusters` 값을 증가시킨다.
 
---
 
## 7. Prod Apply 절차
 
실제 Prod Redis apply는 별도 승인 후 진행한다.
 
```bash
# 1. prod/terraform.tfvars (또는 -var 플래그)에서 플래그 활성화
enable_prod_data_tier = true
enable_prod_redis     = true
 
# 2. Redis만 타겟 apply
cd terraform/environments/prod
terraform apply -target=module.prod_redis
```
 
> EKS, TGW 등 다른 리소스에 영향 없음. `-target` 사용으로 Redis 모듈만 apply된다.