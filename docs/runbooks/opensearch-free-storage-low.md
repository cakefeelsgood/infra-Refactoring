# OpenSearchFreeStorageLow

## Summary

OpenSearch free storage is below the configured threshold.

## Impact

Indexing can fail and cluster health can degrade.

## First checks

- Check FreeStorageSpace
- Check index sizes
- Check shard allocation
- Check old indices
- Check data retention policy

## Recovery

- Delete or archive unnecessary indices only after confirming retention policy
- Increase EBS volume size if required
- Reindex from RDS/S3 raw if recovery is needed
