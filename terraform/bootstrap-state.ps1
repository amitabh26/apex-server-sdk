# One-time bootstrap of the Azure Storage account that holds Terraform state.
# Run this BEFORE `terraform init`.
#
# Requires: az CLI, logged into the target subscription with Contributor on
# the resource group.

[CmdletBinding()]
param(
    [string]$ResourceGroup     = 'engage-launchdarkly-prod',
    [string]$Location          = 'westeurope',
    [string]$StorageAccount    = 'stldbridgetfstate',   # MUST be globally unique. Edit if taken.
    [string]$ContainerName     = 'tfstate'
)

$ErrorActionPreference = 'Stop'

Write-Host "Creating storage account '$StorageAccount' in '$ResourceGroup'..."

az storage account create `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --min-tls-version TLS1_2 `
    --allow-blob-public-access false `
    --allow-shared-key-access false `
    --encryption-services blob `
    | Out-Null

Write-Host "Granting Storage Blob Data Owner on the account to the current user..."

$accountId = az storage account show -n $StorageAccount -g $ResourceGroup --query id -o tsv
$myObjectId = az ad signed-in-user show --query id -o tsv

az role assignment create `
    --assignee-object-id $myObjectId `
    --assignee-principal-type User `
    --role 'Storage Blob Data Owner' `
    --scope $accountId `
    | Out-Null

Write-Host "Creating blob container '$ContainerName' (using AAD auth)..."

az storage container create `
    --name $ContainerName `
    --account-name $StorageAccount `
    --auth-mode login `
    | Out-Null

Write-Host ""
Write-Host "Done. If you changed StorageAccount, edit providers.tf to match:"
Write-Host "    storage_account_name = '$StorageAccount'"
Write-Host ""
Write-Host "Next: terraform init"
