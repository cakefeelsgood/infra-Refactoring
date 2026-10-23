# RDS PostgreSQL Dev / Prod 스펙 분리 및 보호 옵션

본 문서는 MoMent 인프라의 RDS PostgreSQL 구성 기준을 정리한다.

M2-RDS-02의 핵심 목표는 Dev / Prod RDS 스펙을 명확히 분리하고, Prod RDS에 필요한 보호 옵션을 Terraform 변수로 드러내는 것이다.

## 1. 배치 위치

RDS PostgreSQL은 외부 인터넷에 직접 노출하지 않는다.

- Dev RDS: Dev VPC Private Data Subnet
- Prod RDS: Prod VPC Private Data Subnet
- Publicly Accessible: false
- 접근 경로: EKS Node / Pod Security Group에서 PostgreSQL 5432만 허용

RDS는 애플리케이션의 사용자, 자녀 프로필, 프로그램, 추천, 신청, 결제 데이터를 저장하는 관계형 데이터베이스 역할을 한다.

## 2. Dev RDS 기본 스펙

Dev 환경은 개발 및 검증을 위한 기본 환경이다.

비용 절감을 우선하며, 필요 시 destroy / apply를 반복할 수 있는 실습용 구성을 기본값으로 둔다.

| 항목 | 기본값 | 기준 |
| --- | --- | --- |
| instance class | db.t4g.micro | 실습 및 개발 검증용 최소 비용 |
| allocated storage | 20 GiB | Dev 기본 용량 |
| max allocated storage | 100 GiB | 자동 확장 상한 |
| Multi-AZ | false | 비용 절감 |
| backup retention | 1 day | 최소 보관 |
| deletion protection | false | Dev destroy 가능 |
| skip final snapshot | true | Dev 데이터는 재생성 가능하다는 전제 |
| backup window | 18:00-19:00 | Terraform 변수로 관리 |
| maintenance window | sun:19:00-sun:20:00 | Terraform 변수로 관리 |

Dev RDS 관련 변수는 `dev_rds_*` 접두사를 사용한다.

대표 변수:

    dev_rds_instance_class
    dev_rds_allocated_storage
    dev_rds_max_allocated_storage
    dev_rds_multi_az
    dev_rds_backup_retention_period
    dev_rds_backup_window
    dev_rds_maintenance_window
    dev_rds_deletion_protection
    dev_rds_skip_final_snapshot
    dev_rds_final_snapshot_identifier

## 3. Prod RDS 기본 스펙

Prod 환경은 최종 시연 또는 운영 리허설 시점에만 선택적으로 활성화한다.

Prod RDS는 비용보다 데이터 보호와 운영 안정성을 우선한다.

| 항목 | 기본값 | 기준 |
| --- | --- | --- |
| instance class | db.t4g.small | Dev보다 높은 운영 검증 기준 |
| allocated storage | 50 GiB | Prod 최소 운영 용량 |
| max allocated storage | 200 GiB | 자동 확장 상한 |
| Multi-AZ | true | AWS RDS Multi-AZ Primary / Standby 구성 |
| backup retention | 14 days | 운영 데이터 보호 |
| deletion protection | true | 실수 삭제 방지 |
| skip final snapshot | false | 삭제 전 최종 스냅샷 보존 |
| backup window | 18:00-19:00 | Terraform 변수로 관리 |
| maintenance window | sun:19:00-sun:20:00 | Terraform 변수로 관리 |

Prod RDS 관련 변수는 `prod_rds_*` 접두사를 사용한다.

대표 변수:

    enable_prod_rds
    prod_rds_instance_class
    prod_rds_allocated_storage
    prod_rds_max_allocated_storage
    prod_rds_multi_az
    prod_rds_backup_retention_period
    prod_rds_backup_window
    prod_rds_maintenance_window
    prod_rds_deletion_protection
    prod_rds_skip_final_snapshot
    prod_rds_final_snapshot_identifier

## 4. Prod Multi-AZ Standby 설계 기준

Prod RDS는 `prod_rds_multi_az = true`를 기본값으로 둔다.

Terraform에서 Multi-AZ Standby는 별도 `aws_db_instance` 리소스를 하나 더 만드는 방식이 아니다.

`aws_db_instance`에 `multi_az = true`를 설정하면 AWS RDS가 DB Subnet Group 안의 다른 AZ에 Standby를 자동 구성한다.

현재 설계 기준:

- Prod RDS는 Prod Private Data Subnet Group을 사용한다.
- Prod RDS 활성화 시 `multi_az = var.prod_rds_multi_az`를 통해 Multi-AZ 구성을 사용한다.
- `prod_rds_multi_az` 기본값은 true이다.
- 실제 Prod RDS apply는 비용 정책상 수행하지 않았다.
- Multi-AZ Standby의 실제 생성 확인은 Prod 활성화 검증 시점에 수행한다.

## 5. Read Replica 기준

M2-RDS-02에서는 Read Replica를 실제로 생성하지 않는다.

다만 향후 읽기 부하 증가 또는 조회 API 분산이 필요할 때 확장할 수 있도록 다음 flag만 둔다.

    enable_prod_rds_read_replica = false

현재 기준:

- 기본값은 false
- 실제 replica resource는 생성하지 않음
- Read Replica 생성은 후속 이슈에서 다룸
- DB migration, read/write split, application datasource 분리는 백엔드 또는 후속 인프라 이슈에서 다룸

## 6. Prod 활성화 기준

Prod RDS는 다음 flag들이 모두 의도적으로 켜진 경우에만 생성된다.

    enable_prod_vpc       = true
    enable_prod_data_tier = true
    enable_prod_rds       = true

기본값은 false이며, 비용 방지를 위해 평시에는 생성하지 않는다.

Prod RDS apply는 별도 승인 후 진행한다.

## 7. State / Plan 해석 주의사항

현재 실습 계정에서는 비용 절감을 위해 Dev 리소스를 destroy / apply 반복 운영할 수 있다.

따라서 Dev remote state가 비어 있거나 Dev 리소스가 실제 AWS에 남아 있지 않은 상태에서는 `terraform plan`이 Dev VPC, EKS, RDS, Redis, OpenSearch 등을 신규 생성으로 표시할 수 있다.

이 경우 대량 create는 RDS-02 코드 변경 때문이 아니라, 현재 Dev state 및 실제 AWS Dev 리소스가 비어 있기 때문에 발생할 수 있다.

검증 시에는 다음 기준을 따른다.

- 예상하지 않은 destroy가 있으면 apply 중단
- 예상하지 않은 replacement가 있으면 apply 중단
- Prod RDS 실제 생성은 별도 승인 전 수행하지 않음
- Dev state가 빈 상태라면 plan 결과를 코드 변경 영향과 분리해서 해석

## 8. 검증 결과

현재 이슈에서는 실제 apply를 수행하지 않았다.

수행한 검증:

- `terraform fmt -recursive`
- `terraform -chdir=terraform/environments/dev validate`
- `terraform -chdir=terraform/environments/prod init -backend=false`
- `terraform -chdir=terraform/environments/prod validate`
- Dev RDS 기존 공통 변수 및 Prod RDS 잔재 grep 확인
- AWS CLI로 Dev RDS / Redis / EKS / VPC / OpenSearch / SQS 잔여 리소스 미존재 확인

## 9. 이번 이슈에서 하지 않는 것

- Terraform apply
- Prod RDS 실제 생성
- Read Replica 실제 생성
- DB migration / Flyway 변경
- Spring Boot datasource 분리
- 백엔드 API 변경
- 기존 state 복구 또는 state push
