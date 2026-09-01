# 0003 - What is deliberately not built

- **Status:** accepted, and revisited at the end of every phase
- **Date:** 2026-08-31

## Context

The failure mode of a platform at this stage is not missing capability. It is building
a general solution to a problem that has been seen once.

A list of things you decided not to build is only useful if each entry says what would
change your mind. Without that, "not yet" and "no" look identical six months later, and
the argument gets had again from the start.

## Decision

Not built, each with the trigger that reverses it.

| Not built | Reverses when |
|---|---|
| **Feature store** (Feast) | A second consumer reads the same features, or train/serve skew shows up in the drift metrics |
| **Multi-cluster or multi-region** | An availability SLO that a single AKS region demonstrably cannot meet |
| **Service mesh** | mTLS needed across more than roughly five services, or per-service authorisation |
| **Custom operator or CRDs** | The third time a CRD would beat a Helm values file |
| **Kubeflow Pipelines** | More than roughly five people authoring pipelines |
| **Streaming / lakehouse layer** | A freshness requirement the batch path cannot meet |
| **In-house experiment tracking** | Never. This is a solved problem and the solution is free |

Two more that are real decisions rather than omissions:

| Not built | Reverses when |
|---|---|
| **Cluster autoscaling on the system pool** | More than one workload competes for the node. The GPU pool in Phase 2 autoscales from zero, which is where it earns its keep |
| **A private API server in dev** | There is a bastion or a self-hosted runner inside the VNet. A private endpoint with no path to it means the apply succeeds and you cannot reach the cluster it built. Production is a different answer, and `private_cluster_enabled` is already a variable |

## Consequences

Every row is a thing this platform cannot currently do, and that is the correct amount
of platform for one engineer, three workloads and a cluster that is deliberately
destroyed between phases.

The list gets read at the end of each phase. A trigger that has fired is work; a
trigger that has not is a decision that is still holding.
