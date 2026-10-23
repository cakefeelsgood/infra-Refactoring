# MoMent Grafana Dashboards

This directory stores Grafana dashboards as Kubernetes ConfigMaps.

## Delivery model

Grafana dashboards are managed through GitOps:

1. ArgoCD applies environment-specific dashboard ConfigMaps from this directory.
2. kube-prometheus-stack Grafana sidecar discovers dashboard ConfigMaps.
3. Grafana loads JSON dashboards from ConfigMap data.

## Environment split

MoMent currently uses separate monitoring stacks:

- Dev ArgoCD -> Dev monitoring stack -> Dev Grafana
- Prod ArgoCD -> Prod monitoring stack -> Prod Grafana

Therefore dashboards are split by environment:

- monitoring/dashboards/dev
- monitoring/dashboards/prod

Each dashboard keeps the same panel/query structure, but the default environment variable is fixed to the target environment.

## Discovery contract

The kube-prometheus-stack Grafana sidecar discovers ConfigMaps with:

- namespace: monitoring
- label: grafana_dashboard="1"

## Dashboard list

- dev/application-business-overview.yaml
  - MoMent Dev Application / Business Overview
- prod/application-business-overview.yaml
  - MoMent Prod Application / Business Overview

## Source of truth

Manual Grafana UI imports are allowed only for temporary validation.

The final dashboard source of truth is this GitOps directory.
