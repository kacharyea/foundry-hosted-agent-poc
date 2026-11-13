targetScope = 'resourceGroup'

param foundryAccountName string
param foundryProjectName string
param containerRegistryName string
param applicationInsightsName string
param acrConnectionName string
param appInsightsConnectionName string

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource acrConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: acrConnectionName
  properties: {
    #disable-next-line BCP036 // The 2025-06-01 service accepts this value although its generated type omits it.
    authType: 'ProjectManagedIdentity'
    category: 'ContainerRegistry'
    isSharedToAll: false
    metadata: {}
    target: registry.id
    useWorkspaceManagedIdentity: false
  }
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: appInsightsConnectionName
  properties: {
    authType: 'ApiKey'
    category: 'AppInsights'
    isSharedToAll: false
    metadata: {
      ApplicationInsightsConnectionString: appInsights.properties.ConnectionString
      ResourceId: appInsights.id
    }
    target: appInsights.id
    useWorkspaceManagedIdentity: false
  }
}

output foundryProjectId string = foundryProject.id
output acrConnectionId string = acrConnection.id
output appInsightsConnectionId string = appInsightsConnection.id
