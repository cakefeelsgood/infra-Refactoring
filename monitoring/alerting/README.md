# MoMent Alerting Taxonomy

## Alert routes

- EKS/Application: PrometheusRule -> AlertmanagerConfig -> Slack
- AWS Managed Resource: CloudWatch Alarm -> SNS -> Lambda Slack Notifier -> Slack

## Severity

| Severity | Meaning | Response |
| --- | --- | --- |
| critical | Immediate service outage or customer impact | Start incident response immediately |
| high | High risk of outage or partial service impact | Check within 10-15 minutes |
| medium | Degradation or early warning | Check during operating hours |
| info | Deployment, recovery, or test notification | Record only |

## Standard Slack fields

- 알람명
- 설명
- 심각도
- 환경
- 서비스
- 영역
- 사유
- 현재값
- 기준값
- 담당자
- 조치
- Runbook

## Rules

- Do not store Slack webhook URLs in Git.
- Do not create fake alerts for metrics that are not actually scraped.
- Do not use manual Grafana UI-only configuration as the source of truth.
- CloudWatch alarms and Prometheus alerts must use the same severity and owner taxonomy.

## Full Alert Catalog Extension

### Added CloudWatch alarms

| Alarm | Severity | Service | Category | Owner | Runbook |
| --- | --- | --- | --- | --- | --- |
| RDSConnectionHigh | High | rds-postgres | database | Backend/Data | docs/runbooks/rds-connection-high.md |
| RedisMemoryHigh | High | redis | cache | Backend/Infra | docs/runbooks/redis-memory-high.md |
| LambdaThrottleDetected | Medium | lambda | data-pipeline | Data/Infra | docs/runbooks/lambda-throttles-detected.md |
| SqsOldMessageHigh | High | sqs | data-pipeline | Data/Infra | docs/runbooks/sqs-old-message-high.md |
| OpenSearchCPUHigh | High | opensearch | search | Search/Infra | docs/runbooks/opensearch-cpu-high.md |
| OpenSearchJVMMemoryPressureHigh | High | opensearch | search | Search/Infra | docs/runbooks/opensearch-jvm-memory-pressure-high.md |
| OpenSearchFreeStorageLow | High | opensearch | search | Search/Infra | docs/runbooks/opensearch-free-storage-low.md |
| ALBHealthyHostZero | Critical | alb-target-group | edge | Infra | docs/runbooks/alb-healthy-host-zero.md |

### Added Prometheus alerts

| Alarm | Severity | Service | Category | Owner | Runbook |
| --- | --- | --- | --- | --- | --- |
| MomentBackendHpaMaxedOut | Medium | backend-api | capacity | Infra | docs/runbooks/hpa-maxed-out.md |
| MomentBatchWorkerUnavailable | High | batch-job | data-pipeline | Data/Infra | docs/runbooks/batch-worker-unavailable.md |
| MomentNodeNotReady | High | kubernetes | infrastructure | Infra | docs/runbooks/node-not-ready.md |
| MomentPendingPodsHigh | Medium | kubernetes | scheduling | Infra | docs/runbooks/pending-pods-high.md |

### Deferred event-based alerts

RDS failover and Redis failover are event-based alarms and must be implemented through verified EventBridge event patterns before routing to SNS/Lambda/Slack. They must not be faked with metric alarms.
