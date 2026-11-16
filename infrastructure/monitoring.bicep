targetScope = 'resourceGroup'

@description('Region for the workbook and alert rules.')
param location string = resourceGroup().location

@description('Existing Log Analytics workspace that receives the Application Insights telemetry.')
param logAnalyticsWorkspaceName string

@description('Existing workspace-based Application Insights component.')
param applicationInsightsName string

@description('Hosted Agent name as it appears in telemetry (gen_ai.agent.name and the container service role).')
param agentName string = 'foundry-hosted-integration-poc'

@description('Environment label carried on every alert (for example dev, test, prod).')
param environmentName string = 'demo'

@description('Primary owner shown on alerts. Use a team or role name, not a personal identifier, in committed files.')
param ownerName string = 'unassigned'

@description('Backup owner shown on alerts.')
param backupOwnerName string = 'unassigned'

@description('Notification email addresses. Leave empty to create alerts without an action group. Supply real addresses from a gitignored *.local.bicepparam file or the ALERT_EMAIL environment variable; never commit them.')
param alertEmailAddresses array = []

@description('Action group name.')
param actionGroupName string = 'ag-hosted-agent-ops'

@maxLength(12)
@description('Action group short name used in SMS and notifications (12 characters maximum).')
param actionGroupShortName string = 'AgentOps'

@description('Base URL where the runbooks are published (for example the repository docs/runbooks URL). Empty uses the relative docs/runbooks path.')
param runbookBaseUrl string = ''

@description('Create the alert rules.')
param enableAlerts bool = true

@description('Create the no-traffic heartbeat alert. Off by default because an idle demo agent would alert constantly.')
param enableNoTrafficAlert bool = false

@description('How often alert rules evaluate. Use PT1M for live demos.')
@allowed(['PT1M', 'PT5M', 'PT10M', 'PT15M', 'PT30M', 'PT1H'])
param alertEvaluationFrequency string = 'PT5M'

@description('Alert lookback window. Use PT5M for live demos.')
@allowed(['PT1M', 'PT5M', 'PT10M', 'PT15M', 'PT30M', 'PT1H'])
param alertWindowSize string = 'PT15M'

@minValue(1)
@description('p95 POST /responses latency (ms) considered sustained and severe.')
param latencyThresholdMs int = 15000

@minValue(1)
@description('Minimum requests in the window before the latency rule can fire.')
param minLatencySamples int = 5

@minValue(1)
@description('Unexpected tool failures in the window that raise a create-work alert.')
param toolErrorThreshold int = 3

@minValue(1)
@description('External dependency failures in the window that raise a create-work alert.')
param dependencyFailureThreshold int = 3

@minValue(1)
@description('Model tokens in the window that raise a cost create-work alert.')
param tokenSpikeThreshold int = 100000

@description('Optional one-time maintenance window start (yyyy-MM-ddTHH:mm:ss). Both start and end are required to create the suppression rule.')
param maintenanceWindowStart string = ''

@description('Optional maintenance window end (yyyy-MM-ddTHH:mm:ss).')
param maintenanceWindowEnd string = ''

@description('Time zone for the maintenance window.')
param maintenanceTimeZone string = 'UTC'

@description('Common tags.')
param tags object = {
  workload: 'foundry-hosted-agent-poc'
  managedBy: 'bicep'
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(alertEmailAddresses)) {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [for (address, index) in alertEmailAddresses: {
      name: 'email-${index}'
      emailAddress: address
      useCommonAlertSchema: true
    }]
  }
}

module workbook 'modules/ops-workbook.bicep' = {
  name: 'hosted-agent-ops-workbook'
  params: {
    location: location
    workspaceId: workspace.id
    applicationInsightsId: appInsights.id
    agentName: agentName
    tags: tags
  }
}

module alerts 'modules/ops-alerts.bicep' = if (enableAlerts) {
  name: 'hosted-agent-ops-alerts'
  params: {
    location: location
    workspaceId: workspace.id
    actionGroupIds: empty(alertEmailAddresses) ? [] : [resourceId('Microsoft.Insights/actionGroups', actionGroupName)]
    agentName: agentName
    environmentName: environmentName
    ownerName: ownerName
    backupOwnerName: backupOwnerName
    runbookBaseUrl: runbookBaseUrl
    dashboardUrl: '${environment().portal}/#@/resource${workbook.outputs.workbookId}'
    enableNoTrafficAlert: enableNoTrafficAlert
    evaluationFrequency: alertEvaluationFrequency
    windowSize: alertWindowSize
    latencyThresholdMs: latencyThresholdMs
    minLatencySamples: minLatencySamples
    toolErrorThreshold: toolErrorThreshold
    dependencyFailureThreshold: dependencyFailureThreshold
    tokenSpikeThreshold: tokenSpikeThreshold
    tags: tags
  }
  dependsOn: [
    actionGroup
  ]
}

// Scheduled maintenance suppression: removes action groups (notifications) but keeps the alert records.
resource maintenanceSuppression 'Microsoft.AlertsManagement/actionRules@2021-08-08' = if (!empty(maintenanceWindowStart) && !empty(maintenanceWindowEnd)) {
  name: 'suppress-hosted-agent-maintenance'
  location: 'global'
  tags: tags
  properties: {
    description: 'Suppress hosted-agent alert notifications during the scheduled maintenance window.'
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    conditions: [
      {
        field: 'AlertRuleName'
        operator: 'Contains'
        values: [
          'hosted-agent-'
        ]
      }
    ]
    schedule: {
      effectiveFrom: maintenanceWindowStart
      effectiveUntil: maintenanceWindowEnd
      timeZone: maintenanceTimeZone
    }
    actions: [
      {
        actionType: 'RemoveAllActionGroups'
      }
    ]
  }
}

output workbookId string = workbook.outputs.workbookId
output actionGroupId string = empty(alertEmailAddresses) ? '' : resourceId('Microsoft.Insights/actionGroups', actionGroupName)
output alertRuleNames array = alerts.?outputs.alertRuleNames ?? []
