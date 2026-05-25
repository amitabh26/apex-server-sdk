output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "container_app_name" {
  value = azurerm_container_app.bridge.name
}

output "container_app_environment_name" {
  value = azurerm_container_app_environment.this.name
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "managed_identity_name" {
  value = azurerm_user_assigned_identity.app.name
}

output "managed_identity_principal_id" {
  description = "Same value as: az identity show -n ld-bridge-mi -g engage-launchdarkly-prod --query principalId -o tsv"
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "managed_identity_resource_id" {
  description = "Same value as: az identity show -n ld-bridge-mi -g engage-launchdarkly-prod --query id -o tsv"
  value       = azurerm_user_assigned_identity.app.id
}

output "acr_resource_id" {
  description = "Same value as: az acr show -n acrsfscldbridge --query id -o tsv"
  value       = azurerm_container_registry.this.id
}

output "log_analytics_workspace" {
  value = azurerm_log_analytics_workspace.this.name
}

output "container_image" {
  value = "${azurerm_container_registry.this.login_server}/${var.container_image_repository}"
}

output "expected_kv_secrets" {
  description = "Secrets the bridge expects in Key Vault. Populate them with bootstrap-secrets.ps1 before applying."
  value = {
    always = ["ld-sdk-key", "oauth-id"]
    if_password_auth = ["oauth-password", "oauth-secret"]
    if_jwt_auth      = ["oauth-jwt-key"]
  }
}
