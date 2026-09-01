# Creates the remote state backend, and nothing else.
#
# This is the only Terraform in the repo that keeps LOCAL state, on purpose: something
# has to exist before there is a place to put state. Run it once per subscription and
# then forget it. Its state file is gitignored and does not matter - every resource here
# is trivially reproducible and holds no data.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # ponytail: 4.x, not 5.x. The 5.0 major landed days ago (2026-08-27) and a
      # portfolio repo should not open on a four-day-old provider major.
      # Upgrade when 5.x has had a few point releases.
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  description = "Azure subscription to create the state backend in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uaenorth"
}

variable "prefix" {
  description = "Name prefix for all Plinth resources."
  type        = string
  default     = "plinth"
}

variable "state_storage_account_name" {
  description = "Globally unique storage account name for Terraform state. 3-24 lowercase alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "Storage account names are 3-24 characters, lowercase letters and digits only."
  }
}

resource "azurerm_resource_group" "tfstate" {
  name     = "${var.prefix}-tfstate-rg"
  location = var.location
}

resource "azurerm_storage_account" "tfstate" {
  name                     = var.state_storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  # No shared keys. State is read and written with Entra credentials, which is why
  # every backend block in this repo sets use_azuread_auth = true.
  shared_access_key_enabled = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

output "backend_config" {
  description = "Paste these into infra/envs/<env>/backend.tf."
  value = {
    resource_group_name  = azurerm_resource_group.tfstate.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
  }
}
