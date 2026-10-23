# NodeNotReady

## Summary

A Kubernetes node is not Ready.

## Impact

Pods can be evicted, unavailable, or stuck Pending.

## First checks

- kubectl get nodes
- kubectl describe node
- kubectl get events
- Check EC2 instance state
- Check node group health
- Check CNI and kubelet symptoms

## Recovery

- Drain/replace node only after checking workload impact
- Restore node group health
- Confirm pods reschedule successfully
