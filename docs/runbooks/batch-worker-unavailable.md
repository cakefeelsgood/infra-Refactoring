# BatchWorkerUnavailable

## Summary

Batch worker has no available replica.

## Impact

SQS public data processing can stop and queue backlog can increase.

## First checks

- Check batch-job Deployment
- Check pods and events
- Check image pull status
- Check ExternalSecret status
- Check RDS/OpenSearch/SQS connectivity
- Check SQS backlog and DLQ

## Recovery

- Restore batch-job rollout
- Fix Secret/config/dependency issue
- Reprocess queue only after root cause is fixed
