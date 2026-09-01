terraform {
  backend "azurerm" {
    # Created once by infra/bootstrap. Fill storage_account_name in from its
    # backend_config output, or pass it with -backend-config on init.
    resource_group_name = "plinth-tfstate-rg"
    container_name      = "tfstate"
    key                 = "dev.tfstate"

    # No shared keys on that account, so state is read and written with the Entra
    # identity you are already logged in as.
    use_azuread_auth = true

    # storage_account_name = "..."   # <- set this, it is globally unique
  }
}
