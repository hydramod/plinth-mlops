variable "prefix" {
  description = "Name prefix for all resources in this environment."
  type        = string
}

variable "env" {
  description = "Environment name. Part of every resource name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "kubernetes_version" {
  description = "AKS version. null takes the region's default, which is what you want unless you are pinning for a reason - a hardcoded version that a region has retired fails the apply, and this cluster is rebuilt often."
  type        = string
  default     = null
}

variable "system_node_size" {
  description = "VM size for the system node pool. Azure does not allow Spot on a system pool, so this one is regular priority - the Spot pools arrive in Phase 2 for GPU. Burstable on purpose: Argo CD, Kyverno, cert-manager and the KServe controller are idle almost all of the time, which is exactly what the B-series is for. Swap to Standard_D4s_v5 if credit throttling ever shows up in the latency numbers."
  type        = string
  default     = "Standard_B4ms"
}

variable "system_node_count" {
  description = "Nodes in the system pool. One is enough for a single-tenant dev cluster."
  type        = number
  default     = 1
}

variable "api_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server. Empty list means open to the internet, which dev should never be. Put your own /32 here."
  type        = list(string)
  default     = []
}

variable "private_cluster_enabled" {
  description = "Fully private API server. false in dev on purpose - see docs/adr/0003. A private endpoint with no bastion means the apply succeeds and you cannot reach the cluster it built."
  type        = bool
  default     = false
}

variable "acr_name" {
  description = "Globally unique container registry name. 5-50 alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.acr_name))
    error_message = "ACR names are 5-50 alphanumeric characters, no hyphens."
  }
}

variable "storage_account_name" {
  description = "Globally unique ADLS Gen2 account name for datasets and MLflow artifacts. 3-24 lowercase alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account names are 3-24 characters, lowercase letters and digits only."
  }
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name. 3-24 characters, alphanumeric and hyphens."
  type        = string
}

variable "github_repo" {
  description = "owner/repo that GitHub Actions federates from. Empty disables the federated credential entirely."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Log Analytics retention. 30 is the free floor; longer costs money and this cluster is disposable."
  type        = number
  default     = 30
}
