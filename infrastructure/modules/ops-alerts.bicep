targetScope = 'resourceGroup'

param location string
param workspaceId string
param actionGroupIds array
param agentName string
param environmentName string
param ownerName string
param backupOwnerName string
param runbookBaseUrl string
param dashboardUrl string
param enableNoTrafficAlert bool
param evaluationFrequency string
param windowSize string
param latencyThresholdMs int
param minLatencySamples int
param toolErrorThreshold int
param dependencyFailureThreshold int
param tokenSpikeThreshold int
param tags object

// Expected controlled tool outcomes are not outages. They are excluded from error alerts the same way
// access denials are excluded in a RAG workflow.
var expectedToolErrors = '"invalid_user_id", "invalid_query"'

// Foundry platform and identity traffic generates benign probe rows (for example HTTP 404 state-store
// lookups). External dependencies are everything else, minus the documented benign MCP 405 rows.
var externalDependencyFilter = '''
| where DependencyType == "HTTP"
| where not(Target endswith ".services.ai.azure.com" or Target endswith ".openai.azure.com" or Target has "agent365" or Target has "login.microsoftonline")
| where not(Target == "learn.microsoft.com" and ResultCode == "405")
'''

var platformFailures = replace('''
AppRequests
| where AppRoleName == "agentsv2" and Name == "invoke_agent"
| where tostring(Properties["gen_ai.agent.name"]) == "__AGENT__"
| where Success == false
| extend AgentVersion = tostring(Properties["gen_ai.agent.version"])
''', '__AGENT__', agentName)

var latencyQuery = replace(replace(replace('''
AppRequests
| where AppRoleName == "__AGENT__" and Name == "POST /responses"
| summarize Samples = count(), P95Ms = percentile(DurationMs, 95) by AgentVersion = tostring(AppVersion)
| where Samples >= __MIN__ and P95Ms > __THRESHOLD__
''', '__AGENT__', agentName), '__MIN__', string(minLatencySamples)), '__THRESHOLD__', string(latencyThresholdMs))

var toolErrorQuery = replace(replace(replace('''
AppDependencies
| where AppRoleName == "__AGENT__-tools" and Name startswith "tool." and Success == false
| extend ErrorType = tostring(Properties["error.type"]), Tool = tostring(Properties["gen_ai.tool.name"])
| where ErrorType !in (__EXPECTED__)
| summarize Failures = count() by Tool, ErrorType, AgentVersion = tostring(AppVersion)
| where Failures >= __THRESHOLD__
''', '__AGENT__', agentName), '__EXPECTED__', expectedToolErrors), '__THRESHOLD__', string(toolErrorThreshold))

var dependencyHead = replace('''
AppDependencies
| where AppRoleName == "__AGENT__"
''', '__AGENT__', agentName)

var dependencyTail = replace('''
| where Success == false
| summarize Failures = count() by Target, AgentVersion = tostring(AppVersion)
| where Failures >= __THRESHOLD__
''', '__THRESHOLD__', string(dependencyFailureThreshold))

var dependencyQuery = concat(dependencyHead, externalDependencyFilter, dependencyTail)

var tokenQuery = replace(replace('''
AppDependencies
| where AppRoleName == "__AGENT__" and Name startswith "chat "
| extend InputTokens = tolong(Properties["gen_ai.usage.input_tokens"]), OutputTokens = tolong(Properties["gen_ai.usage.output_tokens"])
| summarize TotalTokens = sum(coalesce(InputTokens, 0) + coalesce(OutputTokens, 0)) by AgentVersion = tostring(AppVersion)
| where TotalTokens > __THRESHOLD__
''', '__AGENT__', agentName), '__THRESHOLD__', string(tokenSpikeThreshold))

var noTrafficQuery = replace('''
AppRequests
| where AppRoleName == "agentsv2" and Name == "invoke_agent"
| where tostring(Properties["gen_ai.agent.name"]) == "__AGENT__"
| summarize Requests = count()
| where Requests == 0
''', '__AGENT__', agentName)

// severityClass follows the workshop alert strategy: Page, CreateWork, or Visualize.
var alerts = [
  {
    name: 'hosted-agent-failed-invocations'
    slug: 'failed-invocations'
    enabled: true
    severity: 1
    severityClass: 'Page'
    description: 'The Foundry platform reported a failed invoke_agent (for example session_not_ready or HTTP 500). Customer-impacting; page the service owner.'
    query: platformFailures
    splitByVersion: true
  }
  {
    name: 'hosted-agent-sustained-latency'
    slug: 'sustained-latency'
    enabled: true
    severity: 2
    severityClass: 'Page'
    description: 'p95 POST /responses latency exceeds the threshold with enough samples. Percentile plus volume, never average only.'
    query: latencyQuery
    splitByVersion: false
  }
  {
    name: 'hosted-agent-tool-errors'
    slug: 'tool-errors'
    enabled: true
    severity: 3
    severityClass: 'CreateWork'
    description: 'Repeated unexpected tool failures. Expected controlled errors (invalid_user_id, invalid_query) are excluded.'
    query: toolErrorQuery
    splitByVersion: false
  }
  {
    name: 'hosted-agent-dependency-failures'
    slug: 'dependency-failures'
    enabled: true
    severity: 3
    severityClass: 'CreateWork'
    description: 'Repeated failures calling an external dependency. Foundry platform probes and benign MCP 405 rows are excluded.'
    query: dependencyQuery
    splitByVersion: false
  }
  {
    name: 'hosted-agent-token-spike'
    slug: 'token-spike'
    enabled: true
    severity: 3
    severityClass: 'CreateWork'
    description: 'Model token usage exceeded the cost threshold in the window.'
    query: tokenQuery
    splitByVersion: false
  }
  {
    name: 'hosted-agent-no-traffic'
    slug: 'no-traffic'
    enabled: enableNoTrafficAlert
    severity: 3
    severityClass: 'CreateWork'
    description: 'No invoke_agent requests in the window. Opt-in heartbeat for agents with steady traffic.'
    query: noTrafficQuery
    splitByVersion: false
  }
]

resource rules 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in alerts: if (alert.enabled) {
  name: alert.name
  location: location
  kind: 'LogAlert'
  tags: tags
  properties: {
    displayName: alert.name
    description: alert.description
    enabled: true
    severity: alert.severity
    scopes: [
      workspaceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: alert.query
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
          dimensions: alert.splitByVersion ? [
            {
              name: 'AgentVersion'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ] : []
        }
      ]
    }
    actions: {
      actionGroups: actionGroupIds
      customProperties: {
        service: agentName
        environment: environmentName
        severityClass: alert.severityClass
        owner: ownerName
        backupOwner: backupOwnerName
        runbook: empty(runbookBaseUrl) ? 'docs/runbooks/${alert.slug}.md' : '${runbookBaseUrl}/${alert.slug}.md'
        dashboard: dashboardUrl
        firstAction: 'Open the runbook, then pivot from the alert rows to OperationId in Logs.'
      }
    }
  }
}]

output alertRuleNames array = map(filter(alerts, alert => alert.enabled), alert => alert.name)
