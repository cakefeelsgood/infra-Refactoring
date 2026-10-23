# ALBHealthyHostZero

## Summary

ALB Target Group has zero healthy hosts.

## Impact

External API traffic can fail.

## First checks

- Check Ingress status
- Check TargetGroupBinding
- Check Service endpoints
- Check backend-api pod readiness
- Check AWS Load Balancer Controller events
- Check /health endpoint

## Recovery

- Restore backend-api pods
- Fix Service selector or endpoint mismatch
- Fix readiness probe or health check path
- Check ALB controller and subnet/security group issues
