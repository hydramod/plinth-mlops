# 0002 - Kyverno for admission control, and enforce narrowly before broadly

- **Status:** accepted
- **Date:** 2026-08-31

## Context

AKS ships `azure_policy_enabled`, which installs Gatekeeper and a set of Azure-managed
constraints. The alternative is running an admission controller ourselves.

There is a second question underneath the first, and it is the one that actually
decides whether a policy layer survives: what do you do on day one, when every policy
you would like to enforce is violated by the platform charts you just installed?

## Decision

**Kyverno, installed by Argo CD from its own Helm chart. Azure Policy stays off.**

**And policies land in two tiers:**

- **Enforce**, scoped to the namespaces holding our own workloads (`models`, `mlops`).
  Today that is one policy: no `:latest`, and no untagged images.
- **Audit**, cluster-wide. Today: non-root, and resource requests and limits.

Each Audit policy is promoted to Enforce when the workloads it covers are actually
clean, not before.

## Consequences

Kyverno policies are YAML that reads like the resource they match, which matters more
than it sounds when the policy is the thing standing between a deploy and production.
Azure Policy would have given us compliance *reporting* against Azure's own initiative
definitions, which is worth having the day somebody asks for an attestation, and worth
nothing before that.

The two-tier split is the load-bearing half of this decision. A cluster-wide Enforce on
day one blocks cert-manager, Kyverno and the KServe controller, and the afternoon goes
on writing exclusions. **An Enforce policy with fifteen exclusions is not a policy, it
is a list.** Audit makes the violations visible in `kubectl get polr -A` immediately,
which is most of the value, and the promotion is then a one-line change with evidence
behind it.

## Reverses when

Someone needs a compliance attestation rather than enforcement - at which point Azure
Policy runs *alongside* Kyverno rather than instead of it, because they answer
different questions.
