# EventBridge Scheduler + Lambda Collector 데이터 파이프라인

## 개요

MoMent 인프라에서는 공공데이터 수집 파이프라인의 실행 트리거와 수집 실행 계층을 EventBridge Scheduler와 Lambda Collector로 구성한다.

전체 목표 흐름은 다음과 같다.

EventBridge Scheduler
  -> Lambda Collector
  -> Public Data API
  -> S3 Raw Bucket
  -> SQS Main Queue
  -> Spring Batch
  -> RDS / OpenSearch

M2-DATA-01에서는 EventBridge Scheduler, Lambda Collector, S3 Raw Bucket, SQS Main Queue로 이어지는 기본 인프라 골격을 구성했다.

M2-DATA-02에서는 Lambda Collector가 실제 공공데이터 API를 호출하고, 응답 원본을 S3 Raw Bucket에 저장한 뒤 Spring Batch 인계를 위한 SQS 메시지를 발행하도록 확장했다.

## Dev / Prod 활성화 정책

MoMent Terraform 구성은 Dev-first / Prod-optional 전략을 따른다.

| Environment | 기본값 | 설명 |
| --- | --- | --- |
| dev | enabled | 개발 및 검증용 EventBridge Scheduler + Lambda Collector |
| prod | disabled | 최종 데모 또는 리허설 시점에만 명시적으로 활성화 |

기본 변수는 다음과 같다.

    enable_dev_data_pipeline  = true
    enable_prod_data_pipeline = false

단, 데이터 파이프라인은 SQS Main Queue URL과 S3 Raw Bucket 이름을 필요로 하므로 다음 조건이 함께 만족되어야 생성된다.

- Dev: enable_dev_data_pipeline && enable_dev_sqs && enable_dev_s3_raw_bucket
- Prod: enable_prod_data_pipeline && enable_prod_sqs && enable_prod_s3_raw_bucket

## S3 Raw Bucket 분리 기준

Raw Bucket은 Dev/Prod 환경별로 분리한다.

| Environment | Terraform module | 기본 활성화 | 용도 |
| --- | --- | --- | --- |
| dev | module.dev_s3_raw_bucket | enabled | 개발 및 수집 검증용 Raw 저장소 |
| prod | module.prod_s3_raw_bucket | disabled | 최종 데모 또는 리허설 시점의 운영 후보 Raw 저장소 |
| shared | 제거됨 | 미사용 | 신규 수집 경로에서는 사용하지 않음 |

신규 데이터 수집 경로에서는 Shared Raw Bucket을 사용하지 않는다.

Lambda Collector는 각 환경의 RAW_BUCKET_NAME 환경변수로 전달된 bucket에 원본 응답을 저장한다.
Spring Batch는 SQS 메시지의 rawBucketName과 rawObjectKey를 기준으로 S3 Raw object를 읽는다.

Shared Raw Bucket은 현재 AWS 실제 리소스와 Terraform state에 존재하지 않으며, shared environment의 Terraform 코드에서도 생성 경로를 제거한다.
Shared Raw Bucket을 실제로 생성하거나 import하거나 state 이동하지 않는다.

## Lambda Collector

Lambda Collector는 다음 환경변수를 사용한다.

| 환경변수 | 설명 |
| --- | --- |
| PROJECT_NAME | 프로젝트 이름 |
| ENVIRONMENT | dev 또는 prod |
| RAW_BUCKET_NAME | S3 Raw Bucket 이름 |
| QUEUE_URL | SQS Main Queue URL |
| PUBLIC_DATA_API_URL | legacy 단일 API URL. 신규 source config 사용 시 비워둔다. |
| DATA_PIPELINE_SOURCES_JSON | legacy inline source JSON. 큰 source config는 사용하지 않는다. |
| DATA_PIPELINE_SOURCES_SECRET_NAME | Secrets Manager에 저장된 public data source config 이름 |

M2-DATA-02 기준 Collector는 다음 기능을 지원한다.

- Secrets Manager에서 source config 조회
- Secrets Manager에서 공공데이터 API key 조회
- 서울 열린데이터광장 path-style OpenAPI 페이지네이션
- data.go.kr query parameter 기반 페이지네이션
- JSON/XML/CSV/text/binary 응답의 Raw 저장
- S3 Raw Bucket raw/{sourceName}/{sourceDetail}/yyyy/mm/dd/ prefix 저장
- Spring Batch 인계를 위한 SQS 메시지 발행
- 수집 실패 시 failed/{sourceName}/{sourceDetail}/ prefix에 실패 payload 저장

## Source Config 관리

공공데이터 source config는 Lambda 환경변수에 직접 넣지 않고 Secrets Manager에 저장한다.

이유는 Lambda UpdateFunctionConfiguration 요청 크기 제한으로 인해, 여러 source JSON을 환경변수에 직접 넣으면 배포가 실패할 수 있기 때문이다.

Dev 환경 source config Secret 이름은 다음과 같다.

    moment/dev/public-data/source-config

API key Secret 이름은 다음과 같다.

    moment/dev/public-data/seoul-openapi
    moment/dev/public-data/data-go-kr

Git에는 실제 API key를 저장하지 않는다. Terraform에는 Secret 이름과 구조만 포함한다.

## Source 운영 메타데이터

M2-DATA-03부터 source config는 수집 방식과 갱신 주기를 명시할 수 있다.

| 필드 | 설명 | 기본값 |
| --- | --- | --- |
| triggerType | 수집 트리거 유형. 예: SCHEDULED_API, S3_UPLOAD, MANUAL, AD_HOC | SCHEDULED_API |
| updateFrequency | 원천 데이터 갱신 주기. 예: DAILY, WEEKLY, MONTHLY, YEARLY, AD_HOC | UNKNOWN |

Lambda Collector는 기존 source config와의 호환성을 위해 값이 없으면 기본값을 채운다.
또한 trigger_type, update_frequency처럼 snake_case로 들어온 값도 각각 triggerType, updateFrequency로 정규화한다.

기존 1차 source config에서 사용하던 SCHEDULED 값은 SCHEDULED_API로 정규화한다.
EVENT 값은 S3_UPLOAD로, ON_DEMAND 값은 AD_HOC로 정규화하여 기존 표현과의 호환성을 유지한다.
지원하지 않는 triggerType 값은 조용히 건너뛰지 않고 source config 오류로 처리한다.

## 데이터 성격별 수집 전략

공공데이터 파이프라인은 모든 데이터를 동일한 주기로 수집하지 않고, 데이터의 업데이트 주기와 source별 triggerType에 따라 수집 방식을 분리한다.

| 데이터 성격 | triggerType | updateFrequency 예시 | 수집 경로 |
| --- | --- | --- | --- |
| 자주 갱신되는 API 데이터 | SCHEDULED_API | DAILY, WEEKLY | EventBridge Scheduler -> Lambda Collector -> Public Data API -> S3 -> SQS |
| CSV 파일 또는 장주기 파일 데이터 | S3_UPLOAD | YEARLY, AD_HOC | S3 업로드 또는 수동 업로드 이벤트 기반 |
| 필요 시점에만 재수집하는 데이터 | MANUAL | MONTHLY, YEARLY, AD_HOC | 운영자 수동 트리거 기반 |
| 임시 검증 또는 단발성 수집 | AD_HOC | AD_HOC | 필요 시점의 일회성 실행 |

EventBridge Scheduler 기반 Lambda Collector는 SCHEDULED_API source만 정기 수집 대상으로 처리한다.
S3_UPLOAD, MANUAL, AD_HOC source는 정기 Scheduler 실행에서 API 호출, S3 Raw 저장, SQS 메시지 발행을 수행하지 않고 SKIPPED 결과로 남긴다.

Dev / Prod 분리는 환경 격리와 검증/운영 분리를 위한 구조다.
source별 수집 전략은 Dev / Prod 여부만으로 결정하지 않고 triggerType과 updateFrequency 기준으로 판단한다.

CSV처럼 갱신 주기가 긴 데이터는 매일 API 수집 대상으로 보지 않고, S3 업로드 이벤트 또는 수동 트리거 기반으로 처리하여 불필요한 파이프라인 실행을 줄인다.

## 현재 수집 Source

M2-DATA-02 검증 기준 source config에는 다음 11개 source가 활성화되어 있다.

| sourceName | sourceDetail | 원천 | 용도 |
| --- | --- | --- | --- |
| seoul_public_program | education | 서울 공공서비스예약 교육 | program 후보 |
| seoul_public_program | culture | 서울 공공서비스예약 문화 | program 후보 |
| seoul_public_program | sport | 서울 공공서비스예약 체육 | program 후보 |
| seoul_public_program | medical | 서울 공공서비스예약 진료 | program 후보 |
| seoul_public_program | institution | 서울 공공서비스예약 기관 | institution 후보 |
| seoul_care | wooridongne_kium | 우리동네키움센터 | care/institution 후보 |
| seoul_care | joint_childcare_room | 공동육아방 | care/institution 후보 |
| seoul_care | local_child_center | 지역아동센터 | care/institution 후보 |
| seoul_care | joint_childcare_sharing | 공동육아나눔터 | care/institution 후보 |
| seoul_academy | academy_info | 서울시 학원 교습소정보 | academy/institution/program 후보 |
| government_benefit | service_list | 대한민국 공공서비스 혜택 정보 | benefit_master 후보 |

## SQS 메시지 스키마

Lambda Collector는 S3 Raw object 저장 후 다음 형태의 메시지를 SQS Main Queue에 발행한다.

    {
      "schemaVersion": "1.0",
      "sourceName": "seoul_public_program",
      "sourceDetail": "education",
      "triggerType": "SCHEDULED_API",
      "updateFrequency": "DAILY",
      "rawBucketName": "moment-dev-raw-data-...",
      "rawObjectKey": "raw/seoul_public_program/education/yyyy/mm/dd/page.json",
      "collectedAt": "2026-05-26T03:26:50.761430Z",
      "contentType": "application/json;charset=UTF-8",
      "recordCount": 403,
      "totalCount": 403,
      "environment": "dev",
      "page": {
        "pageIndex": 1,
        "startIndex": 1,
        "endIndex": 1000,
        "pageSize": 1000
      },
      "contentLength": 8819964
    }

Spring Batch는 이후 이 메시지의 rawBucketName, rawObjectKey, sourceName, sourceDetail을 기준으로 S3 Raw 데이터를 읽고 정제/적재한다.
triggerType과 updateFrequency는 source별 운영 메타데이터로 사용하며, Batch 스케줄 조정이나 원천 데이터 갱신 주기 판단에 활용할 수 있다.
정기 Scheduler 실행에서 SKIPPED 처리된 source는 S3 Raw object와 SQS 메시지를 생성하지 않는다.

## 검증 결과

M2-DATA-02 Dev 검증에서 다음 수집이 성공했다.

| Source | 수집 건수 |
| --- | ---: |
| seoul_public_program / education | 403 |
| seoul_public_program / culture | 1,166 |
| seoul_public_program / sport | 710 |
| seoul_public_program / medical | 20 |
| seoul_public_program / institution | 635 |
| seoul_care / wooridongne_kium | 276 |
| seoul_care / joint_childcare_room | 44 |
| seoul_care / local_child_center | 412 |
| seoul_care / joint_childcare_sharing | 40 |
| seoul_academy / academy_info | 25,493 |
| government_benefit / service_list | 10,955 |

총 수집 검증 건수는 40,154건이다.

검증된 항목은 다음과 같다.

- Lambda invoke StatusCode 200
- failedCount 0
- S3 Raw object 저장 확인
- SQS Main Queue 메시지 발행 확인
- source config Secret 복구 확인
- Scheduler는 DISABLED 상태 유지

## IAM 권한

Lambda Collector 실행 Role은 IAM 모듈의 lambda_collector Role을 재사용한다.

부여되는 권한은 다음과 같다.

| 대상 | 권한 |
| --- | --- |
| CloudWatch Logs | Lambda 기본 실행 로그 |
| S3 Raw Bucket | raw / processed / failed prefix 접근 |
| SQS Main Queue | SendMessage, GetQueueAttributes |
| Secrets Manager | DescribeSecret, GetSecretValue |

EventBridge Scheduler는 별도의 invoke role을 사용하여 Lambda Collector를 호출한다.

## Scheduler 상태

Scheduler state 기본값은 DISABLED다.

개발 중 예기치 않은 주기 실행과 비용 발생을 막기 위해, 수동 검증 전까지는 DISABLED 상태를 유지한다.

Dev Scheduler를 실제 주기 실행하려면 다음 값을 명시적으로 변경한다.

    dev_data_pipeline_schedule_state = "ENABLED"

Prod Scheduler는 최종 데모 또는 리허설 기간 외에는 DISABLED 또는 미생성 상태를 유지한다.

## Destroy 주의사항

삭제 전에는 다음을 확인한다.

- S3 Raw Bucket에 보존해야 할 원본 객체가 있는지 확인
- SQS Main Queue / DLQ에 남은 메시지가 있는지 확인
- Lambda CloudWatch Logs 보존 필요 여부 확인
- Secrets Manager에 저장된 source config와 API key 보존 필요 여부 확인
- Prod 데이터 파이프라인은 활성화 전후로 비용과 데이터 보존 여부를 별도 확인

## 후속 작업

M2-DATA-02는 Raw 수집과 S3/SQS 인계 검증까지 담당한다.

다음 단계는 Backend Spring Batch 영역이다.

- SQS 메시지 소비
- S3 Raw object 읽기
- sourceName/sourceDetail 기반 파서 분기
- institution / program / benefit_master 정제 및 upsert
- OpenSearch indexing 연계
