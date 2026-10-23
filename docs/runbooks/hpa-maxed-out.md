# HpaMaxedOut

## Summary

Backend API HPA reached max replicas.

## Impact

If traffic continues to increase, latency and errors can rise because autoscaling is capped.

## First checks

- Check HPA current, desired, max replicas
- Check backend CPU and memory
- Check request rate and latency
- Check node capacity
- Check pending pods

## Recovery

- Confirm whether maxReplicas should be increased
- Check node capacity before increasing maxReplicas
- Investigate inefficient endpoints or dependency latency
