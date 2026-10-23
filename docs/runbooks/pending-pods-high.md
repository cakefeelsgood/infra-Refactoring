# PendingPodsHigh

## Summary

One or more pods stayed Pending.

## Impact

Deployments or scaling events may not complete.

## First checks

- kubectl get pods -n target namespace
- kubectl describe pod
- Check scheduling events
- Check node capacity
- Check taints/tolerations
- Check resource requests
- Check image pull issues

## Recovery

- Fix scheduling constraints
- Add capacity if required
- Fix node labels, taints, tolerations, or resource requests
