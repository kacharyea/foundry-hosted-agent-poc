targetScope = 'resourceGroup'

param foundryAccountName string
param foundryProjectName string
param containerRegistryName string
param logAnalyticsWorkspaceName string
param acrPullRoleAssignmentName string
param workspaceReaderRoleAssignmentName string

var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)
var logAnalyticsDataReaderRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3b03c2da-16b3-4a49-8834-0f8130efdd3b'
)
var effectiveAcrPullAssignmentName = empty(acrPullRoleAssignmentName)
  ? guid(registry.id, foundryProject.id, acrPullRoleDefinitionId)
  : acrPullRoleAssignmentName
var effectiveWorkspaceReaderAssignmentName = empty(workspaceReaderRoleAssignmentName)
  ? guid(workspace.id, foundryProject.id, logAnalyticsDataReaderRoleDefinitionId)
  : workspaceReaderRoleAssignmentName

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

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// The existing Basic registry uses LegacyRegistryPermissions, so AcrPull is the effective pull role.
resource registryPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: effectiveAcrPullAssignmentName
  scope: registry
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource workspaceReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: effectiveWorkspaceReaderAssignmentName
  scope: workspace
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: logAnalyticsDataReaderRoleDefinitionId
  }
}

output foundryProjectPrincipalId string = foundryProject.identity.principalId
output registryPullAssignmentId string = registryPull.id
output workspaceReaderAssignmentId string = workspaceReader.id
