# M2-VALID-B Network / TGW / Data / IAM / Destroy Runbook

## 1. 목적

본 문서는 MoMent M2 Infra Bootstrap 단계에서 구성한 Network, Transit Gateway, Data, IAM, Destroy 운영 절차를 정리한다.

M2-VALID-B는 신규 인프라 리소스를 추가로 구현하는 작업이 아니라, 선행 이슈에서 이미 검증한 결과를 기반으로 운영자가 재확인할 수 있는 절차와 비용 통제 및 destroy runbook을 문서화하는 것을 목표로 한다.

## 2. 검증 범위

- Terraform Backend
- Network VPC
- OpenVPN 관리자 접근 경로
- Transit Gateway 및 Route Table
- IAM / OIDC / IRSA
- Dev Data 계층
  - RDS PostgreSQL
  - OpenSearch
  - SQS / DLQ
  - EventBridge Scheduler
  - Lambda Collector
  - S3 Raw Bucket
- Prod 선택 활성화 정책
- Terraform apply / destroy 운영 절차
- 비용 발생 리소스 점검 절차

## 3. 선행 이슈 검증 결과 요약

본 Runbook은 아래 선행 이슈에서 수행한 검증 결과를 기반으로 한다.

- M2-TF-02: Terraform S3 Backend + State Lock 구성
- M2-NET-02: Transit Gateway + Route Table + 3-VPC Attachment 구성
- M2-IAM-01: IAM Role / OIDC / IRSA 권한 구조 구성
- M2-RDS-01: Dev-first RDS PostgreSQL 구성
- M2-SEARCH-01: Dev-first OpenSearch 구성
- M2-SQS-01: Dev-first SQS + DLQ 구성
- M2-DATA-01: EventBridge Scheduler + Lambda Collector 기본 골격 구성
- M2-DATA-02: Lambda Collector 공공데이터 API 연동 및 S3/SQS 수집 검증
- M2-NET-05: Network VPC OpenVPN 관리자 접근 경로 구성

## 4. Terraform Backend 운영 기준

Terraform Backend는 인프라 상태 파일과 Lock을 관리하는 핵심 리소스이다.

Backend S3 Bucket과 State Lock 리소스는 일반 애플리케이션 인프라 destroy 대상에 포함하지 않는다.

확인 항목:

- S3 Backend Bucket 존재 여부
- Bucket Versioning 활성화 여부
- Public Access Block 설정 여부
- Server-side Encryption 설정 여부
- State Lock 동작 여부
- terraform init 성공 여부

확인 명령어:

    terraform -chdir=terraform/environments/dev init
    terraform -chdir=terraform/environments/dev state list

## 5. Network VPC / OpenVPN 운영 확인 절차

Network VPC는 관리자 접근, 중앙 NAT Egress, Transit Gateway 연결 허브 역할을 수행한다.

관리자는 일반 사용자 트래픽 경로가 아니라 OpenVPN을 통해 Network VPC로 진입한 뒤 Transit Gateway를 통해 Dev 또는 Prod 내부 리소스에 접근한다.

확인 항목:

- Network VPC 생성 상태
- Public Subnet 생성 상태
- TGW Attachment Subnet 생성 상태
- Internet Gateway 연결 상태
- NAT Gateway 생성 상태
- OpenVPN EC2 생성 상태
- OpenVPN Security Group 인바운드 제한
- OpenVPN 접속 가능 여부

확인 명령어:

    aws ec2 describe-vpcs \
      --region ap-northeast-3 \
      --filters "Name=tag:Project,Values=moment" \
      --output table

    aws ec2 describe-nat-gateways \
      --region ap-northeast-3 \
      --filter "Name=state,Values=available" \
      --output table

    aws ec2 describe-instances \
      --region ap-northeast-3 \
      --filters "Name=tag:Name,Values=*openvpn*" \
      --output table

## 6. Transit Gateway 라우팅 확인 절차

Transit Gateway는 Network VPC, Dev VPC, Prod VPC를 연결한다.

단, Dev와 Prod는 직접 통신하지 않으며 TGW Route Table에서 No route 또는 Blackhole 정책으로 차단한다.

라우팅 정책:

| Route Table | Destination | Next Hop |
| --- | --- | --- |
| Network RT | 10.10.0.0/16 | Prod VPC Attachment |
| Network RT | 10.20.0.0/16 | Dev VPC Attachment |
| Prod RT | 10.0.0.0/16 | Network VPC Attachment |
| Prod RT | 0.0.0.0/0 | Network VPC Attachment |
| Prod RT | 10.20.0.0/16 | No route 또는 Blackhole |
| Dev RT | 10.0.0.0/16 | Network VPC Attachment |
| Dev RT | 0.0.0.0/0 | Network VPC Attachment |
| Dev RT | 10.10.0.0/16 | No route 또는 Blackhole |

확인 명령어:

    aws ec2 describe-transit-gateways \
      --region ap-northeast-3 \
      --output table

    aws ec2 describe-transit-gateway-vpc-attachments \
      --region ap-northeast-3 \
      --output table

    aws ec2 describe-transit-gateway-route-tables \
      --region ap-northeast-3 \
      --output table

## 7. IAM / IRSA 권한 구조 확인 절차

IAM / IRSA 구조는 EKS Pod와 Controller가 장기 Access Key 없이 필요한 AWS 리소스에 접근하도록 구성한다.

확인 항목:

- EKS OIDC Provider
- AWS Load Balancer Controller IRSA Role
- Backend Pod IRSA Role
- Batch Pod IRSA Role
- AI Service Pod IRSA Role
- Lambda Collector IAM Role
- ServiceAccount annotation 구조

확인 명령어:

    aws iam list-open-id-connect-providers

    aws iam list-roles \
      --query 'Roles[?contains(RoleName, `moment`)].RoleName' \
      --output table

## 8. Dev Data 계층 확인 절차

Dev 환경은 개발 및 검증의 기본 대상이다.

Data 계층은 외부 인터넷에 직접 노출되지 않고, EKS 워크로드 또는 내부 운영 경로에서만 접근 가능해야 한다.

RDS 확인 명령어:

    aws rds describe-db-instances \
      --region ap-northeast-3 \
      --query 'DBInstances[?contains(DBInstanceIdentifier, `moment`)].[DBInstanceIdentifier,DBInstanceStatus,PubliclyAccessible,Endpoint.Address]' \
      --output table

OpenSearch 확인 명령어:

    aws opensearch list-domain-names \
      --region ap-northeast-3

SQS 확인 명령어:

    aws sqs list-queues \
      --region ap-northeast-3 \
      --queue-name-prefix moment-dev-public-data \
      --output table

## 9. Lambda Collector / S3 / SQS 데이터 파이프라인 확인 절차

데이터 수집 파이프라인 흐름은 다음과 같다.

EventBridge Scheduler -> Lambda Collector -> Public Data API -> S3 Raw Bucket -> SQS -> Spring Batch -> RDS / OpenSearch

M2-DATA-02에서는 Lambda Collector가 실제 공공데이터 API를 호출하고, 원본 응답을 S3 Raw Bucket에 저장한 뒤 SQS 메시지를 발행하는 것까지 검증했다.

Spring Batch의 DB 적재 및 OpenSearch 색인은 후속 백엔드 이슈 범위이다.

확인 항목:

- Lambda 함수 존재
- Lambda 환경변수에 Secret Name 기반 설정 사용
- S3 Raw Bucket에 raw 객체 생성
- SQS 메시지 발행
- CloudWatch Logs에 수집 결과 기록

확인 명령어:

    aws lambda get-function \
      --region ap-northeast-3 \
      --function-name moment-dev-public-data-collector

    aws logs describe-log-groups \
      --region ap-northeast-3 \
      --log-group-name-prefix /aws/lambda/moment-dev-public-data-collector \
      --output table

    aws sqs get-queue-attributes \
      --region ap-northeast-3 \
      --queue-url <QUEUE_URL> \
      --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible

## 10. Prod 선택 활성화 정책

Prod 환경은 기본적으로 비용 절감을 위해 비활성화한다.

Prod 리소스는 최종 시연 또는 운영 리허설 기간에만 명시적으로 활성화한다.

주요 Flag:

- enable_prod_eks
- enable_prod_nodegroups
- enable_prod_rds
- enable_prod_redis
- enable_prod_opensearch
- enable_prod_sqs
- enable_prod_data_pipeline
- enable_prod_edge

운영 기준:

- 기본 apply에서는 Dev 리소스 중심으로 생성한다.
- Prod 비용 리소스는 기본 false 상태를 유지한다.
- 최종 시연 기간에만 필요한 flag를 true로 전환한다.
- 시연 종료 후 flag를 false로 되돌리거나 destroy 절차를 수행한다.

## 11. Terraform apply 운영 순서

권장 apply 순서는 의존성이 낮은 계층에서 높은 계층으로 진행한다.

1. Terraform Backend
2. ECR / Shared Services
3. Network VPC
4. Dev / Prod VPC
5. Transit Gateway
6. Security Group
7. IAM / OIDC / IRSA
8. EKS
9. Data 계층
10. SQS / S3
11. Data Pipeline
12. OpenVPN
13. Edge / Ingress 선택 활성화 리소스

apply 전에는 반드시 plan 결과에서 의도하지 않은 destroy 또는 replacement가 없는지 확인한다.

확인 명령어:

    terraform -chdir=terraform/environments/dev plan

## 12. Terraform destroy 운영 순서

destroy는 비용 리소스와 의존성이 높은 리소스부터 제거한다.

권장 destroy 순서:

1. Edge / CloudFront / WAF / ACM 선택 리소스
2. Ingress / ALB / Target Group
3. EKS Workload / NodeGroup
4. EKS Cluster
5. Data Pipeline
6. SQS / DLQ
7. OpenSearch
8. Redis
9. RDS
10. OpenVPN
11. VPC Endpoint
12. Transit Gateway Attachment
13. Transit Gateway
14. Dev / Prod VPC
15. Network VPC NAT Gateway
16. Network VPC
17. Terraform Backend 제외

주의:

- Terraform Backend S3 Bucket과 State Lock 리소스는 일반 destroy 대상에서 제외한다.
- destroy 전에는 반드시 RDS Snapshot, S3 Raw 보존 여부, SQS/DLQ 잔여 메시지, OpenSearch index 보존 여부를 확인한다.
- plan에서 예상하지 못한 destroy 또는 replacement가 보이면 apply/destroy를 중단한다.

## 13. Destroy 전 백업 / 주의사항

RDS:

- Dev 데이터는 실습용이면 삭제 가능하다.
- Prod 데이터는 destroy 전 snapshot 여부를 확인한다.
- final snapshot skip 여부를 반드시 확인한다.

S3 Raw Bucket:

- raw 데이터 보존 필요 여부를 확인한다.
- 재처리 가능한 데이터인지 확인한다.
- 삭제 전 prefix별 객체 수를 확인한다.

SQS / DLQ:

- Main Queue 잔여 메시지를 확인한다.
- DLQ 잔여 메시지를 확인한다.
- 실패 메시지 분석 필요 여부를 확인한다.

OpenSearch:

- Dev index 삭제 가능 여부를 확인한다.
- Prod index는 snapshot 또는 재색인 가능 여부를 확인한다.

ECR:

- 이미지 보존 필요 여부를 확인한다.
- 최신 demo image tag를 기록한다.

Terraform State:

- destroy 전 state backup 필요 여부를 확인한다.
- Backend는 삭제하지 않는다.

## 14. Destroy 후 잔여 리소스 확인 명령어

EKS:

    aws eks list-clusters --region ap-northeast-3

NAT Gateway:

    aws ec2 describe-nat-gateways \
      --region ap-northeast-3 \
      --filter "Name=state,Values=available,pending" \
      --output table

VPC Endpoint:

    aws ec2 describe-vpc-endpoints \
      --region ap-northeast-3 \
      --output table

Transit Gateway:

    aws ec2 describe-transit-gateways \
      --region ap-northeast-3 \
      --output table

VPC:

    aws ec2 describe-vpcs \
      --region ap-northeast-3 \
      --filters "Name=tag:Project,Values=moment" \
      --output table

ELB / ALB:

    aws elbv2 describe-load-balancers \
      --region ap-northeast-3 \
      --output table

RDS:

    aws rds describe-db-instances \
      --region ap-northeast-3 \
      --output table

OpenSearch:

    aws opensearch list-domain-names \
      --region ap-northeast-3

SQS:

    aws sqs list-queues \
      --region ap-northeast-3 \
      --queue-name-prefix moment \
      --output table

S3:

    aws s3 ls | grep moment

## 15. 비용 발생 주요 리소스 체크리스트

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

## 16. 실패 시 별도 이슈 분리 기준

아래 상황은 M2-VALID-B에서 직접 수정하지 않고 별도 이슈로 분리한다.

- 선행 이슈 범위를 넘어서는 신규 인프라 구현 필요
- EKS / Ingress / Edge 계층의 App 검증 실패
- Backend Spring Batch S3/SQS 소비 구현 필요
- Prod 활성화 정책 변경 필요
- Terraform state 불일치 또는 리소스 drift 발생
- 비용 리소스 삭제 실패
- IAM 권한이 과도하거나 누락되어 정책 수정이 필요한 경우

## 17. 최종 정리

M2-VALID-B는 M2에서 구성한 Network, TGW, Data, IAM 계층이 운영 기준에 맞게 구성되었는지 확인하고, 비용 통제를 위한 destroy 절차를 문서화하는 마감 검증 이슈이다.

본 문서는 M2-CLOSE-01에서 M2 전체 완료 체크리스트와 연결되는 기준 문서로 사용한다.
