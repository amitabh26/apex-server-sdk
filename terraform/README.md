# Terraform — LaunchDarkly Apex Bridge (Option A: KV-only secrets)

Adopts existing Azure resources into Terraform state and wires the bridge Container App to Key Vault secret references. **Terraform never sees plaintext secret values** — secrets live only in `kv-ld-sfsc`, written by an operator via [bootstrap-secrets.ps1](bootstrap-secrets.ps1).

| Resource type | Name |
|---|---|
| Resource group | `engage-launchdarkly-prod` |
| Key Vault | `kv-ld-sfsc` |
| Container Registry | `acrsfscldbridge` |
| Managed Identity | `ld-bridge-mi` |
| Container App Environment | `env-launchdarkly-prod` |
| Container App | `bridge-sdk-host` |
| Log Analytics Workspace | *(set via `log_analytics_workspace_name`)* |
| Image | `acrsfscldbridge.azurecr.io/launchdarkly-sf-bridge:latest` |

## How secrets flow (no plaintext through Terraform)

```
Operator                Key Vault                 Container App
  │                        │                           │
  │  bootstrap-secrets.ps1 │                           │
  ├───────────────────────►│  ld-sdk-key               │
  ├───────────────────────►│  oauth-id                 │
  ├───────────────────────►│  oauth-password           │
  └───────────────────────►│  oauth-secret             │
                           │                           │
                           │  versionless URI:         │
                           │  https://kv-ld-sfsc       │
                           │   .vault.azure.net/       │
                           │   secrets/ld-sdk-key      │
                           │                           │
                           │◄──────────────────────────┤  managed identity
                           │   (read at runtime via    │  ld-bridge-mi
                           │    AcrPull + KV Secrets   │
                           │    User RBAC)             │
```

Terraform's job in this stack is to:

1. Adopt the 7 resources into state (via [imports.tf](imports.tf)).
2. Maintain RBAC: MI → AcrPull on ACR, MI → KV Secrets User on KV.
3. Configure the Container App's `secret { key_vault_secret_id = ... }` blocks to point at versionless KV URIs.
4. Configure non-secret env vars (`SALESFORCE_URL`, `OAUTH_USERNAME`, `OAUTH_URI`, `HTTP_TIMEOUT`).

Rotating a secret = `az keyvault secret set` (or re-run bootstrap-secrets.ps1). No `terraform apply` needed; the versionless URI auto-resolves to the latest version on the next Container App revision pull.

## Prerequisites

- `terraform` >= 1.5
- `az login` to the subscription that owns the resources
- Your AAD principal needs:
  - Contributor on the resource group
  - **Role Based Access Control Administrator** on the RG (to create role assignments for the MI)
  - **Storage Blob Data Owner** on the tfstate storage account (created by bootstrap-state.ps1)
  - **Key Vault Secrets Officer** on `kv-ld-sfsc` (to run bootstrap-secrets.ps1)

## One-time workflow

### 1. Bootstrap the state backend

```powershell
cd c:\amitabh\fork-ld\apex-server-sdk\terraform
.\bootstrap-state.ps1
```

Creates an Azure Storage account `stldbridgetfstate` (you may need to edit the name in both [bootstrap-state.ps1](bootstrap-state.ps1) and [providers.tf](providers.tf) — storage account names are globally unique).

### 2. Bootstrap Key Vault secrets

```powershell
.\bootstrap-secrets.ps1
# OR for JWT auth:
.\bootstrap-secrets.ps1 -AuthMode jwt
```

You'll be prompted for each value (SecureString — no plaintext on screen, in history, or on disk).

### 3. Prepare tfvars

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set log_analytics_workspace_name + non-secret config
```

### 4. Init + plan + apply

```powershell
terraform init
terraform plan -out tfplan
# REVIEW the plan carefully — see "Expected drift" below
terraform apply tfplan
```

## Expected drift on first plan

The plan will **import** the 7 existing resources and likely show diffs because [main.tf](main.tf) doesn't yet know every attribute of your live resources. For each diff:

- If the live value is correct → update main.tf to match.
- If main.tf is correct → let apply make the change.

Common ones to watch:

| Attribute | Note |
|---|---|
| `azurerm_key_vault.purge_protection_enabled` | Prod KVs often have this `true` |
| `azurerm_key_vault.soft_delete_retention_days` | Default 7; portal default is 90 |
| `azurerm_container_registry.sku` | If Standard/Premium, update main.tf |
| `azurerm_log_analytics_workspace.retention_in_days` | Match your live value |
| `tags` | Terraform wants to add `workload`/`managed` tags |

## Building & pushing the image

```powershell
cd c:\amitabh\fork-ld\apex-server-sdk
az acr build `
  --registry acrsfscldbridge `
  --image launchdarkly-sf-bridge:1.0.0 `
  --file Dockerfile `
  .
```

Then update `container_image_repository` in tfvars and `terraform apply`.

## Rotating a secret

No Terraform involved:

```powershell
az keyvault secret set --vault-name kv-ld-sfsc --name oauth-password --value '<new>'
az containerapp revision restart -n bridge-sdk-host -g engage-launchdarkly-prod
```

The Container App's versionless KV URI auto-resolves to the new version.

## Switching auth mode

```powershell
# 1. Add the JWT key to KV (and remove password/secret if you want)
.\bootstrap-secrets.ps1 -AuthMode jwt

# 2. Flip auth_mode in terraform.tfvars to "jwt"
# 3. terraform apply  — Container App secrets and env vars adjust automatically
```

## Files

| File | Purpose |
|---|---|
| [providers.tf](providers.tf) | Provider + remote state backend |
| [variables.tf](variables.tf) | All inputs — none of them secret |
| [main.tf](main.tf) | Resources |
| [imports.tf](imports.tf) | `import` blocks for the 7 pre-existing resources |
| [outputs.tf](outputs.tf) | Resource IDs, including ones that reproduce your `az ... show` commands |
| [terraform.tfvars.example](terraform.tfvars.example) | Template (no secrets) |
| [bootstrap-state.ps1](bootstrap-state.ps1) | One-time: create tfstate storage account |
| [bootstrap-secrets.ps1](bootstrap-secrets.ps1) | Interactive: write secrets to KV |
| [.gitignore](.gitignore) | Excludes `.tfvars`, `.tfstate`, `.terraform/` |
