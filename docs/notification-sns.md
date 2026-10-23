# Notification SNS

## 목적

MoMent Backend API가 notification 이벤트를 AWS SNS Topic으로 발행할 수 있도록 Dev-first 기준의 SNS 인프라와 Backend IAM 권한을 구성한다.

이번 구성은 모바일 단말 Push 수신 전체 구현이 아니라, Backend가 SNS Topic에 메시지를 publish할 수 있는 기반 인프라다.

## 구성 범위

- Dev notification SNS Topic
- Prod notification SNS Topic 선택 활성화 구조
- Backend API Pod IAM/IRSA Role의 sns:Publish 권한
- Dev/Prod SNS Topic ARN output
- Backend 런타임 환경변수 연결 기준

## 제외 범위

- FCM/APNS/Expo push token 수집
- SNS PlatformApplication 생성
- SNS PlatformEndpoint 생성
- 모바일 device token 저장
- 실제 모바일 단말 Push 수신

해당 범위는 별도 Push Token / PlatformEndpoint 후속 이슈에서 처리한다.

## Dev 설정

Dev 환경은 기본적으로 notification SNS Topic을 생성할 수 있도록 구성한다.

- enable_dev_notification_sns = true
- dev_notification_sns_topic_name = null
- dev_notification_sns_display_name = "MoMent Dev Notification"
- dev_notification_sns_kms_master_key_id = null

topic_name을 null로 두면 기본 이름은 다음 형식으로 생성된다.

- moment-dev-notification-topic

## Prod 설정

Prod 환경은 비용 및 운영 안전성을 위해 기본 비활성화한다.

- enable_prod_notification_sns = false
- prod_notification_sns_topic_name = null
- prod_notification_sns_display_name = "MoMent Prod Notification"
- prod_notification_sns_kms_master_key_id = null

Prod 활성화가 필요하면 승인 후 enable_prod_notification_sns=true로 변경하고 plan 결과를 확인한다.

## Backend 환경변수 연결 기준

Backend는 다음 환경변수로 SNS Topic publish를 활성화한다.

- NOTIFICATION_SNS_ENABLED=true
- NOTIFICATION_SNS_TOPIC_ARN=<terraform output dev_notification_sns_topic_arn 또는 prod_notification_sns_topic_arn>
- AWS_REGION=ap-northeast-3

로컬/CI에서는 NOTIFICATION_SNS_ENABLED=false 또는 Topic ARN 빈 값으로 두어도 Backend가 깨지지 않아야 한다.

## IAM / IRSA 권한

Backend API Pod Role에는 notification SNS Topic에 대한 최소 권한만 부여한다.

- Action: sns:Publish
- Resource: notification SNS Topic ARN

Batch Pod, Lambda Collector, AI Service 권한과 섞지 않는다.

## 암호화 기준

현재 모듈은 kms_master_key_id를 선택 입력으로 둔다.

- null: SNS 기본 설정 사용
- alias/aws/sns 또는 CMK ARN: 명시적 SNS server-side encryption 사용

KMS 암호화를 활성화할 경우 Backend publish 주체의 KMS 권한 영향까지 함께 검토한다.

## 검증 기준

- terraform fmt -recursive
- terraform validate
- Dev plan에서 notification SNS Topic 생성 확인
- Dev plan에서 Backend IAM Policy에 sns:Publish 추가 확인
- Prod 기본 plan에서 notification SNS Topic 미생성 확인
- 무관 리소스 destroy/replacement 없음 확인
- 민감정보가 코드, tfvars, output, 문서에 포함되지 않음 확인
