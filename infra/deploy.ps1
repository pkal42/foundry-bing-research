<#
.SYNOPSIS
  Deploy the Foundry + Bing-Grounding infrastructure from .env.

.DESCRIPTION
  Reads provisioning settings from the .env file at the repo root, creates the
  resource group if missing, then runs `az deployment group create` against
  ./main.bicep. Idempotent — safe to re-run.

  Run from the repo root:  .\infra\deploy.ps1
  Or from this folder:     .\deploy.ps1
#>
[CmdletBinding()]
param(
  [string] $EnvFile = (Join-Path $PSScriptRoot ".." ".env"),
  [string] $BicepFile = (Join-Path $PSScriptRoot "main.bicep")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $EnvFile)) {
  throw ".env file not found at $EnvFile. Copy .env.example and fill it in."
}
if (-not (Test-Path $BicepFile)) {
  throw "Bicep template not found at $BicepFile."
}

# ── Parse .env into a hashtable (ignores comments + blank lines, strips quotes) ──
$envValues = @{}
foreach ($line in Get-Content $EnvFile) {
  $line = $line.Trim()
  if (-not $line -or $line.StartsWith("#")) { continue }
  $eq = $line.IndexOf("=")
  if ($eq -lt 1) { continue }
  $key = $line.Substring(0, $eq).Trim()
  $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
  $envValues[$key] = $value
}

function Need($name) {
  if (-not $envValues.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($envValues[$name])) {
    throw "$name is required in $EnvFile."
  }
  return $envValues[$name]
}
function Opt($name, $default) {
  if ($envValues.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace($envValues[$name])) {
    return $envValues[$name]
  }
  return $default
}

$subscriptionId       = Need "AZURE_SUBSCRIPTION_ID"
$resourceGroup        = Opt  "RESOURCE_GROUP"        "rg-foundry-bing-research"
$location             = Opt  "LOCATION"              "eastus"
$foundryAccount       = Opt  "FOUNDRY_ACCOUNT"       "foundry-bing-research-acct"
$foundryProject       = Opt  "FOUNDRY_PROJECT"       "bing-research-proj"
$modelName            = Opt  "MODEL_NAME"            "gpt-5.1"
$modelVersion         = Opt  "MODEL_VERSION"         "2025-11-13"
$modelDeployment      = Opt  "MODEL_DEPLOYMENT"      "gpt-5.1"
$modelSku             = Opt  "MODEL_SKU"             "GlobalStandard"
$modelCapacity        = Opt  "MODEL_CAPACITY"        "50"
$bingResource         = Opt  "BING_RESOURCE"         "bing-grounding-research"
$bingSku              = Opt  "BING_SKU"              "G1"
$bingConnectionName   = Opt  "BING_CONNECTION_NAME"  "bing-grounding-conn"

Write-Host "Subscription : $subscriptionId"
Write-Host "Resource grp : $resourceGroup ($location)"
Write-Host "Foundry      : $foundryAccount / $foundryProject"
Write-Host "Model        : $modelName v$modelVersion (deployment=$modelDeployment, sku=$modelSku, capacity=$modelCapacity)"
Write-Host "Bing         : $bingResource (sku=$bingSku, connection=$bingConnectionName)"
Write-Host ""

az account set --subscription $subscriptionId --only-show-errors | Out-Null

if (-not (az group show -n $resourceGroup --only-show-errors 2>$null)) {
  Write-Host "Creating resource group $resourceGroup in $location..."
  az group create -n $resourceGroup -l $location --only-show-errors | Out-Null
} else {
  Write-Host "Resource group $resourceGroup already exists."
}

Write-Host "`nDeploying $BicepFile (idempotent — safe to re-run)..."
$result = az deployment group create `
  -g $resourceGroup `
  -f $BicepFile `
  --parameters `
    "location=$location" `
    "foundryAccountName=$foundryAccount" `
    "foundryProjectName=$foundryProject" `
    "modelName=$modelName" `
    "modelVersion=$modelVersion" `
    "modelDeploymentName=$modelDeployment" `
    "modelSku=$modelSku" `
    "modelCapacity=$modelCapacity" `
    "bingResourceName=$bingResource" `
    "bingSku=$bingSku" `
    "bingConnectionName=$bingConnectionName" `
  --only-show-errors `
  -o json | ConvertFrom-Json

$out = $result.properties.outputs
Write-Host "`n[OK] Deployment complete."
Write-Host ""
Write-Host "  Project endpoint   : $($out.projectEndpoint.value)"
Write-Host "  Bing connection id : $($out.bingConnectionId.value)"
Write-Host "  Model deployment   : $($out.modelDeploymentName.value)"
Write-Host ""
Write-Host "Add these to your .env file:"
Write-Host "  AZURE_AI_PROJECT_ENDPOINT=$($out.projectEndpoint.value)"
Write-Host "  AZURE_AI_MODEL_DEPLOYMENT_NAME=$($out.modelDeploymentName.value)"
Write-Host "  BING_CONNECTION_ID=$($out.bingConnectionId.value)"
