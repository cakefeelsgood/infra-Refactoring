# RDSConnectionHigh

## Summary

RDS DatabaseConnections exceeded the configured threshold.

## Impact

Backend API can fail or become slow if the database connection pool or RDS connection limit is exhausted.

## First checks

- Check RDS DatabaseConnections
- Check backend connection pool settings
- Check active sessions
- Check slow queries
- Check recent deployment or traffic spike

## Recovery

- Scale backend carefully if DB can handle more connections
- Reduce connection pool if it is too aggressive
- Investigate leaked connections
- Kill abnormal sessions only after confirming impact
