# M4-CW-01 CloudWatch Metrics / Alarm 최소 연동 구성

## 개요
AWS Managed Resource 중심 관측성 구성.
Prometheus/Grafana가 EKS Workload 중심이라면 CloudWatch는 ALB, RDS, Redis, OpenSearch, Lambda 등 AWS 관리형 리소스 중심.

## 관측 대상 및 확인 결과

| 리소스 | Namespace | 주요 메트릭 | 확인 |
|--------|-----------|------------|------|
| ALB | AWS/ApplicationELB | RequestCount, TargetResponseTime, HTTPCode_Target_4XX/5XX, HealthyHostCount, UnHealthyHostCount | ✅ (트래픽 없어 Datapoints 없음) |
| NAT Gateway | AWS/NATGateway | BytesOutToDestination, PacketsDropCount | ✅ |
| RDS | AWS/RDS | CPUUtilization, DatabaseConnections, FreeStorageSpace | ✅ |
| Redis | AWS/ElastiCache | CPUUtilization, CurrConnections, Evictions | ✅ |
| OpenSearch | AWS/ES | ClusterStatus, CPUUtilization, JVMMemoryPressure | ✅ |
| Lambda | AWS/Lambda | Errors, Duration, Throttles | ✅ |

## Target Group Health
- Prod EKS 비활성 상태로 현재 활성 Target Group 없음
- 확인 방법:
  1. Prod EKS 활성화
  2. ALB Controller 설치
  3. Ingress 배포 후 아래 명령어로 확인
```bash
aws elbv2 describe-target-health \
  --region ap-northeast-3 \
  --target-group-arn <TARGET_GROUP_ARN>
```
- CloudWatch 콘솔에서 ALB > Target Group > Health 탭으로도 확인 가능

## CloudWatch Alarm

### 생성된 Alarm
| Alarm 이름 | 리소스 | 메트릭 | 임계값 | SNS |
|-----------|--------|--------|--------|-----|
| moment-dev-rds-cpu-high | moment-dev-postgres | CPUUtilization | > 80% (5분 평균, 2회 연속) | moment-dev-notification-topic |

### Alarm 후보 (미생성)
| Alarm | 리소스 | 메트릭 | 권장 임계값 |
|-------|--------|--------|------------|
| moment-dev-alb-5xx-high | Dev ALB | HTTPCode_Target_5XX_Count | > 10 (5분) |
| moment-dev-alb-unhealthy | Dev ALB | UnHealthyHostCount | > 0 |
| moment-dev-lambda-errors | moment-dev-public-data-collector | Errors | > 0 |

## SNS 연동
- SNS Topic: arn:aws:sns:ap-northeast-3:611058323802:moment-dev-notification-topic
- CloudWatch Alarm → SNS 연동 완료 (moment-dev-rds-cpu-high)
- Slack Lambda 연동은 M4-ALERT-01 또는 M5 고도화 항목으로 분리

## CloudWatch Logs 기준
- 장기 저장 미구성
- 필요한 경우 짧은 retention (7일 이하) 기준으로만 사용

## Prod 환경
- Prod EKS 비활성 상태로 Alarm 생성 보류
- 활성화 시 동일 기준으로 Alarm 생성 필요
