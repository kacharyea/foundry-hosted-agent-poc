using '../main.bicep'

// Copy this file to an environment-specific name and customize it.
// The Foundry account and project must already exist and have a system-assigned identity.
param location = 'eastus2'
param foundryAccountName = 'my-foundry-account'
param foundryProjectName = 'my-foundry-project'
param containerRegistryName = 'myagentacr12345'
param logAnalyticsWorkspaceName = 'law-hosted-agent-dev'
param applicationInsightsName = 'appi-hosted-agent-dev'
param acrConnectionName = 'hosted-agent-acr'
param appInsightsConnectionName = 'hosted-agent-appinsights'
param logRetentionInDays = 30
param acrPullRoleAssignmentName = ''
param workspaceReaderRoleAssignmentName = ''
param tags = {
  workload: 'foundry-hosted-agent'
  environment: 'dev'
  managedBy: 'bicep'
}
