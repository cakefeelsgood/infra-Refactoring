# M2-CLOSE-01 M2 Infra Bootstrap 최종 완료 체크리스트

## 1. 목적

본 문서는 MoMent M2 Infra Bootstrap 단계의 최종 완료 상태를 정리한다.

M2-CLOSE-01은 신규 인프라 리소스를 추가로 구현하는 작업이 아니라, 선행 M2 이슈와 M2-VALID-A / M2-VALID-B에서 수행한 검증 결과를 하나로 모아 M2 단계가 완료되었음을 확인하는 마감 문서이다.

최종 산출물은 M3 GitOps / CI/CD 단계로 넘어가기 위한 기준 문서로 사용한다.

## 2. M2 전체 완료 기준

M2 Infra Bootstrap은 다음 범위를 포함한다.

- Terraform Foundation
- Terraform S3 Backend / State Lock
- ECR Repository
- Network VPC
- Prod VPC
- Dev VPC
- Transit Gateway
- Security Group
- IAM / OIDC / IRSA
- EKS Cluster
- Managed NodeGroup
- RDS PostgreSQL
- Redis
- OpenSearch
- S3 Raw Bucket
- SQS / DLQ
- EventBridge Scheduler
- Lambda Collector
- OpenVPN 관리자 접근 경로
- AWS Load Balancer Controller / Ingress 준비
- Route53 / CloudFront / WAF / ACM Edge 계층 준비
- M2-VALID-A 검증
- M2-VALID-B 검증 및 Destroy Runbook

## 3. 최종 아키텍처 기준

MoMent 인프라는 Single AWS Account 기반 Multi-VPC Logical Separation Architecture를 기준으로 한다.

VPC는 다음 3개로 구성한다.

| VPC | CIDR | 역할 |
| --- | --- | --- |
| Network VPC | 10.0.0.0/16 | OpenVPN 관리자 접근, 중앙 NAT, TGW Hub |
| Prod VPC | 10.10.0.0/16 | 운영 / 최종 시연 환경 |
| Dev VPC | 10.20.0.0/16 | 개발 / 검증 환경 |

핵심 원칙은 다음과 같다.

- Network VPC는 관리자 접근과 중앙 NAT Egress를 담당한다.
- Dev VPC와 Prod VPC는 동일한 Subnet 구조를 유지한다.
- Dev와 Prod는 TGW에 연결되어 있지만 직접 통신하지 않는다.
- Dev ↔ Prod 직접 통신은 TGW Route Table의 No route 또는 Blackhole 정책으로 차단한다.
- 사용자 트래픽과 관리자 트래픽은 분리한다.
- Route53 / CloudFront / WAF / ACM은 VPC 내부가 아니라 Global / Edge Layer에 둔다.
- CloudFront Origin은 Internet Gateway가 아니라 ALB이다.

## 4. 선행 이슈 완료 요약

| 구분 | 이슈 | 상태 |
| --- | --- | --- |
| Terraform Foundation | M2-TF-01 | 완료 |
| Terraform Backend | M2-TF-02 | 완료 |
| ECR | M2-ECR-01 | 완료 |
| Network VPC | M2-NET-01 | 완료 |
| Prod VPC | M2-NET-03 | 완료 |
| Dev VPC | M2-NET-04 | 완료 |
| Transit Gateway | M2-NET-02 | 완료 |
| Security Group | M2-SEC-01 | 완료 |
| VPC Endpoint | M2-NET-06 | 완료 |
| S3 Raw Bucket | M2-S3-01 | 완료 |
| IAM / OIDC / IRSA | M2-IAM-01 | 완료 |
| EKS Cluster | M2-EKS-01 | 완료 |
| EKS NodeGroup | M2-EKS-02 | 완료 |
| AWS Load Balancer Controller | M2-EKS-03 | 완료 |
| RDS PostgreSQL | M2-RDS-01 | 완료 |
| Redis | M2-REDIS-01 | 완료 |
| OpenSearch | M2-SEARCH-01 | 완료 |
| SQS / DLQ | M2-SQS-01 | 완료 |
| Data Pipeline Skeleton | M2-DATA-01 | 완료 |
| Public Data Collector | M2-DATA-02 | 완료 |
| OpenVPN Admin Access | M2-NET-05 | 완료 |
| Edge Layer | M2-EDGE-01 | 완료 또는 선택 활성화 기준 정리 |
| VALID-A | M2-VALID-A | 완료 |
| VALID-B | M2-VALID-B | 완료 |
| CLOSE | M2-CLOSE-01 | 본 문서 |

## 5. 주요 문서 링크

| 문서 | 역할 |
| --- | --- |
| docs/network-vpc.md | Network VPC 구성 및 운영 기준 |
| docs/prod-vpc.md | Prod VPC 구성 기준 |
| docs/dev-vpc.md | Dev VPC 구성 기준 |
| docs/transit-gateway.md | TGW Attachment / Route Table 정책 |
| docs/iam-irsa.md | IAM / OIDC / IRSA 권한 구조 |
| docs/eks.md | EKS Cluster 및 Add-on 구성 기준 |
| docs/ecr.md | ECR Repository 구성 기준 |
| docs/sqs.md | SQS / DLQ 구성 및 Dev/Prod 활성화 정책 |
| docs/data-pipeline.md | EventBridge / Lambda Collector / S3 / SQS 데이터 파이프라인 |
| docs/openvpn-admin-access.md | OpenVPN 관리자 접근 경로 |
| docs/alb-controller.md | AWS Load Balancer Controller / Ingress 준비 |
| docs/m2-valid-b-runbook.md | Network / TGW / Data / IAM / Destroy 운영 Runbook |
| docs/m2-close-checklist.md | M2 Infra Bootstrap 최종 완료 체크리스트 |

## 6. M2-VALID-A 요약

M2-VALID-A는 App / EKS / Ingress / Endpoint / Edge 계층 검증을 담당한다.

검증 범위는 다음과 같다.

- ECR Repository 확인
- Dev EKS Cluster 확인
- Dev NodeGroup 확인
- AWS Load Balancer Controller 설치 확인
- IngressClass 확인
- 테스트 Ingress / ALB / Target Group 확인
- VPC Endpoint 확인
- Security Group 관계 확인
- EKS 워크로드의 AWS 리소스 접근 확인
- Prod App / Edge 선택 활성화 정책 정리

M2-VALID-A의 세부 검증 결과는 App / EKS / Ingress / Endpoint / Edge 담당 문서와 PR 결과를 기준으로 한다.

## 7. M2-VALID-B 요약

M2-VALID-B는 Network / TGW / Data / IAM / Destroy 운영 절차를 담당한다.

검증 및 문서화 범위는 다음과 같다.

- Terraform Backend 운영 기준
- Network VPC / OpenVPN 확인 절차
- Transit Gateway Route Table 확인 절차
- IAM / OIDC / IRSA 확인 절차
- Dev Data 계층 확인 절차
- Lambda Collector / S3 / SQS 데이터 파이프라인 확인 절차
- Prod 선택 활성화 flag 정책
- Terraform apply / destroy 운영 순서
- destroy 전 백업 / 주의사항
- destroy 후 잔여 리소스 확인 명령어
- 비용 발생 주요 리소스 체크리스트

세부 내용은 `docs/m2-valid-b-runbook.md`를 기준으로 한다.

## 8. Dev 기본 인프라 최종 상태

Dev 환경은 개발 및 검증의 기본 운영 환경이다.

Dev-first 전략에 따라 다음 리소스는 Dev 기준으로 구성 및 검증한다.

- Dev VPC
- Dev Public Subnet
- Dev Private App Subnet
- Dev Private Data Subnet
- Dev Reserved Data Subnet
- Dev TGW Attachment Subnet
- Dev EKS Cluster
- Dev Managed NodeGroup
- Dev RDS PostgreSQL
- Dev Redis
- Dev OpenSearch
- Dev SQS / DLQ
- Dev EventBridge Scheduler
- Dev Lambda Collector
- S3 Raw Bucket
- IAM / IRSA Role
- OpenVPN을 통한 내부 접근 경로

Dev C Zone Private Data Subnet은 비용 절감을 위해 실제 데이터 리소스를 배치하지 않을 수 있으나, Prod와 동일한 확장 가능 구조를 유지하기 위해 Reserved Data Subnet으로 남긴다.

## 9. Prod 선택 활성화 최종 기준

Prod 환경은 기본적으로 비활성화한다.

Prod 리소스는 최종 시연 또는 운영 리허설 기간에만 명시적으로 활성화한다.

주요 flag는 다음과 같다.

- enable_prod_eks
- enable_prod_nodegroups
- enable_prod_rds
- enable_prod_redis
- enable_prod_opensearch
- enable_prod_sqs
- enable_prod_data_pipeline
- enable_prod_edge

운영 기준은 다음과 같다.

- 기본 apply에서는 Prod 비용 리소스가 생성되지 않아야 한다.
- 최종 시연 또는 운영 리허설 기간에만 필요한 Prod flag를 true로 전환한다.
- Prod 운영 기간은 짧게 유지한다.
- 시연 종료 후 flag를 false로 되돌리거나 destroy 절차를 수행한다.
- Prod 데이터 리소스 destroy 전에는 백업 또는 snapshot 필요 여부를 확인한다.

## 10. Edge 계층 최종 기준

Edge 계층은 일반 사용자 트래픽 진입점이다.

최종 목표 흐름은 다음과 같다.

User -> Route53 -> CloudFront (+ WAF Web ACL, + ACM) -> Prod ALB -> EKS -> RDS / Redis / OpenSearch

정리 기준은 다음과 같다.

- Route53 / CloudFront / WAF / ACM은 VPC 내부 리소스가 아니다.
- WAF는 CloudFront에 연결되는 Web ACL이다.
- ACM은 HTTPS 인증서이다.
- CloudFront 다음 트래픽은 Internet Gateway가 아니라 ALB로 향한다.
- Prod Edge 계층은 기본 비활성화하고 최종 시연 기간에만 선택 활성화한다.

## 11. 데이터 파이프라인 최종 기준

M2 데이터 파이프라인 흐름은 다음과 같다.

EventBridge Scheduler -> Lambda Collector -> Public Data API -> S3 Raw Bucket -> SQS -> Spring Batch -> RDS / OpenSearch

M2-DATA-01은 EventBridge / Lambda / S3 / SQS 인프라 골격을 구성했다.

M2-DATA-02는 Lambda Collector가 실제 공공데이터 API를 호출하고, 원본 응답을 S3 Raw Bucket에 저장한 뒤 SQS 메시지를 발행하는 흐름을 검증했다.

Spring Batch의 SQS 소비, S3 Raw 데이터 읽기, DB upsert, OpenSearch 색인은 후속 백엔드 이슈에서 처리한다.

## 12. Destroy / 비용 운영 최종 기준

M2 이후 비용 통제는 Dev-first / Prod-optional 전략을 따른다.

기본 원칙은 다음과 같다.

- Dev 환경은 개발 및 검증 중심으로 운영한다.
- Prod 환경은 최종 시연 또는 운영 리허설 기간에만 짧게 운영한다.
- 비용이 큰 리소스는 필요 시에만 생성한다.
- destroy 전에는 데이터 보존 필요 여부를 확인한다.
- Terraform Backend S3 Bucket과 State Lock 리소스는 일반 destroy 대상에서 제외한다.
- plan에서 의도하지 않은 destroy 또는 replacement가 발생하면 apply/destroy를 중단한다.
- Billing 반영은 지연될 수 있으므로 비용 확인은 AWS CLI 리소스 잔여 확인과 함께 진행한다.

주요 비용 리소스는 다음과 같다.

- EKS Cluster
- EKS Managed NodeGroup
- NAT Gateway
- VPC Endpoint
- ALB / NLB
- CloudFront
- RDS
- Redis
- OpenSearch
- Lambda 대량 실행 로그
- SQS 메시지 적체
- S3 객체 보관
- EBS Volume
- Elastic IP
- OpenVPN EC2

## 13. M3 진행 전 인수인계 기준

M3 GitOps / CI/CD 단계는 M2에서 구성한 인프라를 기준으로 진행한다.

M3에서 참조해야 하는 기준은 다음과 같다.

- ECR Repository URL
- Dev EKS Cluster 이름
- Dev NodeGroup label / capacity 기준
- IRSA Role 및 ServiceAccount annotation 기준
- Dev Ingress / ALB Controller 기준
- S3 / SQS / Lambda Collector 데이터 파이프라인 기준
- Dev-first / Prod-optional 운영 정책
- Destroy / 비용 통제 Runbook

M3에서는 GitHub Actions, ECR Push, Helm / Kustomize, ArgoCD Sync, Dev 배포, Prod 선택 배포 전략을 이 기준 위에서 구성한다.

## 14. 실패 항목 관리 기준

M2-CLOSE-01에서는 신규 구현을 추가하지 않는다.

아래 항목은 별도 이슈로 분리한다.

- M2 범위 외 신규 인프라 구현
- Backend Spring Batch S3/SQS 소비 구현
- 애플리케이션 API 수정
- 프론트엔드 화면 수정
- M3 GitOps / CI/CD 구현
- M4 Observability 구현
- M5 HA / Security 고도화
- Terraform state drift 수정
- 비용 리소스 삭제 실패 대응

## 15. 최종 완료 선언

M2 Infra Bootstrap은 다음 조건을 만족하면 완료로 본다.

- 주요 인프라 리소스가 Terraform으로 구성되었다.
- Dev-first 운영 기준이 정리되었다.
- Prod 선택 활성화 기준이 정리되었다.
- Network / TGW / IAM / Data 계층 검증 결과가 문서화되었다.
- App / EKS / Ingress / Edge 계층 검증 결과가 문서화되었다.
- Destroy 및 비용 통제 절차가 문서화되었다.
- M3 GitOps / CI/CD 단계에서 참조할 기준 문서가 준비되었다.

본 문서를 기준으로 M2 Infra Bootstrap 단계를 종료하고, 다음 단계인 M3 GitOps / CI/CD 구축으로 진행한다.
