using '../monitoring.bicep'

// Copy this file to an environment-specific name ending in .local.bicepparam (gitignored) and edit it.
// Names must match the resources created by main.bicep.
param logAnalyticsWorkspaceName = 'law-hosted-agent-dev'
param applicationInsightsName = 'appi-hosted-agent-dev'
param agentName = 'foundry-hosted-integration-poc'
param environmentName = 'dev'

// Use team or role names in committed files.
param ownerName = 'unassigned'
param backupOwnerName = 'unassigned'

// Notification email. Two ways to supply it without committing a personal address:
//   1. Set the ALERT_EMAIL environment variable (works in pipelines and local shells), or
//   2. Put the address in your own *.local.bicepparam file.
// Leave both empty to deploy alerts without notifications.
var alertEmail = readEnvironmentVariable('ALERT_EMAIL', '')
param alertEmailAddresses = empty(alertEmail) ? [] : [alertEmail]

// Where runbooks are published, for example https://github.com/<org>/<repo>/blob/main/docs/runbooks
param runbookBaseUrl = ''

// Live-demo tuning. Defaults suit steady operation.
// param alertEvaluationFrequency = 'PT1M'
// param alertWindowSize = 'PT5M'
// param latencyThresholdMs = 15000
// param enableNoTrafficAlert = false
// param maintenanceWindowStart = '2026-12-05T02:00:00'
// param maintenanceWindowEnd = '2026-12-05T04:00:00'
