# ArgoCD App Degraded

## Summary

ArgoCD Application health is degraded.

## Primary owner

Follow the alert label owner.

## Immediate checks

1. Confirm affected environment and service.
2. Check current alert state.
3. Check recent deployment, Terraform, or GitOps changes.
4. Check service logs and Kubernetes events.

## Investigation

Run argocd app get, inspect degraded resources, sync errors, events, and reconcile GitOps source.

## Recovery

1. Fix the verified root cause.
2. Reconcile using GitOps or Terraform.
3. Confirm workload health and alert recovery.
4. Record evidence in the issue or incident note.

## Do not

- Do not create temporary Kubernetes secrets.
- Do not apply manual drift as the final fix.
- Do not silence the alert without root-cause evidence.
- Do not change thresholds only to hide a real issue.
