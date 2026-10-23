# SqsOldMessageHigh

## Summary

SQS ApproximateAgeOfOldestMessage exceeded the configured threshold.

## Impact

Batch processing is delayed and public data freshness can degrade.

## First checks

- Check batch-job pod availability
- Check SQS visible message count
- Check DLQ visible message count
- Check worker logs
- Check RDS/OpenSearch dependency status

## Recovery

- Restore batch worker
- Reprocess failed messages after fixing root cause
- Check DLQ redrive only after message schema and downstream errors are understood
