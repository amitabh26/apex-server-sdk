terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Remote state backend — secrets in tfstate (Container App ARM payload,
  # role assignments, etc.) are encrypted at rest in Azure Storage with
  # RBAC controlling who can read state. NEVER use local state for prod.
  #
  # Bootstrap the storage account once with bootstrap-state.ps1, then run
  # `terraform init`.
  backend "azurerm" {
    resource_group_name  = "engage-launchdarkly-prod"
    storage_account_name = "stldbridgetfstate" # must be globally unique; edit if taken
    container_name       = "tfstate"
    key                  = "ld-bridge.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
