terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  name = "${var.prefix}-${var.env}"

  tags = merge(var.tags, {
    project = "plinth"
    env     = var.env
    managed = "terraform"
  })
}

# ---------------------------------------------------------------------------
# Foundation
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${local.name}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${local.name}-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = ["10.60.0.0/16"]
  tags                = local.tags
}

# Overlay CNI hands pod IPs out of its own space, so this subnet only has to be big
# enough for nodes. /22 leaves room for the GPU pool that arrives in Phase 2.
resource "azurerm_subnet" "aks" {
  name                 = "aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.60.0.0/22"]
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${local.name}-aks"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  dns_prefix          = local.name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "${local.name}-aks-nodes"

  # Free tier: no uptime SLA on the control plane. Correct for a cluster that is
  # deliberately destroyed between phases.
  sku_tier = "Free"

  private_cluster_enabled = var.private_cluster_enabled

  # Workload Identity, so nothing in this cluster ever holds a secret to reach Azure.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  role_based_access_control_enabled = true

  # Azure Policy stays off. Kyverno does admission control here - see docs/adr/0002.
  azure_policy_enabled = false

  default_node_pool {
    name            = "system"
    vm_size         = var.system_node_size
    node_count      = var.system_node_count
    os_disk_size_gb = 64
    vnet_subnet_id  = azurerm_subnet.aks.id
    # Required so the pool can be replaced in place when vm_size changes.
    temporary_name_for_rotation = "systmp"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  api_server_access_profile {
    authorized_ip_ranges = var.api_authorized_ip_ranges
  }

  tags = local.tags

  lifecycle {
    # AKS patches the node image out from under Terraform. Fighting it produces a
    # diff on every plan and no benefit.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# Control-plane audit logs. kube-audit-admin only: full kube-audit is the same data
# plus every read, and it is the line item that makes Log Analytics expensive.
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "audit"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------
# Registry, data, secrets
# ---------------------------------------------------------------------------

resource "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = azurerm_container_registry.this.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# ADLS Gen2: datasets now, MLflow artifacts from Phase 1.
resource "azurerm_storage_account" "data" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  tags = local.tags
}

resource "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # RBAC, not access policies. Access policies are a second authorisation system to
  # keep in your head for no gain.
  rbac_authorization_enabled = true

  purge_protection_enabled   = false # this environment is destroyed on purpose
  soft_delete_retention_days = 7

  tags = local.tags
}

# ---------------------------------------------------------------------------
# GitHub Actions -> Azure, by OIDC federation. No client secret exists.
# ---------------------------------------------------------------------------

resource "azuread_application" "ci" {
  count        = var.github_repo == "" ? 0 : 1
  display_name = "${local.name}-ci"
}

resource "azuread_service_principal" "ci" {
  count     = var.github_repo == "" ? 0 : 1
  client_id = azuread_application.ci[0].client_id
}

resource "azuread_application_federated_identity_credential" "ci_branch" {
  count          = var.github_repo == "" ? 0 : 1
  application_id = azuread_application.ci[0].id
  display_name   = "github-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "ci_pr" {
  count          = var.github_repo == "" ? 0 : 1
  application_id = azuread_application.ci[0].id
  display_name   = "github-pull-request"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
}

# Scoped to this resource group, not the subscription.
resource "azurerm_role_assignment" "ci_contributor" {
  count                = var.github_repo == "" ? 0 : 1
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.ci[0].object_id
}

resource "azurerm_role_assignment" "ci_acr_push" {
  count                = var.github_repo == "" ? 0 : 1
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.ci[0].object_id
}
