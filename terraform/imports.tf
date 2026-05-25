###############################################################################
# Import blocks — adopt existing Azure resources into Terraform state.
#
# These run on `terraform plan`/`apply`. After the first successful apply has
# brought all resources under management, you can delete this file (or leave
# it — import of an already-managed resource is a no-op).
#
# IMPORTANT: run `terraform plan` first and review the diff. If Terraform wants
# to change attributes on a resource, adjust main.tf to match the live state
# (location, SKU, tags, etc.) before applying — otherwise apply will mutate
# the existing resource.
###############################################################################

locals {
  subscription_id = data.azurerm_client_config.current.subscription_id

  rg_id = "/subscriptions/${local.subscription_id}/resourceGroups/${var.resource_group_name}"
}

import {
  to = azurerm_resource_group.this
  id = local.rg_id
}

import {
  to = azurerm_log_analytics_workspace.this
  id = "${local.rg_id}/providers/Microsoft.OperationalInsights/workspaces/${var.log_analytics_workspace_name}"
}

import {
  to = azurerm_container_registry.this
  id = "${local.rg_id}/providers/Microsoft.ContainerRegistry/registries/${var.container_registry_name}"
}

import {
  to = azurerm_user_assigned_identity.app
  id = "${local.rg_id}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${var.managed_identity_name}"
}

import {
  to = azurerm_key_vault.this
  id = "${local.rg_id}/providers/Microsoft.KeyVault/vaults/${var.key_vault_name}"
}

import {
  to = azurerm_container_app_environment.this
  id = "${local.rg_id}/providers/Microsoft.App/managedEnvironments/${var.container_app_environment_name}"
}

import {
  to = azurerm_container_app.bridge
  id = "${local.rg_id}/providers/Microsoft.App/containerApps/${var.container_app_name}"
}
