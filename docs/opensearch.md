# OpenSearch Dev/Prod 스펙 분리 및 Prod HA 옵션 기준

본 문서는 MoMent 인프라의 Amazon OpenSearch Service 구성 기준을 정리한다.

M2-SEARCH-02의 핵심 목표는 Dev / Prod OpenSearch 스펙을 명확히 분리하고, Prod 환경에서 사용할 수 있는 HA 옵션을 Terraform 변수로 드러내는 것이다.

## 1. 배치 위치

OpenSearch는 외부 인터넷에 직접 노출하지 않는다.

- Dev OpenSearch: Dev VPC Private Data Subnet
- Prod OpenSearch: Prod VPC Private Data Subnet
- 접근 경로: EKS Node / Pod Security Group에서 HTTPS 443만 허용
- 용도: 검색 인덱싱, 검색 후보 조회, AI 검색 보조, 공공데이터 색인 연계

## 2. Dev / Prod 기본 스펙 비교

| 항목 | Dev | Prod |
| --- | --- | --- |
| data node instance type | t3.small.search | t3.medium.search |
| data node count | 1 | 2 |
| zone awareness | false | true |
| availability zone count | - | 2 |
| dedicated master | false | true |
| dedicated master count | - | 3 |
| dedicated master type | - | t3.small.search |
| Multi-AZ with Standby | false | false |
| EBS volume type | gp3 | gp3 |
| EBS volume size | 10 GiB | 50 GiB |
| encryption at rest | true | true |
| node-to-node encryption | true | true |
| HTTPS enforcement | true | true |

Dev는 개발 및 검증을 위한 단일 노드 구성을 유지한다.

Prod는 비용 최적화보다 운영 안정성을 우선하므로 다음 기준을 둔다.

- 2개 AZ에 data node를 분산한다.
- dedicated master node 3개를 사용한다.
- Dev보다 높은 data node instance type과 EBS 용량을 사용한다.
- Multi-AZ with Standby는 현재 2-AZ VPC 구조와 맞지 않으므로 기본값 false로 둔다.
- 향후 Prod VPC가 3-AZ로 확장되면 Multi-AZ with Standby를 true로 전환할 수 있도록 변수만 제공한다.

## 3. Prod HA 옵션 기준

Prod OpenSearch는 다음 flag들이 모두 의도적으로 켜진 경우에만 생성된다.

    enable_prod_vpc        = true
    enable_prod_data_tier  = true
    enable_prod_opensearch = true

기본값은 false이며, 실제 Prod OpenSearch apply는 별도 승인 후 진행한다.

Prod HA 관련 대표 변수:

    prod_opensearch_instance_type
    prod_opensearch_instance_count
    prod_opensearch_dedicated_master_enabled
    prod_opensearch_dedicated_master_type
    prod_opensearch_dedicated_master_count
    prod_opensearch_zone_awareness_enabled
    prod_opensearch_availability_zone_count
    prod_opensearch_multi_az_with_standby_enabled
    prod_opensearch_ebs_volume_size

## 4. Multi-AZ with Standby 기준

Amazon OpenSearch Service의 Multi-AZ with Standby는 3개 AZ 기반 구성을 요구한다.

현재 MoMent Prod VPC는 다음 2개 Private Data Subnet을 기준으로 한다.

| AZ | CIDR | 용도 |
| --- | --- | --- |
| ap-northeast-3a | 10.10.20.0/24 | Prod Private Data Subnet |
| ap-northeast-3c | 10.10.21.0/24 | Prod Private Data Subnet |

따라서 M2-SEARCH-02에서는 다음 기준을 따른다.

- `prod_opensearch_multi_az_with_standby_enabled = false`
- `prod_opensearch_zone_awareness_enabled = true`
- `prod_opensearch_availability_zone_count = 2`
- `prod_opensearch_dedicated_master_enabled = true`
- `prod_opensearch_dedicated_master_count = 3`

향후 3-AZ Prod VPC 구조가 추가되면 다음 조건을 만족할 때 Standby 구성을 활성화할 수 있다.

- Prod Private Data Subnet 3개
- `availability_zone_count = 3`
- dedicated master 3개
- data node count는 3의 배수
- Standby 지원 instance family 사용

## 5. Terraform 모듈 기준

`terraform/modules/opensearch`는 Dev / Prod 공통 모듈이다.

모듈은 다음 옵션을 제공한다.

| 변수 | 설명 |
| --- | --- |
| `instance_type` | data node instance type |
| `instance_count` | data node count |
| `dedicated_master_enabled` | dedicated master 사용 여부 |
| `dedicated_master_type` | dedicated master instance type |
| `dedicated_master_count` | dedicated master node 수 |
| `zone_awareness_enabled` | AZ 분산 여부 |
| `availability_zone_count` | AZ 개수 |
| `multi_az_with_standby_enabled` | Multi-AZ with Standby 사용 여부 |
| `ebs_volume_type` | EBS volume type |
| `ebs_volume_size` | EBS volume size |

모듈에는 다음 validation / precondition을 둔다.

- zone awareness 활성화 시 subnet 수와 AZ count가 일치해야 한다.
- zone awareness 활성화 시 data node 수는 AZ count 이상이어야 한다.
- dedicated master 활성화 시 master node 수는 3 또는 5만 허용한다.
- Multi-AZ with Standby 활성화 시 3개 AZ, 3개 dedicated master, data node count 3의 배수 조건을 만족해야 한다.

## 6. State / Plan 해석 주의사항

현재 Prod OpenSearch 도메인은 기본 비활성화 상태이다.

Prod state에 OpenSearch domain이 없는 상태에서는 Prod OpenSearch target plan이 신규 생성으로 표시될 수 있다.

검증 시에는 다음 기준을 따른다.

- 예상하지 않은 destroy가 있으면 apply 중단
- 예상하지 않은 replacement가 있으면 apply 중단
- Prod OpenSearch 실제 생성은 별도 승인 전 수행하지 않음
- OpenSearch service-linked role은 account-level 리소스이므로 중복 생성하지 않음

## 7. 이번 이슈에서 하지 않는 것

- Terraform apply
- Prod OpenSearch 실제 생성
- OpenSearch index 생성
- Spring Batch OpenSearch Writer 구현
- Backend 검색 API 변경
- AI Service 검색 로직 변경
- 3-AZ Prod VPC 확장
