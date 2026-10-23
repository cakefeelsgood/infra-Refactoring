# SQS + DLQ 구성

## 개요

MoMent 인프라에서는 공공데이터 수집 이후 비동기 배치 처리를 위해 SQS Main Queue와 DLQ를 구성한다.

SQS는 EventBridge Scheduler와 Lambda Collector, Spring Batch 사이의 비동기 메시지 전달 계층으로 사용한다.

기본 흐름은 다음과 같다.

EventBridge Scheduler
  -> Lambda Collector
  -> S3 Raw Bucket 저장
  -> SQS Main Queue 메시지 전송
  -> Spring Batch Job 메시지 소비
  -> RDS / OpenSearch 적재

처리에 반복 실패한 메시지는 DLQ로 이동하여 실패 원인을 분리 확인할 수 있도록 한다.

## Dev / Prod 활성화 정책

MoMent Terraform 구성에서는 Dev 환경을 기본 검증 대상으로 설정한다.

| Environment | 기본값 | Queue | DLQ |
| --- | --- | --- | --- |
| dev | enabled | moment-dev-public-data-queue | moment-dev-public-data-dlq |
| prod | disabled | moment-prod-public-data-queue | moment-prod-public-data-dlq |

Prod SQS는 최종 데모 또는 리허설 시점에 명시적으로 활성화한다.

enable_dev_sqs  = true
enable_prod_sqs = false

## Dev / Prod 운영 정책 분리

SQS는 instance size가 있는 리소스는 아니지만, 메시지 보관 기간, visibility timeout, max receive count, DLQ retention은 운영 정책에 해당한다.

따라서 MoMent는 Dev와 Prod의 SQS / DLQ 정책 변수를 분리한다.

- Dev: 개발 / 검증 / 재실행 중심
- Prod: 운영 리허설 / 장애 추적 / 메시지 유실 방지 중심

| 항목 | Dev 기본값 | Prod 기본값 | 기준 |
| --- | --- | --- | --- |
| Visibility Timeout | 300초 | 900초 | Prod는 S3 Raw 읽기와 DB/OpenSearch 적재 Batch 처리 여유를 더 둠 |
| Main Queue Retention | 86400초, 1일 | 604800초, 7일 | Prod는 장애 분석과 재처리 여지를 더 길게 유지 |
| DLQ Retention | 345600초, 4일 | 1209600초, 14일 | DLQ는 실패 증거 보존을 위해 Main Queue보다 길게 유지 |
| Max Receive Count | 3 | 5 | Prod는 일시 장애 재시도 여지를 더 둠 |
| Receive Wait Time | 10초 | 20초 | Prod는 long polling 기준으로 빈 receive 응답을 줄임 |
| Delay Seconds | 0초 | 0초 | 즉시 처리 기준 유지 |
| Message Size | 262144 bytes | 262144 bytes | AWS SQS 최대 메시지 크기 기준 유지 |
| Server Side Encryption | SQS Managed SSE enabled | SQS Managed SSE enabled | 환경 공통 암호화 |

## Terraform 변수 기준

Dev environment는 Dev 전용 변수를 사용한다.

| 변수 | 설명 |
| --- | --- |
| dev_sqs_visibility_timeout_seconds | Dev SQS visibility timeout |
| dev_sqs_message_retention_seconds | Dev Main Queue retention |
| dev_sqs_dlq_message_retention_seconds | Dev DLQ retention |
| dev_sqs_max_receive_count | Dev DLQ 이동 전 최대 수신 횟수 |
| dev_sqs_receive_wait_time_seconds | Dev long polling wait time |
| dev_sqs_delay_seconds | Dev message delay |
| dev_sqs_max_message_size | Dev max message size |
| dev_sqs_managed_sse_enabled | Dev SQS managed SSE |

Prod environment는 Prod 전용 변수를 사용한다.

| 변수 | 설명 |
| --- | --- |
| prod_sqs_visibility_timeout_seconds | Prod SQS visibility timeout |
| prod_sqs_message_retention_seconds | Prod Main Queue retention |
| prod_sqs_dlq_message_retention_seconds | Prod DLQ retention |
| prod_sqs_max_receive_count | Prod DLQ 이동 전 최대 수신 횟수 |
| prod_sqs_receive_wait_time_seconds | Prod long polling wait time |
| prod_sqs_delay_seconds | Prod message delay |
| prod_sqs_max_message_size | Prod max message size |
| prod_sqs_managed_sse_enabled | Prod SQS managed SSE |

Queue 이름과 DLQ 이름은 환경별 고정 naming을 유지한다.

- Dev Main Queue: moment-dev-public-data-queue
- Dev DLQ: moment-dev-public-data-dlq
- Prod Main Queue: moment-prod-public-data-queue
- Prod DLQ: moment-prod-public-data-dlq

## DLQ Redrive 정책

Main Queue는 DLQ를 대상으로 redrive policy를 가진다.

Dev 기본 maxReceiveCount는 3이다.

Prod 기본 maxReceiveCount는 5이다.

즉, Batch Job이 메시지를 반복 처리하지 못하고 visibility timeout 이후 다시 수신되는 흐름이 환경별 maxReceiveCount만큼 누적되면 해당 메시지는 DLQ로 이동한다.

DLQ는 실패 메시지 격리와 장애 분석을 위한 증거 보존 계층이다.

Prod DLQ retention은 Main Queue retention보다 길게 잡아 실패 메시지를 운영 리허설과 장애 추적에 활용할 수 있도록 한다.

## IAM 연결

SQS Queue ARN은 IAM 모듈의 sqs_queue_arns 입력으로 전달한다.

| 대상 | 권한 |
| --- | --- |
| Batch Job Pod | ReceiveMessage, DeleteMessage, ChangeMessageVisibility, GetQueueAttributes |
| Lambda Collector | SendMessage, GetQueueAttributes |

DLQ는 실패 메시지 격리용으로 두며, 기본 Batch/Lambda 권한에는 Main Queue ARN만 연결한다.

## Backend 영향 범위

이번 SQS / DLQ 정책 분리는 Terraform 운영 정책 변수 분리 작업이다.

다음 항목은 변경하지 않는다.

- SQS 메시지 body schema
- Lambda Collector SQS payload
- Spring Batch Consumer 코드
- Queue URL output 구조
- Queue ARN output 구조
- Queue 이름
- DLQ 이름

따라서 백엔드 코드는 직접 변경하지 않는다.

단, visibility timeout, max receive count, message retention은 메시지 재처리 동작에 영향을 줄 수 있으므로 Spring Batch 처리 시간이 확정되면 후속 이슈에서 운영값을 조정할 수 있다.

## Destroy 주의사항

SQS Queue 삭제 전에는 Main Queue와 DLQ에 남아 있는 메시지를 확인해야 한다.

특히 DLQ에 메시지가 남아 있으면 수집 또는 배치 처리 실패 증거일 수 있으므로, 삭제 전 원인 확인 또는 캡처가 필요하다.
