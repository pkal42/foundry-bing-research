// ─────────────────────────────────────────────────────────────────────────────
// modules/foundry/foundry.bicep
//
// Creates a Foundry (AI Services) account, a project under it, and a single
// model deployment. Idempotent — re-deploying with the same parameters is a
// no-op.
// ─────────────────────────────────────────────────────────────────────────────

@description('Azure region for the Foundry account and model deployment.')
param location string = resourceGroup().location

@description('Foundry (AI Services) account name. 3-24 chars, lowercase letters/digits/hyphens, globally unique.')
@minLength(3)
@maxLength(24)
param foundryAccountName string

@description('Foundry project name within the AI Services account.')
param foundryProjectName string

@description('Catalog model id (what Azure recognizes, e.g. gpt-5.1).')
param modelName string = 'gpt-5.1'

@description('Pinned model version to avoid silent version drift.')
param modelVersion string = '2025-11-13'

@description('Model deployment alias used by application code at runtime.')
param modelDeploymentName string = 'gpt-5.1'

@description('Model SKU. GlobalStandard = pay-as-you-go global throughput.')
param modelSku string = 'GlobalStandard'

@description('Model SKU capacity in thousands of tokens-per-minute (TPM).')
@minValue(1)
param modelCapacity int = 50

resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Required for AOAI endpoint URLs and for Foundry projects to attach.
    customSubDomainName: foundryAccountName
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: foundryProjectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: foundryProjectName
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: foundry
  name: modelDeploymentName
  sku: {
    name: modelSku
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

@description('Foundry account name (echo).')
output foundryAccountName string = foundry.name

@description('Foundry project name (echo).')
output foundryProjectName string = project.name

@description('ARM id of the Foundry project.')
output projectId string = project.id

@description('Project endpoint passed to FoundryAgent / AzureAIAgentClient.')
output projectEndpoint string = 'https://${foundry.name}.services.ai.azure.com/api/projects/${project.name}'

@description('Model deployment alias your code uses at runtime.')
output modelDeploymentName string = modelDeployment.name
