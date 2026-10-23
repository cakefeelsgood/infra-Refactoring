# ai-service-target-down

## Summary

This runbook describes the first response steps for the ai-service-target-down alert.

## First checks

1. Confirm alert environment, service, severity, and owner.
2. Check the related Grafana Application / Business dashboard.
3. Check Prometheus rule source metric and alert state.
4. Check recent GitOps sync, deployment, or image tag changes.
5. Check affected pods, events, logs, and dependencies.

## Recovery notes

- Do not apply manual temporary fixes without recording root cause.
- Prefer GitOps or Terraform source-of-truth changes.
- Do not perform destructive Prod validation for alert testing.
- Record impact, start time, recovery time, and final action.
