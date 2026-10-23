# LambdaThrottleDetected

## Summary

Lambda throttling was detected.

## Impact

Public data collection can be delayed or retried.

## First checks

- Check Lambda Throttles
- Check Lambda concurrent executions
- Check EventBridge Scheduler frequency
- Check Lambda timeout and duration
- Check downstream S3/SQS/API latency

## Recovery

- Reduce invocation rate if scheduler is too aggressive
- Increase concurrency limit only when justified
- Fix long-running collector execution
