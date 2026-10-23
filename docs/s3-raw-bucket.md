# S3 Raw Bucket Dev/Prod 분리 기준

## 1. 목적

MoMent 데이터 파이프라인에서 사용하는 S3 Raw Bucket의 Dev/Prod 분리 기준과 Shared Raw Bucket 잔재 처리 기준을 정리한다.

이번 문서는 M2-S3-02 기준으로 다음 내용을 명확히 한다.

- Dev Raw Bucket과 Prod Raw Bucket의 책임 분리
- Shared Raw Bucket의 현재 상태
- Terraform state와 AWS 실제 리소스 기준 확인 결과
- Data Pipeline / IAM 연결 기준
- 향후 migration 또는 import가 필요한 경우의 주의사항

## 2. 결론

신규 데이터 수집 경로에서는 Shared Raw Bucket을 사용하지 않는다.

MoMent는 Dev-first / Prod-optional 전략을 따르므로 Raw Bucket도 환경별로 분리한다.

| Environment | Terraform module | 기본 bucket naming | 기본 활성화 | 용도 |
| --- | --- | --- | --- | --- |
| dev | module.dev_s3_raw_bucket | moment-dev-raw-data-{account_id}-{region} | true | 개발 및 수집 검증용 Raw 저장소 |
| prod | module.prod_s3_raw_bucket | moment-prod-raw-data-{account_id}-{region} | false | 최종 데모 또는 리허설 시점의 운영 후보 Raw 저장소 |
| shared | 제거됨 | 없음 | 미사용 | 신규 수집 경로에서는 사용하지 않음 |

## 3. Dev Raw Bucket 기준

Dev Raw Bucket은 terraform/environments/dev에서 관리한다.

Dev 데이터 파이프라인은 다음 리소스를 직접 참조한다.

- module.dev_s3_raw_bucket[0].raw_bucket_name
- module.dev_s3_raw_bucket[0].raw_bucket_access_policy_arn
- module.dev_sqs[0].queue_url
- module.dev_iam[0].lambda_collector_role_arn

Lambda Collector는 RAW_BUCKET_NAME 환경변수로 Dev Raw Bucket 이름을 전달받고, 수집 원본을 raw / processed / failed prefix 기준으로 저장한다.

Dev Raw Bucket은 개발 및 검증을 위한 기본 경로이며, 운영 데이터와 섞지 않는다.

## 4. Prod Raw Bucket 기준

Prod Raw Bucket은 terraform/environments/prod에서 관리한다.

Prod 데이터 파이프라인은 다음 리소스를 직접 참조한다.

- module.prod_s3_raw_bucket[0].raw_bucket_name
- module.prod_s3_raw_bucket[0].raw_bucket_access_policy_arn
- module.prod_sqs[0].queue_url
- module.prod_iam[0].lambda_collector_role_arn

Prod Raw Bucket은 비용과 데이터 보존 정책 때문에 기본 비활성화 상태를 유지한다.

Prod 데이터 파이프라인을 실제로 활성화하려면 다음 flag를 명시적으로 검토해야 한다.

- enable_prod_s3_raw_bucket
- enable_prod_sqs
- enable_prod_iam
- enable_prod_data_pipeline

Prod 활성화는 최종 데모 또는 리허설 시점에만 별도 승인 후 진행한다.

## 5. Shared Raw Bucket 정리 기준

Shared Raw Bucket은 현재 운영 중인 리소스가 아니다.

확인 결과는 다음과 같다.

- AWS 계정에 moment raw bucket 없음
- Terraform dev/prod/shared state에 S3 Raw Bucket 리소스 없음
- shared state 리소스 수 0개
- shared 기본 plan은 실제 인프라 변경 없이 output만 추가
- shared environment의 S3 Raw Bucket 생성 경로는 Terraform 코드에서 제거됨
- Shared Raw Bucket 신규 생성, import, state mv는 수행하지 않음

따라서 shared의 module.s3_raw_bucket 생성 경로는 Terraform 코드에서 제거한다.

Shared environment에는 IAM, GitHub OIDC, 공통 role/policy 후보만 남기고, Raw Bucket은 Dev/Prod 환경별 module에서 관리한다.

단, 신규 Dev/Prod 데이터 수집 경로에서는 Shared Raw Bucket을 사용하지 않는다.

## 6. IAM 연결 기준

Raw Bucket 접근 권한은 각 환경의 Raw Bucket access policy ARN을 IAM module에 전달하는 방식으로 구성한다.

Dev 기준:

- module.dev_s3_raw_bucket[0].raw_bucket_access_policy_arn
- module.dev_iam raw_bucket_access_policy_arns

Prod 기준:

- module.prod_s3_raw_bucket[0].raw_bucket_access_policy_arn
- module.prod_iam raw_bucket_access_policy_arns

Shared IAM module은 raw_bucket_access_policy_arns 입력을 받을 수 있으나, 신규 데이터 파이프라인의 기본 경로는 Dev/Prod 환경별 IAM과 Raw Bucket 연결이다.

환경별 Raw Bucket 권한 연결에는 raw_bucket_access_policy_arns 리스트를 사용한다.

## 7. Data Pipeline 연결 기준

Data Pipeline module은 bucket ARN이 아니라 raw_bucket_name을 입력으로 받는다.

Lambda Collector는 RAW_BUCKET_NAME 환경변수를 사용해 S3 put_object를 수행한다.

SQS 메시지에는 다음 값이 포함된다.

- rawBucketName
- rawObjectKey
- sourceName
- sourceDetail
- triggerType
- updateFrequency
- environment

Spring Batch는 이후 rawBucketName과 rawObjectKey를 기준으로 원본 데이터를 읽는다.

## 8. 이번 이슈에서 하지 않는 것

이번 이슈에서는 다음 작업을 하지 않는다.

- S3 Bucket 생성
- S3 Bucket 삭제
- S3 Bucket 이름 변경
- Terraform apply
- Terraform state mv
- Terraform import
- Shared Raw Bucket 강제 활성화
- Data Pipeline Lambda payload 변경
- Spring Batch 코드 변경
- Backend API 변경
- Frontend 변경

## 9. 검증 기준

이번 이슈의 검증 기준은 다음과 같다.

- terraform fmt 통과
- dev/prod/shared validate 통과
- shared 기본 plan에서 실제 리소스 변경 없음 확인
- shared S3 target plan default false에서 No changes 확인
- shared environment에서 S3 Raw Bucket 생성 경로가 제거되었는지 확인
- AWS 계정에 기존 moment raw bucket 없음 확인
- Git diff에 민감정보 없음 확인
- Terraform apply 미수행

## 10. 운영 주의사항

S3 Bucket은 이름 변경이 사실상 replacement로 이어질 수 있으므로, bucket_name 변경은 별도 이슈에서만 검토한다.

Raw Bucket에는 공공데이터 원본이 저장될 수 있으므로 destroy 전에는 반드시 다음을 확인한다.

- raw / processed / failed prefix 객체 존재 여부
- 보존해야 할 원본 수집 데이터 여부
- Spring Batch 재처리 필요 여부
- SQS 메시지와 raw object key 정합성
- IAM policy attachment 영향 범위
