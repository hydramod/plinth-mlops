# 0001 - KServe in RawDeployment mode, without Knative or Istio

- **Status:** accepted
- **Date:** 2026-08-31

## Context

KServe's default installation sits on Knative Serving, which sits on a service mesh
(Istio or Kourier). That is three control planes to run, upgrade and debug before the
first model is served.

Knative buys two things: scale-to-zero, and revision-based traffic splitting for
canary rollouts.

## Decision

Install KServe in `RawDeployment` mode. Each `InferenceService` becomes a plain
Deployment, Service and HPA. No Knative, no Istio.

Set per-service with the annotation, rather than as a cluster default, so a single
model can opt back in without reinstalling anything:

```yaml
annotations:
  serving.kserve.io/deploymentMode: RawDeployment
```

## Consequences

**What we lose.** Scale-to-zero, and KServe's built-in canary percentage field.

**Why that is affordable.** Scale-to-zero on a one-node cluster saves nothing - the
node is already running and already paid for. It starts mattering when there are many
models that are mostly idle, and the cost is a cold start on the first request, which
enterprise latency requirements tend not to forgive anyway.

Traffic splitting is the more interesting loss, and it is covered: Phase 1 introduces
**Argo Rollouts**, which does canary analysis against Prometheus and rolls back on a
failed SLO. That is a strictly better answer than a percentage field, because it
includes the decision to abort.

**What we gain.** One fewer control plane in the destroy-and-rebuild cycle, a shorter
bootstrap, and a cluster where `kubectl get deploy` explains what is running.

## Reverses when

Many models, mostly idle, where scale-to-zero is real money - or a request-driven
autoscaling requirement that HPA on CPU and concurrency cannot meet.
