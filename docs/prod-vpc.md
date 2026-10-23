# Prod VPC 구성 문서

## 1. 구성 개요

Prod VPC는 MoMent 서비스의 운영/최종 배포 환경을 위한 Service VPC이다.

Prod VPC는 Public Subnet, Private App Subnet, Private Data Subnet, TGW Attachment Subnet으로 분리하여 구성한다.

각 Subnet의 역할은 다음과 같다.

- Public Subnet: Internet-facing ALB 배치
- Private App Subnet: EKS Worker Node 및 Pod 배치
- Private Data Subnet: RDS, Redis, OpenSearch 등 데이터 계층 배치
- TGW Attachment Subnet: Transit Gateway 연결 전용 Subnet

## 2. 구성 목적

Prod VPC의 주요 목적은 다음과 같다.

- 운영/최종 배포 환경의 네트워크 기반 구성
- ALB, EKS, Data Tier의 Subnet 계층 분리
- Public 트래픽과 Private 워크로드 분리
- EKS 및 ALB Controller에서 사용할 Subnet Tag 사전 적용
- 향후 Transit Gateway 연결을 위한 Attachment Subnet 준비

## 3. 생성 리소스

| 구분 | 내용 |
|---|---|
| VPC | `moment-prod-vpc` |
| CIDR | `10.10.0.0/16` |
| Public Subnet | AZ-A, AZ-C 총 2개 |
| Private App Subnet | AZ-A, AZ-C 총 2개 |
| Private Data Subnet | AZ-A, AZ-C 총 2개 |
| TGW Attachment Subnet | AZ-A, AZ-C 총 2개 |
| Internet Gateway | Public Subnet 인터넷 연결용 |
| Public Route Table | `0.0.0.0/0 -> IGW` |
| Private App Route Table | EKS Worker Node 및 Pod용 |
| Private Data Route Table | Data Tier local 중심 구성 |
| TGW Route Table | TGW Attachment Subnet 전용 |

## 4. Subnet 구성

| Subnet Type | AZ | CIDR | 역할 |
|---|---|---|---|
| Public Subnet | ap-northeast-3a | 10.10.0.0/24 | Internet-facing ALB 배치 |
| Public Subnet | ap-northeast-3c | 10.10.1.0/24 | Internet-facing ALB 배치 |
| Private App Subnet | ap-northeast-3a | 10.10.10.0/24 | EKS Worker Node 및 Pod 배치 |
| Private App Subnet | ap-northeast-3c | 10.10.11.0/24 | EKS Worker Node 및 Pod 배치 |
| Private Data Subnet | ap-northeast-3a | 10.10.20.0/24 | RDS, Redis, OpenSearch 배치 |
| Private Data Subnet | ap-northeast-3c | 10.10.21.0/24 | RDS, Redis, OpenSearch 배치 |
| TGW Attachment Subnet | ap-northeast-3a | 10.10.100.0/28 | Transit Gateway Attachment 전용 |
| TGW Attachment Subnet | ap-northeast-3c | 10.10.100.16/28 | Transit Gateway Attachment 전용 |

## 5. Route Table 구성

### Public Route Table

Public Subnet은 Internet Gateway를 통해 외부 인터넷과 통신한다.

```text
10.10.0.0/16 -> local
0.0.0.0/0 -> Internet Gateway
```

### Private App Route Table

Private App Subnet은 EKS Worker Node 및 Pod가 배치되는 영역이다.

현재는 Transit Gateway가 아직 생성되지 않았기 때문에 local route 중심으로 구성되어 있다.

```text
10.10.0.0/16 -> local
```

Terraform 코드에서는 `transit_gateway_id` 변수를 통해 TGW ID가 전달되면 아래 라우트가 생성되도록 조건부 구현했다.

```text
0.0.0.0/0 -> Transit Gateway
10.0.0.0/16 -> Transit Gateway
```

단, 실제 TGW 생성, VPC Attachment 연결, Network VPC와의 라우팅 연결은 후속 TGW 구성 이슈에서 진행한다.

### Private Data Route Table

Private Data Subnet은 RDS, Redis, OpenSearch 등 데이터 계층 리소스가 배치되는 영역이다.

외부 인터넷 직접 경로를 두지 않고 local 중심으로 구성한다.

```text
10.10.0.0/16 -> local
```

### TGW Route Table

TGW Attachment Subnet은 향후 Transit Gateway Attachment 전용으로 사용한다.

현재는 Attachment 생성 전이므로 local route 중심으로 구성한다.

```text
10.10.0.0/16 -> local
```

## 6. EKS / ALB Subnet Tag

EKS 및 AWS Load Balancer Controller에서 Subnet을 인식할 수 있도록 Subnet Tag를 적용했다.

### Public Subnet

Internet-facing ALB 배치용 Public Subnet에는 다음 Tag를 적용했다.

```text
kubernetes.io/role/elb = 1
```

### Private App Subnet

Internal ALB 또는 Private Load Balancer 배치 가능성을 고려하여 Private App Subnet에는 다음 Tag를 적용했다.

```text
kubernetes.io/role/internal-elb = 1
```

## 7. Terraform Output

Prod VPC 모듈은 다음 output을 제공한다.

- `prod_vpc_id`
- `prod_vpc_cidr`
- `prod_public_subnet_ids`
- `prod_private_app_subnet_ids`
- `prod_private_data_subnet_ids`
- `prod_tgw_subnet_ids`
- `prod_igw_id`
- `prod_public_route_table_id`
- `prod_private_app_route_table_id`
- `prod_private_data_route_table_id`
- `prod_tgw_route_table_id`

Root module에서는 GitHub Actions 및 후속 Terraform 모듈에서 참조할 수 있도록 주요 output을 다시 노출한다.

## 8. 검증 명령어

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

## 9. 검증 결과

Dev 환경 Terraform state에서 Prod VPC 리소스 생성을 확인했다.

생성 확인 대상:

- Prod VPC
- Public Subnet 2개
- Private App Subnet 2개
- Private Data Subnet 2개
- TGW Attachment Subnet 2개
- Internet Gateway
- Public Route Table
- Private App Route Table
- Private Data Route Table
- TGW Route Table
- Route Table Association
- EKS / ALB Subnet Tag

## 10. 참고 사항

이번 이슈에서는 Prod VPC와 각 Subnet 계층, IGW, Route Table, EKS/ALB Subnet Tag를 구성한다.

Transit Gateway 본체 생성, Network VPC Attachment, Prod VPC Attachment, 실제 TGW 라우팅 연결은 후속 TGW 구성 이슈에서 진행한다.

Private App Route Table의 TGW 라우트는 `transit_gateway_id` 변수를 통해 조건부 생성되도록 구현해두었다.