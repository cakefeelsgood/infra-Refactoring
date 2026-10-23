# Network VPC 구성 문서

## 1. 구성 개요

Network VPC는 MoMent 인프라에서 관리자/운영자 접근 경로, 중앙 NAT Egress, Transit Gateway 연결 허브 역할을 담당한다.

일반 사용자 트래픽을 직접 처리하는 VPC가 아니라, Dev / Prod App VPC의 Private Subnet이 외부 인터넷으로 나갈 때 중앙화된 NAT Gateway를 통해 egress 하도록 하기 위한 네트워크 허브 VPC이다.

## 2. 구성 목적

Network VPC의 주요 목적은 다음과 같다.

- 관리자/운영자 접근 경로 분리
- 중앙 NAT Gateway 기반 outbound egress 경로 구성
- 향후 Transit Gateway 연결을 위한 Attachment Subnet 준비
- Dev / Prod VPC와 Network VPC를 분리하여 네트워크 책임을 명확히 구분

## 3. 생성 리소스

| 구분 | 내용 |
|---|---|
| VPC | `moment-dev-network-vpc` |
| CIDR | `10.0.0.0/16` |
| Public Subnet | AZ-A, AZ-C 총 2개 |
| TGW Attachment Subnet | AZ-A, AZ-C 총 2개 |
| Internet Gateway | Network VPC 인터넷 연결용 |
| Elastic IP | AZ별 NAT Gateway 고정 공인 IP |
| NAT Gateway | AZ별 중앙 outbound egress용 |
| Public Route Table | `0.0.0.0/0 -> IGW` |
| TGW Route Table | AZ별 `0.0.0.0/0 -> 동일 AZ NAT Gateway` |

## 4. Subnet 구성

| Subnet Type | AZ | CIDR | 역할 |
|---|---|---|---|
| Public Subnet | ap-northeast-3a | 10.0.0.0/24 | NAT Gateway / 운영자 진입 리소스 배치 |
| Public Subnet | ap-northeast-3c | 10.0.1.0/24 | 고가용성 확장 대비 |
| TGW Attachment Subnet | ap-northeast-3a | 10.0.100.0/28 | Transit Gateway Attachment 전용 |
| TGW Attachment Subnet | ap-northeast-3c | 10.0.100.16/28 | Transit Gateway Attachment 전용 |

## 5. Route Table 구성

### Public Route Table

Public Subnet은 Internet Gateway를 통해 외부 인터넷과 통신한다.

```text
0.0.0.0/0 -> Internet Gateway
```

### TGW Route Table

TGW Attachment Subnet은 동일 AZ의 NAT Gateway를 통해 외부 egress 경로를 갖는다.

```text
TGW Subnet AZ-A: 0.0.0.0/0 -> AZ-A NAT Gateway
TGW Subnet AZ-C: 0.0.0.0/0 -> AZ-C NAT Gateway
```

단, 실제 Dev / Prod App VPC와의 연결 및 Spoke VPC의 NAT 경유 라우팅은 이후 Transit Gateway Attachment 구성 이슈에서 추가로 연결한다.

## 6. Terraform Output

Network VPC 모듈은 다음 output을 제공한다.

- `network_vpc_id`
- `public_subnet_ids`
- `tgw_subnet_ids`
- `nat_gateway_id` (하위 호환용 첫 번째 NAT Gateway ID)
- `nat_gateway_ids`
- `nat_gateway_id_map`
- `tgw_route_table_ids`
- `tgw_route_table_id_map`
- `igw_id`

## 7. 검증 명령어

```bash
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

## 8. 검증 결과

Dev 환경에서 Terraform apply를 통해 Network VPC 및 관련 네트워크 리소스 생성을 확인했다.

생성 확인 대상:

- Network VPC
- Public Subnet 2개
- TGW Attachment Subnet 2개
- Internet Gateway
- Elastic IP
- NAT Gateway 2개
- Public Route Table
- TGW Route Table 2개
- Route Table Association

## 9. 참고 사항

이번 이슈에서는 Network VPC 자체와 중앙 NAT Gateway, TGW Attachment Subnet까지만 구성한다.

Transit Gateway 생성, VPC Attachment, Dev / Prod App VPC와의 실제 라우팅 연결은 후속 네트워크 이슈에서 진행한다.

## M2-NET-08 NAT Gateway AZ 이중화 기준

Network VPC의 NAT Gateway는 비용 최적화 목적의 단일 구성이 아니라 최종 설계 정합성을 기준으로 AZ별 이중화한다.

- Public Subnet 수와 동일한 수의 NAT Gateway를 생성한다.
- NAT Gateway마다 Elastic IP를 1개씩 할당한다.
- TGW Attachment Subnet별 Route Table을 분리한다.
- 각 TGW Attachment Subnet의 `0.0.0.0/0` 경로는 동일 AZ의 NAT Gateway를 바라본다.
- 기존 단일 output은 하위 호환용으로 유지하되, 신규 구현에서는 `nat_gateway_ids`, `nat_gateway_id_map`, `tgw_route_table_ids`, `tgw_route_table_id_map`을 우선 사용한다.
