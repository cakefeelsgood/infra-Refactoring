# Terraform Environment 분리 전략

## 1. 목적

MoMent Terraform 구성은 Dev와 Prod뿐 아니라 Network, Shared 성격 리소스까지 environment와 state 기준으로 분리할 수 있도록 정리한다.

M2-OPS-01에서는 `terraform/environments/prod` 골격과 `prod/terraform.tfstate` state key를 분리했다.

M2-OPS-02에서는 기존 `terraform/environments/dev` 안에 함께 있던 Network, Shared, Dev, Prod 리소스 구조를 장기적으로 다음 기준으로 분리할 수 있도록 skeleton과 이관 전략을 정리한다.

- `terraform/environments/network`
- `terraform/environments/shared`
- `terraform/environments/dev`
- `terraform/environments/prod`

이번 작업은 실제 전체 apply, state mv, import를 수행하지 않는다.

## 2. Environment 구조

    terraform/
    ├── environments/
    │   ├── network/
    │   ├── shared/
    │   ├── dev/
    │   └── prod/
    └── modules/

| Environment | Backend key | 역할 |
| --- | --- | --- |
| network | network/terraform.tfstate | Network VPC, TGW, OpenVPN, 중앙 NAT, Network SG |
| shared | shared/terraform.tfstate | GitHub OIDC, 공통 IAM 후보, 환경별 Raw Bucket policy 입력 기준 |
| dev | dev/terraform.tfstate | Dev VPC, Dev EKS, Dev Data Tier, Dev SQS/Data Pipeline |
| prod | prod/terraform.tfstate | Prod VPC, Prod EKS, Prod Data Tier, Prod SQS/Data Pipeline, Edge |

## 3. Environment별 관리 기준

### 3.1 Network environment

`terraform/environments/network`는 장기적으로 다음 리소스를 관리한다.

- Network VPC
- Network Security Group
- OpenVPN
- Transit Gateway
- 중앙 NAT Egress
- TGW Route Table
- TGW Attachment 기준

현재 skeleton에서는 실제 module wiring을 수행하지 않고, migration candidate만 정리한다.

현재 Network migration 후보는 다음과 같다.

- `network_vpc`
- `network_security_group`
- `network_openvpn`
- `transit_gateway`

Network 관련 enable flag는 기본 false이다.

    enable_network_vpc     = false
    enable_transit_gateway = false
    enable_openvpn         = false

### 3.2 Shared environment

`terraform/environments/shared`는 장기적으로 다음 리소스를 관리한다.

- GitHub OIDC Provider
- 공통 IAM Role / Policy
- 환경별 Raw Bucket access policy 입력 기준
- 공통 Secrets Manager 기준
- OpenSearch service-linked role 기준 검토
- Terraform backend bucket / lock table 기준 검토

현재 skeleton에서는 실제 module wiring을 수행하지 않고, migration candidate와 account-level candidate만 정리한다.

현재 Shared migration 후보는 다음과 같다.

- `iam`
- `s3_raw_bucket` 제거 완료

Account-level 후보는 다음과 같다.

- `github_oidc_provider`
- `common_iam_role_policy`
- `opensearch_service_linked_role`
- `terraform_backend_bucket`
- `terraform_lock_table`

Shared 관련 enable flag는 기본 false이다.

    enable_common_iam           = false
    create_github_oidc_provider = false

### 3.3 Dev environment

`terraform/environments/dev`는 장기적으로 Dev 전용 리소스를 관리한다.

- Dev VPC
- Dev Security Groups
- Dev VPC Endpoints
- Dev EKS
- Dev Managed NodeGroups
- Dev RDS / Redis / OpenSearch
- Dev SQS / Data Pipeline

기존 dev environment에는 Network, Shared, Prod module 호출이 함께 남아 있을 수 있다.

이 리소스들은 state 이관 전략 없이 바로 삭제하지 않는다.

### 3.4 Prod environment

`terraform/environments/prod`는 장기적으로 Prod 전용 리소스를 관리한다.

- Prod VPC
- Prod Security Groups
- Prod VPC Endpoints
- Prod EKS
- Prod RDS / Redis / OpenSearch
- Prod SQS / Data Pipeline
- Prod ALB / Edge Layer

Prod 관련 enable flag는 비용 방지를 위해 기본 false이다.

    enable_prod_vpc            = false
    enable_prod_vpc_endpoints  = false
    enable_prod_eks            = false
    enable_prod_nodegroups     = false
    enable_prod_data_tier      = false
    enable_prod_rds            = false
    enable_prod_redis          = false
    enable_prod_opensearch     = false
    enable_prod_sqs            = false
    enable_prod_data_pipeline  = false
    enable_edge                = false

## 4. Dev environment에 남아 있는 이관 후보

기존 `terraform/environments/dev/main.tf`에 남아 있는 후보는 다음 기준으로 분류한다.

### 4.1 Network 후보

- `network_vpc`
- `network_security_group`
- `network_openvpn`
- `transit_gateway`

### 4.2 Shared 후보

- `iam`
- `s3_raw_bucket` 제거 완료

### 4.3 Prod 후보

- `prod_vpc`
- `prod_security_group`
- `prod_vpc_endpoint`
- `prod_sqs`
- `prod_data_pipeline`
- `prod_eks`
- `prod_redis`
- `prod_rds`
- `prod_opensearch`
- `edge`

`prod_eks_nodegroups`는 변수는 존재하지만, 기존 dev/main.tf 기준 실제 module 호출은 확인 후 별도 이슈에서 다룬다.

## 5. Shared/account-level 리소스 기준

다음 리소스는 특정 환경에 무작정 복제하지 않는다.

| 리소스 | 기준 |
| --- | --- |
| ECR | Dev/Prod별 분리 관리. shared에 두지 않고 `dev_ecr`, `prod_ecr` 기준으로 관리 |
| GitHub OIDC Provider | account-level 리소스이며 중복 생성 금지 |
| 공통 IAM Role / Policy | Shared environment 후보 |
| OpenSearch service-linked role | account-level 리소스이며 중복 생성 금지 |
| S3 Raw Bucket | Dev/Prod 환경별 분리 관리. Shared Raw Bucket은 생성 경로를 제거하며 신규 수집 경로에서는 사용하지 않음 |
| Terraform backend bucket / lock table | backend 자체는 별도 관리 대상이며 environment에서 중복 생성하지 않음 |
| Network VPC / TGW | Network environment 후보 |

Prod data pipeline은 Prod environment의 prod_s3_raw_bucket과 prod_sqs를 직접 참조하는 구조를 사용한다.

    enable_prod_s3_raw_bucket = false
    prod_raw_bucket_name      = null

## 6. Network / TGW 분리 기준

Network VPC는 OpenVPN, 중앙 NAT Egress, Transit Gateway hub 역할을 담당한다.

TGW는 Network, Dev, Prod VPC를 연결하지만 Dev와 Prod 직접 통신은 허용하지 않는다.

기준 라우팅 정책은 다음과 같다.

| Route Table | CIDR | Next hop |
| --- | --- | --- |
| Network RT | 10.10.0.0/16 | Prod attachment |
| Network RT | 10.20.0.0/16 | Dev attachment |
| Prod RT | 10.0.0.0/16 | Network attachment |
| Prod RT | 0.0.0.0/0 | Network attachment |
| Prod RT | 10.20.0.0/16 | No route / Blackhole |
| Dev RT | 10.0.0.0/16 | Network attachment |
| Dev RT | 0.0.0.0/0 | Network attachment |
| Dev RT | 10.10.0.0/16 | No route / Blackhole |

Prod 또는 Dev environment에서 TGW ID가 필요할 경우 Network state output을 remote state로 참조하거나, 명시적 variable로 주입한다.

현재 skeleton 단계에서는 Network/TGW remote state 연결을 활성화하지 않는다.

## 7. State 이동 / Import 전략

이번 이슈에서는 실제 state 이동을 하지 않는다.

향후 실제 이관이 필요할 경우 다음 순서로 진행한다.

1. 현재 state 확인
2. AWS 실제 리소스 존재 여부 확인
3. dev state가 관리 중인 리소스와 state 밖 리소스 구분
4. 이동 대상은 `terraform state mv` 후보로 분류
5. state 밖 기존 리소스는 `terraform import` 후보로 분류
6. shared/account-level 리소스 중복 생성 여부 확인
7. network/shared/prod/dev 각각 target address 준비
8. 별도 승인 후 state mv 또는 import 수행
9. 각 environment별 `terraform plan`에서 destroy/replacement 여부 확인
10. 안전 확인 후 기존 dev module 호출 제거 검토

## 8. 이번 이슈에서 하지 않는 것

- Prod 전체 리소스 apply
- Network 전체 리소스 apply
- Shared 전체 리소스 apply
- 기존 Dev 리소스 삭제
- 실제 state mv/import
- Network/shared/dev/prod 전체 state migration 완료
- Prod NodeGroup 세부 운영 스펙 설계
- RDS/Redis/OpenSearch HA 세부 스펙 설계
- Edge Layer 실제 CloudFront 배포 검증
- Kubernetes Deployment, Ingress, GitOps manifest 수정

## 9. 검증 명령어

Network environment 정적 검증:

    terraform -chdir=terraform/environments/network init -backend=false
    terraform -chdir=terraform/environments/network validate

Shared environment 정적 검증:

    terraform -chdir=terraform/environments/shared init -backend=false
    terraform -chdir=terraform/environments/shared validate

Prod environment 정적 검증:

    terraform -chdir=terraform/environments/prod init -backend=false
    terraform -chdir=terraform/environments/prod validate

Dev environment 영향 확인:

    terraform -chdir=terraform/environments/dev validate

전체 포맷 확인:

    terraform fmt -recursive

## 10. 운영 주의사항

- 각 environment의 backend key가 서로 다른지 확인한다.
- Network/Shared/Prod 리소스는 기본 false로 유지한다.
- apply는 별도 승인 후 수행한다.
- state mv/import는 별도 승인 후 수행한다.
- GitHub OIDC Provider, OpenSearch service-linked role 같은 account-level 리소스를 중복 생성하지 않는다.
- Prod ALB DNS 없이 Edge를 활성화하지 않는다.
- TGW route 변경은 Dev ↔ Prod 직접 통신 차단 원칙을 유지한다.
- Terraform plan에서 destroy/replacement가 보이면 apply하지 않고 중단한다.

## 11. ECR Dev/Prod 분리 기준

ECR은 shared environment에 두지 않는다.

MoMent는 Dev와 Prod 이미지 저장소를 명확히 분리하기 위해 다음 기준을 사용한다.

| Environment | Module | Repository 예시 |
| --- | --- | --- |
| dev | dev_ecr | moment-dev-backend-api, moment-dev-ai-service, moment-dev-batch-job |
| prod | prod_ecr | moment-prod-backend-api, moment-prod-ai-service, moment-prod-batch-job |

기존 공통 ECR Repository가 이미 AWS에 존재하거나 state에 남아 있다면 바로 삭제하지 않는다.

향후 실제 이관 시 다음 중 하나를 선택한다.

1. 기존 공통 ECR을 유지한 채 신규 Dev/Prod ECR을 별도 생성
2. 기존 공통 ECR 이미지를 Dev/Prod ECR로 복사 후 공통 ECR 제거
3. state에 남아 있는 기존 `module.ecr` 주소를 별도 승인 후 정리

이번 이슈에서는 ECR apply, image copy, state mv/import를 수행하지 않는다.

## Dev environment cleanup result

이번 변경에서는 Dev environment에서 Prod/Network/Shared 관리 대상 module을 제거한다.

Dev environment에 남는 관리 대상은 다음과 같다.

- Dev ECR
- Dev VPC
- Dev Security Groups
- Dev VPC Endpoints
- Dev SQS
- Dev Data Pipeline
- Dev EKS
- Dev EKS NodeGroups
- Dev Redis
- Dev RDS
- Dev OpenSearch

Network environment는 다음 module을 관리 대상으로 가진다.

- Network VPC
- Network Security Groups
- Transit Gateway
- OpenVPN

Shared environment는 다음 module 후보를 가진다.

- S3 Raw Bucket 생성 경로 제거 완료
- Common IAM / GitHub OIDC / Lambda Collector Role / EKS Role 기준

ECR은 Shared environment에 두지 않는다.

- Dev ECR: terraform/environments/dev
- Prod ECR: terraform/environments/prod

단, 실제 state mv/import/apply는 이번 PR에서 수행하지 않는다.

## 12. S3 Raw Bucket Dev/Prod 분리 기준

S3 Raw Bucket은 신규 데이터 수집 경로에서 Dev/Prod 환경별로 분리한다.

- Dev Raw Bucket: terraform/environments/dev의 module.dev_s3_raw_bucket 기준
- Prod Raw Bucket: terraform/environments/prod의 module.prod_s3_raw_bucket 기준
- Shared Raw Bucket: terraform/environments/shared에서 생성 경로 제거, 신규 수집 경로에서는 사용하지 않음

현재 AWS 실제 리소스와 Terraform state 기준으로 Shared Raw Bucket은 존재하지 않는다.
따라서 이번 정리에서는 S3 Bucket 생성, 삭제, import, state mv를 수행하지 않는다.

상세 기준은 docs/s3-raw-bucket.md를 따른다.
