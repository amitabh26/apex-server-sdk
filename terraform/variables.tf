variable "location" {
  description = "Azure region of the existing resource group."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags applied to managed resources."
  type        = map(string)
  default = {
    workload = "ld-apex-bridge"
    managed  = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Existing resource names (in Azure)
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  type    = string
  default = "engage-launchdarkly-prod"
}

variable "key_vault_name" {
  type    = string
  default = "kv-ld-sfsc"
}

variable "container_registry_name" {
  type    = string
  default = "acrsfscldbridge"
}

variable "managed_identity_name" {
  type    = string
  default = "ld-bridge-mi"
}

variable "container_app_environment_name" {
  type    = string
  default = "env-launchdarkly-prod"
}

variable "container_app_name" {
  type    = string
  default = "bridge-sdk-host"
}

variable "log_analytics_workspace_name" {
  description = "Name of the existing Log Analytics workspace backing the Container Apps environment."
  type        = string
}

# ---------------------------------------------------------------------------
# Container image
# ---------------------------------------------------------------------------

variable "container_image_repository" {
  description = "Image repository:tag pushed to ACR. Combined with the ACR login server."
  type        = string
  default     = "launchdarkly-sf-bridge:latest"
}

# ---------------------------------------------------------------------------
# Bridge configuration (non-secret)
# ---------------------------------------------------------------------------

variable "salesforce_url" {
  description = "Salesforce Apex REST URL, e.g. https://yourorg.salesforce.com/services/apexrest/"
  type        = string
}

variable "oauth_username" {
  description = "Salesforce username for the connected app integration user."
  type        = string
}

variable "oauth_uri" {
  description = "Salesforce OAuth token endpoint. Override for sandbox."
  type        = string
  default     = "https://login.salesforce.com/services/oauth2/token"
}

variable "http_timeout" {
  description = "HTTP timeout for the bridge's outbound calls (Go duration)."
  type        = string
  default     = "1500ms"
}

# ---------------------------------------------------------------------------
# Auth mode — picks which Key Vault secrets the Container App references.
# Secret VALUES live only in Key Vault; Terraform never reads them.
# ---------------------------------------------------------------------------

variable "auth_mode" {
  description = "Salesforce auth mode: 'password' (uses oauth-password + oauth-secret in KV) or 'jwt' (uses oauth-jwt-key in KV)."
  type        = string
  default     = "password"

  validation {
    condition     = contains(["password", "jwt"], var.auth_mode)
    error_message = "auth_mode must be 'password' or 'jwt'."
  }
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------

variable "cpu" {
  type    = number
  default = 0.25
}

variable "memory" {
  type    = string
  default = "0.5Gi"
}

variable "min_replicas" {
  type    = number
  default = 1
}

variable "max_replicas" {
  description = "The bridge is a singleton — keep at 1."
  type        = number
  default     = 1
}
