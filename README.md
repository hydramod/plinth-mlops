# Plinth

The flat base a statue stands on. Models stand on it, it is not the interesting part,
and it must not move.

Plinth is an MLOps platform on Azure AKS: model serving, model CI/CD with automatic
rollback, drift and cost observability, and regression testing for output that is not
deterministic. It is built to make the twentieth model cheaper to ship than the first,
and Phase 4 measures whether it does rather than asserting it.

It is a real platform for imaginary customers. Nothing here is anybody's production.

## Where it is

| Phase | What lands | Status |
|---|---|---|
| **0** | Terraform baseline, GitOps loop, admission policy, one hello-world endpoint | in progress |
| 1 | Tabular model end to end: MLflow, Airflow, model CI, canary with auto-rollback, drift | not started |
| 2 | LLM endpoint on vLLM, GPU scheduling, quantisation and batching measured | not started |
| 3 | RAG, retrieval quality monitoring, and the evaluation harness | not started |
| 4 | The golden path, a second model through it, and the hardening pass | not started |

**Phase 0 is done when a commit to this repo reaches a live endpoint with nobody
touching the cluster by hand.**

## Shape

```
   this repo --OIDC--> Azure              Argo CD <-- gitops/ (app-of-apps)
   +-------------------------------------------------------------------------+
   |  Terraform  envs/dev  ->  VNet - AKS - ACR - ADLS Gen2 -                 |
   |                           Key Vault - Log Analytics - Workload Identity  |
   +-------------------------------------------------------------------------+
        AKS --+- platform:  Argo CD - Kyverno - cert-manager
              +- serving:   KServe (RawDeployment)
```

The bootstrap is deliberately thin: `terraform apply`, install Argo CD, apply one root
Application. Everything else in the cluster is Argo CD pulling `gitops/` from this
repo. That is what makes destroy-and-rebuild a real test instead of a second imperative
install path.

```
infra/bootstrap/        remote state backend. Local state, run once, then forget.
infra/modules/platform/ everything Azure
infra/envs/dev/         the one environment that exists today
gitops/bootstrap/       the only manifest applied by hand
gitops/platform/        Argo CD Applications, ordered by sync wave
gitops/policies/        Kyverno ClusterPolicies
gitops/models/          InferenceServices
docs/adr/               why things are the way they are
docs/runbook-phase-0.md standing it up from nothing
```

## Running it

You need `terraform`, `az` and `kubectl`. The full walkthrough, from an empty
subscription to a live endpoint, is in
[docs/runbook-phase-0.md](docs/runbook-phase-0.md) - nine steps, every one a command you
can paste.

The shape of it:

```bash
terraform -chdir=infra/bootstrap apply     # once per subscription: the state backend
terraform -chdir=infra/envs/dev apply      # the environment
az aks get-credentials ...                 # kubeconfig
kubectl apply -n argocd -f <argo-cd install manifest, pinned>
kubectl apply -f gitops/bootstrap/root-app.yaml
```

That last line is the only manifest applied by hand, ever. From there Argo CD pulls
`gitops/` and converges the cluster on its own.

```bash
terraform -chdir=infra/envs/dev destroy    # this environment is meant to be destroyed
```

Destroying it between phases is both the cost strategy and the proof that the
infrastructure code is real: everything comes back from git in about twenty minutes.

## Decisions

The interesting ones are in [docs/adr/](docs/adr/):

- [KServe in RawDeployment mode, without Knative or Istio](docs/adr/0001-kserve-rawdeployment-no-knative.md) -
  dropping an entire control plane, and what it costs
- [Kyverno for admission control, enforce narrowly before broadly](docs/adr/0002-kyverno-over-azure-policy.md) -
  an Enforce policy with fifteen exclusions is not a policy, it is a list
- [What is deliberately not built](docs/adr/0003-what-is-not-built.md)

## What is deliberately not built

The hardest part of a platform at this stage is not building the parts you skip. Each
of these is a decision with the condition that would reverse it, recorded in
[ADR 0003](docs/adr/0003-what-is-not-built.md):

no feature store, no service mesh, no multi-cluster, no Kubeflow, no custom operator,
no streaming layer, and no in-house experiment tracking.
