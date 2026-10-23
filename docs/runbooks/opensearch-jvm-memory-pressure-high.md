# OpenSearchJVMMemoryPressureHigh

## Summary

OpenSearch JVM memory pressure exceeded the configured threshold.

## Impact

Search latency, GC pressure, and cluster instability can occur.

## First checks

- Check JVMMemoryPressure
- Check cluster red/yellow status
- Check shard count
- Check query volume
- Check indexing volume

## Recovery

- Reduce heavy queries
- Review shard count and index size
- Scale or tune OpenSearch only after confirming heap pressure trend
