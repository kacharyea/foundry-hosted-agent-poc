targetScope = 'resourceGroup'

@description('Azure region for the Hosted Agent support resources.')
param location string = resourceGroup().location

@description('Name of the existing Microsoft Foundry account. This deployment does not modify it.')
param foundryAccountName string

@description('Name of the existing Microsoft Foundry project. This deployment does not modify it.')
param foundryProjectName string

@description('Container registry used for immutable Hosted Agent images.')
param containerRegistryName string

@description('Log Analytics workspace receiving Application Insights telemetry.')
param logAnalyticsWorkspaceName string

@description('Workspace-based Application Insights component connected to Foundry.')
param applicationInsightsName string

@description('Foundry project connection name for ACR.')
param acrConnectionName string = 'hosted-agent-acr'

@description('Foundry project connection name for Application Insights.')
param appInsightsConnectionName string = 'hosted-agent-appinsights'

@description('Existing AcrPull role-assignment GUID to adopt. Leave empty for a deterministic GUID in a new environment.')
param acrPullRoleAssignmentName string = ''

@description('Existing workspace-reader role-assignment GUID to adopt. Leave empty for a deterministic GUID in a new environment.')
param workspaceReaderRoleAssignmentName string = ''

@allowed([
  30
  60
  90
  120
  180
  270
  365
  550
  730
])
@description('Log Analytics retention in days.')
param logRetentionInDays int = 30

@description('Common resource tags. Shared Foundry resources are not retagged.')
param tags object = {
  workload: 'foundry-hosted-agent-poc'
  environment: 'demo'
  managedBy: 'bicep'
}

module supportResources 'modules/support-resources.bicep' = {
  name: 'hosted-agent-support-resources'
  params: {
    location: location
    containerRegistryName: containerRegistryName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    applicationInsightsName: applicationInsightsName
    logRetentionInDays: logRetentionInDays
    tags: tags
  }
}

module projectConnections 'modules/foundry-connections.bicep' = {
  name: 'hosted-agent-foundry-connections'
  dependsOn: [
    supportResources
  ]
  params: {
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    containerRegistryName: containerRegistryName
    applicationInsightsName: applicationInsightsName
    acrConnectionName: acrConnectionName
    appInsightsConnectionName: appInsightsConnectionName
  }
}

module workloadPermissions 'modules/permissions.bicep' = {
  name: 'hosted-agent-workload-permissions'
  dependsOn: [
    supportResources
  ]
  params: {
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    containerRegistryName: containerRegistryName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    acrPullRoleAssignmentName: acrPullRoleAssignmentName
    workspaceReaderRoleAssignmentName: workspaceReaderRoleAssignmentName
  }
}

output containerRegistryId string = supportResources.outputs.containerRegistryId
output containerRegistryLoginServer string = supportResources.outputs.containerRegistryLoginServer
output logAnalyticsWorkspaceId string = supportResources.outputs.logAnalyticsWorkspaceId
output applicationInsightsId string = supportResources.outputs.applicationInsightsId
output foundryProjectId string = projectConnections.outputs.foundryProjectId
output foundryProjectPrincipalId string = workloadPermissions.outputs.foundryProjectPrincipalId
