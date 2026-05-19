// ─────────────────────────────────────────────────────────────────────────────
// modules/bing-grounding/bing-grounding.bicep
//
// Creates a Grounding-with-Bing-Search resource and wires it into an existing
// Foundry project as a typed connection. The Foundry project must already
// exist when this module is deployed — the caller (main.bicep) enforces order
// via a module dependency on the foundry module.
//
// The Bing API key is read at deployment time via listKeys() and injected
// into the connection's credentials. The literal key never appears in source.
// ─────────────────────────────────────────────────────────────────────────────

@description('Microsoft.Bing/accounts resource name (kind=Bing.Grounding).')
param bingResourceName string

@description('Grounding-with-Bing SKU. G1 is the standard tier.')
param bingSku string = 'G1'

@description('Foundry (AI Services) account name that owns the project to wire Bing into.')
param foundryAccountName string

@description('Foundry project name to wire Bing into. Must already exist.')
param foundryProjectName string

@description('Name of the connection inside the Foundry project.')
param bingConnectionName string = 'bing-grounding-conn'

// Bing.Grounding resources are always region=global.
resource bing 'Microsoft.Bing/accounts@2020-06-10' = {
  name: bingResourceName
  location: 'global'
  kind: 'Bing.Grounding'
  sku: {
    name: bingSku
  }
  properties: {}
}

// Reference the already-deployed Foundry account + project so we can attach a
// connection as a sub-resource of the project.
resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: foundryAccountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundry
  name: foundryProjectName
}

resource bingConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: bingConnectionName
  properties: {
    category: 'GroundingWithBingSearch'
    target: 'https://api.bing.microsoft.com/'
    authType: 'ApiKey'
    credentials: {
      key: bing.listKeys().key1
    }
    metadata: {
      ResourceId: bing.id
      ApiType: 'Azure'
    }
    isSharedToAll: true
  }
}

@description('ARM id of the Bing.Grounding resource.')
output bingResourceId string = bing.id

@description('Full ARM id of the project connection. Passed to BingGroundingTool / HostedWebSearchTool.')
output bingConnectionId string = bingConnection.id
