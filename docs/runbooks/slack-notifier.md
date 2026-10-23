# slack-notifier

## Summary

This runbook describes the first response steps for the slack-notifier alert.

## First checks

1. Confirm alert environment and service.
2. Check recent deployments, Terraform changes, and GitOps sync status.
3. Check the related CloudWatch metric and Grafana dashboard.
4. Check the affected AWS resource or workload health.
5. Record impact, start time, recovery time, and action taken.

## Recovery notes

- Do not apply manual temporary fixes without recording root cause.
- Prefer Terraform or GitOps source-of-truth changes.
- Escalate to the listed owner if customer impact is confirmed.
