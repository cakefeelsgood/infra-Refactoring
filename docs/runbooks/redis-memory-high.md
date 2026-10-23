# RedisMemoryHigh

## Summary

Redis memory usage exceeded the configured threshold.

## Impact

Redis eviction, cache miss increase, distributed lock instability, or latency increase can occur.

## First checks

- Check Redis DatabaseMemoryUsagePercentage
- Check Evictions
- Check key count and TTL policy
- Check application cache behavior
- Check recent traffic or batch spike

## Recovery

- Reduce unnecessary keys
- Apply TTL where appropriate
- Review cache write path
- Scale Redis only after confirming memory trend
