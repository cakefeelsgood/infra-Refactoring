# Dev VPC 구성 문서

## 1. 구성 개요

Dev VPC는 MoMent 서비스의 개발 및 검증 환경을 위한 Service VPC이다.

Dev VPC는 Prod VPC와 동일하게 Public Subnet, Private App Subnet, Private Data Subnet, TGW Attachment Subnet으로 분리하여 구성한다.

각 Subnet의 역할은 다음과 같다.

- Public Subnet: ALB 배치 가능 영역
- Private App Subnet: EKS Worker Node 및 Pod 배치 가능 영역
- Private Data Subnet: Dev 데이터 리소스 배치 가능 영역
- Reserved Data Subnet: 향후 Multi-AZ Data Tier 확장 대비 영역
- TGW Attachment Subnet: Transit Gateway 연결 전용 Subnet

## 2. 구성 목적

Dev VPC의 주요 목적은 다음과 같다.

- 개발/검증 환경의 네트워크 기반 구성
- Prod와 동일한 Subnet 계층 구조 유지
- ALB, EKS, Data Tier의 Subnet 계층 분리
- 비용 최적화를 위한 Dev 데이터 리소스 축소 배치 가능 구조 확보
- Reserved Data Subnet을 통한 향후 Multi-AZ 확장 가능성 유지
- EKS 및 ALB Controller에서 사용할 Subnet Tag 사전 적용
- 향후 Transit Gateway 연결을 위한 Attachment Subnet 준비

## 3. 생성 리소스

| 구분 | 내용 |
|---|---|
| VPC | `moment-dev-vpc` |
| CIDR | `10.20.0.0/16` |
| Public Subnet | AZ-A, AZ-C 총 2개 |
| Private App Subnet | AZ-A, AZ-C 총 2개 |
| Private Data Subnet | AZ-A 1개 |
| Reserved Data Subnet | AZ-C 1개 |
| TGW Attachment Subnet | AZ-A, AZ-C 총 2개 |
| Internet Gateway | Public Subnet 인터넷 연결용 |
| Public Route Table | `0.0.0.0/0 -> IGW` |
| Private App Route Table | EKS Worker Node 및 Pod용 |
| Private Data Route Table | Data Tier local 중심 구성 |
| TGW Route Table | TGW Attachment Subnet 전용 |

## 4. Subnet 구성

| Subnet Type | AZ | CIDR | 역할 |
|---|---|---|---|
| Public Subnet | ap-northeast-3a | 10.20.0.0/24 | ALB 배치 가능 |
| Public Subnet | ap-northeast-3c | 10.20.1.0/24 | ALB 배치 가능 |
| Private App Subnet | ap-northeast-3a | 10.20.10.0/24 | EKS Worker Node 및 Pod 배치 가능 |
| Private App Subnet | ap-northeast-3c | 10.20.11.0/24 | EKS Worker Node 및 Pod 배치 가능 |
| Private Data Subnet | ap-northeast-3a | 10.20.20.0/24 | Dev RDS, Redis, OpenSearch 배치 가능 |
| Reserved Data Subnet | ap-northeast-3c | 10.20.21.0/24 | Reserved for Multi-AZ Data Tier |
| TGW Attachment Subnet | ap-northeast-3a | 10.20.100.0/28 | Transit Gateway Attachment 전용 |
| TGW Attachment Subnet | ap-northeast-3c | 10.20.100.16/28 | Transit Gateway Attachment 전용 |

## 5. Route Table 구성

### Public Route Table

Public Subnet은 Internet Gateway를 통해 외부 인터넷과 통신한다.

```text
10.20.0.0/16 -> local
0.0.0.0/0 -> Internet Gateway
```

### Private App Route Table

Private App Subnet은 EKS Worker Node 및 Pod가 배치되는 영역이다.

현재는 Transit Gateway가 아직 생성되지 않았기 때문에 local route 중심으로 구성되어 있다.

```text
10.20.0.0/16 -> local
```

Terraform 코드에서는 `transit_gateway_id` 변수를 통해 TGW ID가 전달되면 아래 라우트가 생성되도록 조건부 구현했다.

```text
0.0.0.0/0 -> Transit Gateway
10.0.0.0/16 -> Transit Gateway
```

단, 실제 TGW 생성, VPC Attachment 연결, Network VPC와의 라우팅 연결은 후속 TGW 구성 이슈에서 진행한다.

### Private Data Route Table

Private Data Subnet은 Dev 데이터 계층 리소스가 배치되는 영역이다.

외부 인터넷 직접 경로를 두지 않고 local 중심으로 구성한다.

```text
10.20.0.0/16 -> local
```

### TGW Route Table

TGW Attachment Subnet은 향후 Transit Gateway Attachment 전용으로 사용한다.

현재는 Attachment 생성 전이므로 local route 중심으로 구성한다.

```text
10.20.0.0/16 -> local
```

## 6. Reserved Data Subnet 기준

Dev VPC는 비용 최적화를 위해 데이터 리소스를 단일 AZ 또는 축소 구성할 수 있다.

다만 Prod와 동일한 네트워크 구조를 유지하고 향후 Multi-AZ Data Tier 확장을 고려하기 위해 반대편 Private Data Subnet은 삭제하지 않고 Reserved Data Subnet으로 유지한다.

Reserved Data Subnet에는 다음 Tag를 적용한다.

```text
Tier = reserved-data
Role = reserved-for-multi-az-data-tier
```

## 7. EKS / ALB Subnet Tag

EKS 및 AWS Load Balancer Controller에서 Subnet을 인식할 수 있도록 Subnet Tag를 적용했다.

### Public Subnet

ALB 배치 가능 Public Subnet에는 다음 Tag를 적용했다.

```text
kubernetes.io/role/elb = 1
```

### Private App Subnet

Internal ALB 또는 Private Load Balancer 배치 가능성을 고려하여 Private App Subnet에는 다음 Tag를 적용했다.

```text
kubernetes.io/role/internal-elb = 1
```

## 8. Terraform Output

Dev VPC 모듈은 다음 output을 제공한다.

- `dev_vpc_id`
- `dev_vpc_cidr`
- `dev_public_subnet_ids`
- `dev_private_app_subnet_ids`
- `dev_private_data_subnet_ids`
- `dev_reserved_data_subnet_ids`
- `dev_tgw_subnet_ids`
- `dev_igw_id`
- `dev_public_route_table_id`
- `dev_private_app_route_table_id`
- `dev_private_data_route_table_id`
- `dev_tgw_route_table_id`

Root module에서는 GitHub Actions 및 후속 Terraform 모듈에서 참조할 수 있도록 주요 output을 다시 노출한다.

## 9. 검증 명령어

```bash
terraform init -reconfigure
terraform fmt -recursive
terraform validate
terraform plan -detailed-exitcode
```

## 10. 참고 사항

이번 이슈에서는 Dev VPC와 각 Subnet 계층, IGW, Route Table, EKS/ALB Subnet Tag를 구성한다.

Transit Gateway 본체 생성, Network VPC Attachment, Dev VPC Attachment, 실제 TGW 라우팅 연결은 후속 TGW 구성 이슈에서 진행한다.

Private App Route Table의 TGW 라우트는 `transit_gateway_id` 변수를 통해 조건부 생성되도록 구현해두었다.

Dev ↔ Prod 직접 라우팅은 이번 이슈에서 구성하지 않는다.
