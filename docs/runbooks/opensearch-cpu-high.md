# OpenSearchCPUHigh

## Summary

OpenSearch CPU utilization exceeded the configured threshold.

## Impact

Search latency, indexing throughput, and recommendation/search features can degrade.

## First checks

- Check OpenSearch CPUUtilization
- Check search request rate
- Check indexing load
- Check slow queries
- Check shard and cluster health

## Recovery

- Reduce heavy queries
- Review index/shard layout
- Scale domain only after checking query and indexing pressure
