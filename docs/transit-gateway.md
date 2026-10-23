# Transit Gateway + Route Table + 3-VPC Attachment

## 개요

MoMent 인프라는 Single AWS Account 기반 Multi-VPC Logical Separation Architecture를 기준으로 한다.

이번 M2-NET-02 작업에서는 Network VPC, Prod VPC, Dev VPC를 Transit Gateway에 연결하고, Transit Gateway Route Table을 통해 환경 간 통신 가능 여부를 제어한다.

## 대상 VPC

| 구분 | CIDR | 역할 |
| --- | --- | --- |
| Network VPC | 10.0.0.0/16 | 관리자 접근, 중앙 NAT, TGW 연결 허브 |
| Prod VPC | 10.10.0.0/16 | 운영/최종 배포 환경 |
| Dev VPC | 10.20.0.0/16 | 개발/검증 환경 |

## 생성 리소스

| 리소스 | 값 |
| --- | --- |
| Transit Gateway | tgw-0958ffaf8fb1b4206 |
| Network Attachment | tgw-attach-030ec10f173062cf9 |
| Prod Attachment | tgw-attach-070bce14fba3a3117 |
| Dev Attachment | tgw-attach-047cb6843ecefd04b |
| Network TGW Route Table | tgw-rtb-0d19e0e47a7aa79b7 |
| Prod TGW Route Table | tgw-rtb-08aa2e04abb8c8bc5 |
| Dev TGW Route Table | tgw-rtb-005d32113b4163650 |

## 라우팅 정책

핵심 정책은 다음과 같다.

- Network VPC ↔ Prod VPC 허용
- Network VPC ↔ Dev VPC 허용
- Prod VPC ↔ Dev VPC 직접 통신 차단
- Prod / Dev Private App Subnet의 인터넷 egress는 Network VPC 중앙 NAT 경로로 전달

## Network TGW Route Table

| Destination | Target | Type | State |
| --- | --- | --- | --- |
| 10.10.0.0/16 | Prod Attachment | propagated | active |
| 10.20.0.0/16 | Dev Attachment | propagated | active |

## Prod TGW Route Table

| Destination | Target | Type | State |
| --- | --- | --- | --- |
| 0.0.0.0/0 | Network Attachment | static | active |
| 10.0.0.0/16 | Network Attachment | propagated | active |
| 10.20.0.0/16 | Blackhole | static | blackhole |

## Dev TGW Route Table

| Destination | Target | Type | State |
| --- | --- | --- | --- |
| 0.0.0.0/0 | Network Attachment | static | active |
| 10.0.0.0/16 | Network Attachment | propagated | active |
| 10.10.0.0/16 | Blackhole | static | blackhole |

## VPC Route Table 연결

Prod / Dev Private App Route Table에는 TGW 경로가 추가된다.

| VPC | Route Table | Destination | Target |
| --- | --- | --- | --- |
| Prod | Private App RT | 0.0.0.0/0 | Transit Gateway |
| Prod | Private App RT | 10.0.0.0/16 | Transit Gateway |
| Dev | Private App RT | 0.0.0.0/0 | Transit Gateway |
| Dev | Private App RT | 10.0.0.0/16 | Transit Gateway |

Network VPC Public Route Table에는 Prod / Dev CIDR로 돌아가는 경로가 추가된다.

| VPC | Route Table | Destination | Target |
| --- | --- | --- | --- |
| Network | Public RT | 10.10.0.0/16 | Transit Gateway |
| Network | Public RT | 10.20.0.0/16 | Transit Gateway |

## 검증 결과

Terraform apply 결과는 다음과 같다.

Apply complete! Resources: 24 added, 0 changed, 0 destroyed.

Apply 이후 plan 결과는 다음과 같다.

No changes. Your infrastructure matches the configuration.
PLAN_EXIT_CODE=0

AWS CLI로 확인한 TGW 상태는 다음과 같다.

Transit Gateway: available
Default Association: disable
Default Propagation: disable

Prod / Dev 직접 통신 차단 확인 결과는 다음과 같다.

Prod RT: 10.20.0.0/16 blackhole
Dev RT: 10.10.0.0/16 blackhole

## 운영 메모

현재 구조에서는 Prod VPC와 Dev VPC가 같은 Transit Gateway에 연결되어 있지만, 서로 직접 통신하지 않는다.

환경 간 통신 제어는 Transit Gateway Route Table에서 수행하며, Network VPC만 운영 접근 및 중앙 NAT 허브 역할을 담당한다.


## M2-NET-08 Network VPC NAT Egress 정합성

Transit Gateway를 통해 Network VPC로 전달된 Dev / Prod Private App Subnet의 외부 egress 트래픽은 Network VPC 내부에서 AZ별 NAT Gateway를 통해 처리한다.

Network VPC의 TGW Attachment Subnet Route Table은 단일 Route Table을 공유하지 않고 AZ별로 분리한다.

| Network TGW Subnet | Default Route | 목적 |
| --- | --- | --- |
| AZ-A TGW Subnet | `0.0.0.0/0 -> AZ-A NAT Gateway` | 동일 AZ NAT egress |
| AZ-C TGW Subnet | `0.0.0.0/0 -> AZ-C NAT Gateway` | 동일 AZ NAT egress |

이 구조는 단일 NAT Gateway에 egress가 몰리는 구성을 제거하고, 최종 Multi-AZ Network VPC 설계와 Terraform 구현을 일치시키기 위한 기준이다.
