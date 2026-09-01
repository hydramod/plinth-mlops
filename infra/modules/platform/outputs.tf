output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "aks_oidc_issuer_url" {
  description = "Needed by every Workload Identity federated credential from Phase 1 on."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "storage_account_name" {
  value = azurerm_storage_account.data.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "ci_client_id" {
  description = "Set as AZURE_CLIENT_ID in GitHub Actions. There is no matching secret - the trust is the federated credential."
  value       = try(azuread_application.ci[0].client_id, null)
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}
