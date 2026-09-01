# Runbook - Phase 0, from nothing to a live endpoint

**Done when:** a commit to this repo reaches a live model endpoint with nobody touching
the cluster by hand.

Everything below runs from Git Bash on Windows, or any POSIX shell, from the repo root.

---

## 0. Tooling

None of this is installed by default on a Windows box:

```bash
winget install --id Hashicorp.Terraform -e
winget install --id Microsoft.AzureCLI -e
winget install --id Kubernetes.kubectl -e
```

```bash
terraform version && az version && kubectl version --client
```

---

## 1. Azure login

```bash
az login
```

```bash
az account set --subscription "<subscription-id>" && az account show --query "{name:name, id:id, tenant:tenantId}" -o table
```

Register the providers this needs, once per subscription. They are usually already
registered; this is idempotent and cheap:

```bash
for p in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.Storage Microsoft.OperationalInsights; do az provider register --namespace "$p"; done
```

---

## 2. State backend, once per subscription

`infra/bootstrap` keeps **local** state on purpose - something has to exist before there
is somewhere to put state. Its own state file holds nothing that matters and is
gitignored.

```bash
terraform -chdir=infra/bootstrap init
```

```bash
terraform -chdir=infra/bootstrap apply -var subscription_id="<subscription-id>" -var state_storage_account_name="<globally-unique-name>"
```

Take `state_storage_account_name` from the output and put it in
`infra/envs/dev/backend.tf`, in the line that is currently commented out.

---

## 3. The environment

```bash
cp infra/envs/dev/terraform.tfvars.example infra/envs/dev/terraform.tfvars
```

Fill in `infra/envs/dev/terraform.tfvars`. Three of the names are globally unique across
all of Azure, so put your own suffix on them. `api_authorized_ip_ranges` is your own IP:

```bash
echo "$(curl -s https://ifconfig.me)/32"
```

Then plan, and read it properly the first time:

```bash
terraform -chdir=infra/envs/dev init -input=false && terraform -chdir=infra/envs/dev plan -input=false
```

```bash
terraform -chdir=infra/envs/dev apply -input=false
```

Expect 10-15 minutes, most of it AKS.

---

## 4. Hand the cluster to Argo CD

Fetch credentials:

```bash
az aks get-credentials --resource-group "$(terraform -chdir=infra/envs/dev output -raw resource_group_name)" --name "$(terraform -chdir=infra/envs/dev output -raw aks_name)" --overwrite-existing
```

Install Argo CD at a pinned version:

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
```

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.2/manifests/install.yaml
```

```bash
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=10m
```

Then apply the one manifest that is applied by hand, ever:

```bash
kubectl apply -f gitops/bootstrap/root-app.yaml
```

**That is the last time anything touches this cluster imperatively.** Argo CD pulls
everything else from `gitops/`.

---

## 5. Watch it converge

```bash
kubectl -n argocd get applications -w
```

They come up in wave order: cert-manager and kyverno first, then the KServe CRDs and
the Kyverno policies, then the KServe controller, then the model. All six should reach
`Synced / Healthy`.

The Argo CD UI, if you want it - password first, then a port-forward:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:443
```

`https://localhost:8081`, user `admin`.

---

## 6. Prove it

```bash
kubectl -n argocd get applications && kubectl -n models get inferenceservice
```

Port-forward the model and call it:

```bash
kubectl -n models port-forward svc/hello-sklearn-predictor 8080:80
```

In a second shell:

```bash
curl -s -H "Content-Type: application/json" -d '{"instances": [[6.8, 2.8, 4.8, 1.4]]}' http://127.0.0.1:8080/v1/models/hello-sklearn:predict
```

That returns a prediction from a model nobody deployed by hand.

**Then prove the loop rather than the endpoint** - that is the actual acceptance test.
Change `minReplicas` to `2` in `gitops/models/hello-sklearn.yaml`, commit, push, and
watch:

```bash
kubectl -n models get pods -w
```

A second pod appears with no `kubectl apply` anywhere. **That is Phase 0 done.**

---

## 7. Prove the policy

The `disallow-latest-tag` policy is `Enforce` in the `models` namespace. It should
refuse this outright:

```bash
kubectl -n models run latest-test --image=nginx:latest
```

And the Audit policies should already have findings:

```bash
kubectl get polr -A
```

---

## 8. Tear it down

```bash
terraform -chdir=infra/envs/dev destroy -input=false
```

This environment is meant to be destroyed between phases - it is the cost strategy and
the proof that the IaC is real. `infra/bootstrap` stays; only `envs/dev` goes.

If you are pausing for days rather than weeks and would rather keep the state:

```bash
az aks stop --resource-group plinth-dev-rg --name plinth-dev-aks
```

That stops the node VMs, which is nearly all of the running cost.

---

## Known first-run friction

- **`apply` fails on a name collision.** ACR, the storage account and Key Vault names
  are globally unique across Azure. Add a suffix and re-run.
- **`kubectl` times out.** Your public IP changed. Update `api_authorized_ip_ranges` in
  `terraform.tfvars` and apply again.
- **The `models` Application stays Progressing.** The hello model pulls from a public
  Google bucket; check the predictor pod's `storage-initializer` init container first.
- **Key Vault name is "already in use" after a destroy.** Soft delete. The provider is
  configured to purge on destroy, but a failed destroy can leave one behind:
  `az keyvault purge --name <name>`.
