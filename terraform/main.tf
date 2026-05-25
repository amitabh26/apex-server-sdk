locals {
  using_jwt_auth = var.auth_mode == "jwt"

  acr_login_server = "${var.container_registry_name}.azurecr.io"
  container_image  = "${local.acr_login_server}/${var.container_image_repository}"

  # Versionless Key Vault secret URIs. Azure resolves to the current version
  # at runtime, so rotating a secret in KV doesn't require a Terraform apply.
  # Terraform never reads the secret VALUES.
  kv_secrets_base = "https://${var.key_vault_name}.vault.azure.net/secrets"

  kv_secret_ids = {
    ld_sdk_key     = "${local.kv_secrets_base}/ld-sdk-key"
    oauth_id       = "${local.kv_secrets_base}/oauth-id"
    oauth_password = "${local.kv_secrets_base}/oauth-password"
    oauth_secret   = "${local.kv_secrets_base}/oauth-secret"
    oauth_jwt_key  = "${local.kv_secrets_base}/oauth-jwt-key"
  }

  base_env = [
    { name = "SALESFORCE_URL", value = var.salesforce_url },
    { name = "OAUTH_USERNAME", value = var.oauth_username },
    { name = "OAUTH_URI", value = var.oauth_uri },
    { name = "HTTP_TIMEOUT", value = var.http_timeout },
  ]

  secret_env_common = [
    { name = "LD_SDK_KEY", secretRef = "ld-sdk-key" },
    { name = "OAUTH_ID", secretRef = "oauth-id" },
  ]

  secret_env_password = [
    { name = "OAUTH_PASSWORD", secretRef = "oauth-password" },
    { name = "OAUTH_SECRET", secretRef = "oauth-secret" },
  ]

  secret_env_jwt = [
    { name = "OAUTH_JWT_KEY", secretRef = "oauth-jwt-key" },
  ]

  env = concat(
    local.base_env,
    local.secret_env_common,
    local.using_jwt_auth ? local.secret_env_jwt : local.secret_env_password,
  )
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Resource group (imported)
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Log Analytics workspace (imported)
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Azure Container Registry (imported)
# ---------------------------------------------------------------------------

resource "azurerm_container_registry" "this" {
  name                = var.container_registry_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# User-assigned managed identity (imported)
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "app" {
  name                = var.managed_identity_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# ---------------------------------------------------------------------------
# Key Vault (imported)
#
# Secret VALUES are populated out-of-band (see bootstrap-secrets.ps1 or your
# Key Vault provisioning pipeline). Terraform only grants the Container App's
# managed identity read access — it does NOT manage the secret values.
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "this" {
  name                       = var.key_vault_name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  rbac_authorization_enabled = true
  tags                       = var.tags
}

resource "azurerm_role_assignment" "kv_reader_app" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# ---------------------------------------------------------------------------
# Container Apps environment (imported)
# ---------------------------------------------------------------------------

resource "azurerm_container_app_environment" "this" {
  name                       = var.container_app_environment_name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = var.tags
}

# ---------------------------------------------------------------------------
# Container App — bridge-sdk-host (imported)
# ---------------------------------------------------------------------------

resource "azurerm_container_app" "bridge" {
  name                         = var.container_app_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = local.acr_login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  secret {
    name                = "ld-sdk-key"
    identity            = azurerm_user_assigned_identity.app.id
    key_vault_secret_id = local.kv_secret_ids.ld_sdk_key
  }

  secret {
    name                = "oauth-id"
    identity            = azurerm_user_assigned_identity.app.id
    key_vault_secret_id = local.kv_secret_ids.oauth_id
  }

  dynamic "secret" {
    for_each = local.using_jwt_auth ? [] : [1]
    content {
      name                = "oauth-password"
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = local.kv_secret_ids.oauth_password
    }
  }

  dynamic "secret" {
    for_each = local.using_jwt_auth ? [] : [1]
    content {
      name                = "oauth-secret"
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = local.kv_secret_ids.oauth_secret
    }
  }

  dynamic "secret" {
    for_each = local.using_jwt_auth ? [1] : []
    content {
      name                = "oauth-jwt-key"
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = local.kv_secret_ids.oauth_jwt_key
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "bridge"
      image  = local.container_image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = local.env
        content {
          name        = env.value.name
          value       = lookup(env.value, "value", null)
          secret_name = lookup(env.value, "secretRef", null)
        }
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.kv_reader_app,
  ]
}
