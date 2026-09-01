output "resource_group_name" {
  value = module.platform.resource_group_name
}

output "aks_name" {
  value = module.platform.aks_name
}

output "aks_oidc_issuer_url" {
  value = module.platform.aks_oidc_issuer_url
}

output "acr_login_server" {
  value = module.platform.acr_login_server
}

output "storage_account_name" {
  value = module.platform.storage_account_name
}

output "key_vault_uri" {
  value = module.platform.key_vault_uri
}

output "ci_client_id" {
  value = module.platform.ci_client_id
}

output "tenant_id" {
  value = module.platform.tenant_id
}
