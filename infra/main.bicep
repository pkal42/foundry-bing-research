// ─────────────────────────────────────────────────────────────────────────────
// infra/main.bicep
//
// Resource-group-scoped composition of the shared modules used by all three
// notebooks (transfer-pricing, regulatory-monitoring, foundry-bing-research).
// All need identical infrastructure, so one main.bicep serves them all.
//
//   modules/<rp>/<module>.bicep  — reusable per-RP building blocks
//   infra/main.bicep             — lab-/scenario-level composition
//
// Re-running this template is safe; Bicep diffs against deployed state.
// ─────────────────────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Azure region for the Foundry account and model deployment. Bing is always region=global.')
param location string = resourceGroup().location

// ── Foundry parameters ───────────────────────────────────────────────────────
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

// ── Bing parameters ──────────────────────────────────────────────────────────
@description('Microsoft.Bing/accounts resource name (kind=Bing.Grounding).')
param bingResourceName string

@description('Grounding-with-Bing SKU. G1 is the standard tier.')
param bingSku string = 'G1'

@description('Name of the connection inside the Foundry project that wires up the Bing resource.')
param bingConnectionName string = 'bing-grounding-conn'

// ── Modules ──────────────────────────────────────────────────────────────────
module foundryModule './modules/foundry/foundry.bicep' = {
  name: 'foundry'
  params: {
    location: location
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    modelName: modelName
    modelVersion: modelVersion
    modelDeploymentName: modelDeploymentName
    modelSku: modelSku
    modelCapacity: modelCapacity
  }
}

module bingModule './modules/bing-grounding/bing-grounding.bicep' = {
  name: 'bingGrounding'
  params: {
    bingResourceName: bingResourceName
    bingSku: bingSku
    foundryAccountName: foundryModule.outputs.foundryAccountName
    foundryProjectName: foundryModule.outputs.foundryProjectName
    bingConnectionName: bingConnectionName
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────
@description('Project endpoint passed to FoundryAgent / AzureAIAgentClient.')
output projectEndpoint string = foundryModule.outputs.projectEndpoint

@description('ARM id of the Foundry project.')
output projectId string = foundryModule.outputs.projectId

@description('Model deployment alias your code uses at runtime.')
output modelDeploymentName string = foundryModule.outputs.modelDeploymentName

@description('ARM id of the Bing.Grounding resource.')
output bingResourceId string = bingModule.outputs.bingResourceId

@description('Full ARM id of the project connection. Passed to BingGroundingTool / HostedWebSearchTool.')
output bingConnectionId string = bingModule.outputs.bingConnectionId
