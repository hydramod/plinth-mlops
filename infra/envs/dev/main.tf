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

provider "azurerm" {
  features {
    key_vault {
      # This environment is disposable. Leaving deleted vaults in soft-delete blocks
      # the next apply from reusing the name, which is exactly the wrong failure mode
      # for a stack that is destroyed and rebuilt every few weeks.
      purge_soft_delete_on_destroy = true
    }
  }
  subscription_id = var.subscription_id
}

provider "azuread" {}

variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "uaenorth"
}

variable "api_authorized_ip_ranges" {
  description = "Your own public IP as a /32. Find it with: curl -s https://ifconfig.me"
  type        = list(string)
}

variable "acr_name" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "key_vault_name" {
  type = string
}

variable "github_repo" {
  type    = string
  default = "hydramod/plinth-mlops"
}

module "platform" {
  source = "../../modules/platform"

  prefix   = "plinth"
  env      = "dev"
  location = var.location

  api_authorized_ip_ranges = var.api_authorized_ip_ranges
  private_cluster_enabled  = false

  acr_name             = var.acr_name
  storage_account_name = var.storage_account_name
  key_vault_name       = var.key_vault_name
  github_repo          = var.github_repo

  tags = {
    owner = "hydramod"
  }
}
