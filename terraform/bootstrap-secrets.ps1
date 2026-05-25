# Populate Key Vault with the secrets the bridge expects.
# Run this BEFORE `terraform apply` (or any time you need to rotate a secret).
#
# Secrets are read interactively via Read-Host -AsSecureString — they never
# touch disk, command history, or this file.
#
# Requires:
#   - az CLI, logged in
#   - You have 'Key Vault Secrets Officer' (or equivalent) on the KV

[CmdletBinding()]
param(
    [string]$KeyVaultName = 'kv-ld-sfsc',
    [ValidateSet('password','jwt')]
    [string]$AuthMode     = 'password'
)

$ErrorActionPreference = 'Stop'

function Set-KvSecret {
    param([string]$Name, [string]$Prompt)

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name $Name `
            --value $plain `
            --output none
        Write-Host "  set: $Name"
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        Remove-Variable plain -ErrorAction SilentlyContinue
    }
}

Write-Host "Writing secrets to Key Vault '$KeyVaultName' (auth_mode=$AuthMode)..."

Set-KvSecret -Name 'ld-sdk-key' -Prompt 'LaunchDarkly SDK key (LD_SDK_KEY)'
Set-KvSecret -Name 'oauth-id'   -Prompt 'Salesforce connected app consumer key (OAUTH_ID)'

switch ($AuthMode) {
    'password' {
        Set-KvSecret -Name 'oauth-password' -Prompt 'Salesforce password + security token (OAUTH_PASSWORD)'
        Set-KvSecret -Name 'oauth-secret'   -Prompt 'Salesforce connected app consumer secret (OAUTH_SECRET)'
    }
    'jwt' {
        Set-KvSecret -Name 'oauth-jwt-key' -Prompt 'Base64-encoded PEM RSA private key (OAUTH_JWT_KEY)'
    }
}

Write-Host ""
Write-Host "Done. The Container App will pick up the new values on its next revision."
Write-Host "To force a roll: az containerapp revision restart -n bridge-sdk-host -g engage-launchdarkly-prod"
