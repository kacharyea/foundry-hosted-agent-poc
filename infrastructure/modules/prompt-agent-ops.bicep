targetScope = 'resourceGroup'

param location string
param workspaceId string
param applicationInsightsId string
param actionGroupIds array
param agentName string
param environmentName string
param ownerName string
param backupOwnerName string
param runbookBaseUrl string
param evaluationFrequency string
param windowSize string
param toolFailureThreshold int
param tokenSpikeThreshold int
param tags object

// Prompt agents have no container. Foundry emits every span from the role "responsesapi" into AppDependencies:
// invoke_agent <agent>:<version>, chat <model>, and execute_tool <tool>. There is no AppRequests row.
var invocations = replace('''
AppDependencies
| where AppRoleName == "responsesapi" and Name startswith "invoke_agent __AGENT__:"
''', '__AGENT__', agentName)

var tools = replace('''
AppDependencies
| where AppRoleName == "responsesapi" and Name startswith "execute_tool"
| where tostring(Properties["gen_ai.agent.name"]) == "__AGENT__"
''', '__AGENT__', agentName)

var models = replace('''
AppDependencies
| where AppRoleName == "responsesapi" and Name startswith "chat "
| where tostring(Properties["gen_ai.agent.name"]) == "__AGENT__"
''', '__AGENT__', agentName)

var failedInvocationsQuery = '${invocations}| where Success == false\n| extend AgentVersion = tostring(Properties["gen_ai.agent.version"]), ErrorType = tostring(Properties["error.type"])\n'

var toolFailuresQuery = '${tools}| where Success == false\n| summarize Failures = count() by Tool = tostring(Properties["gen_ai.tool.name"]), AgentVersion = tostring(Properties["gen_ai.agent.version"])\n| where Failures >= ${toolFailureThreshold}\n'

var tokenQuery = '${models}| extend InputTokens = tolong(Properties["gen_ai.usage.input_tokens"]), OutputTokens = tolong(Properties["gen_ai.usage.output_tokens"])\n| summarize TotalTokens = sum(coalesce(InputTokens, 0) + coalesce(OutputTokens, 0)) by AgentVersion = tostring(Properties["gen_ai.agent.version"])\n| where TotalTokens > ${tokenSpikeThreshold}\n'

var alerts = [
  {
    name: 'prompt-agent-failed-invocations'
    slug: 'prompt-agent-failed-invocations'
    severity: 1
    severityClass: 'Page'
    description: 'The Foundry platform reported a failed invoke_agent for the prompt agent (for example rate_limit_exceeded or a model error). Customer-impacting; page the service owner.'
    query: failedInvocationsQuery
    splitByVersion: true
  }
  {
    name: 'prompt-agent-tool-failures'
    slug: 'prompt-agent-tool-failures'
    severity: 3
    severityClass: 'CreateWork'
    description: 'Repeated failures calling a tool (for example the Microsoft Learn MCP tool).'
    query: toolFailuresQuery
    splitByVersion: false
  }
  {
    name: 'prompt-agent-token-spike'
    slug: 'prompt-agent-token-spike'
    severity: 3
    severityClass: 'CreateWork'
    description: 'Model token usage exceeded the cost threshold in the window.'
    query: tokenQuery
    splitByVersion: false
  }
]

var panels = [
  {
    title: '1. Service health - is the prompt agent healthy now?'
    visualization: 'tiles'
    query: 'let p =\n${replace(invocations, '__AGENT__', '{AgentName}')};\nunion\n  (p | summarize Value = todouble(count()) | extend Metric = "Requests", Ord = 1),\n  (p | summarize Value = round(100.0 * countif(Success == true) / max_of(count(), 1), 1) | extend Metric = "Task success %", Ord = 2),\n  (p | summarize Value = round(100.0 * countif(Success == false) / max_of(count(), 1), 1) | extend Metric = "Failure %", Ord = 3),\n  (p | summarize Value = round(percentile(DurationMs, 95) / 1000.0, 1) | extend Metric = "P95 latency (s)", Ord = 4)\n| order by Ord asc\n| project Metric, Value'
  }
  {
    title: '2. Requests and failures over time'
    visualization: 'timechart'
    query: '${replace(invocations, agentName, '{AgentName}')}| summarize Requests = count(), Failures = countif(Success == false) by bin(TimeGenerated, 5m)'
  }
  {
    title: '3. Version markers - first and last seen per version (change check)'
    visualization: 'table'
    query: '${replace(invocations, agentName, '{AgentName}')}| extend Ver = tostring(Properties["gen_ai.agent.version"])\n| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated), Requests = count(), Failures = countif(Success == false), P95Ms = round(percentile(DurationMs, 95), 0) by Version = Ver\n| extend FailurePct = round(100.0 * Failures / Requests, 1)\n| order by FirstSeen desc'
  }
  {
    title: '4. Failures by error type - what is breaking?'
    visualization: 'table'
    query: '${replace(invocations, agentName, '{AgentName}')}| where Success == false\n| summarize Failures = count(), LastSeen = max(TimeGenerated) by ErrorType = tostring(Properties["error.type"]), ResultCode, Version = tostring(Properties["gen_ai.agent.version"])\n| order by Failures desc'
  }
  {
    title: '5. Tool quality - calls, failures, and tail latency per tool'
    visualization: 'table'
    query: '${replace(tools, agentName, '{AgentName}')}| summarize Calls = count(), Failures = countif(Success == false), P50Ms = round(percentile(DurationMs, 50), 0), P95Ms = round(percentile(DurationMs, 95), 0) by Tool = tostring(Properties["gen_ai.tool.name"])\n| extend FailurePct = round(100.0 * Failures / Calls, 1)'
  }
  {
    title: '6. Model usage and cost signals - tokens by version'
    visualization: 'table'
    query: '${replace(models, agentName, '{AgentName}')}| extend InputTokens = tolong(Properties["gen_ai.usage.input_tokens"]), OutputTokens = tolong(Properties["gen_ai.usage.output_tokens"]), CachedTokens = tolong(Properties["gen_ai.usage.cached_tokens"])\n| summarize ModelCalls = count(), InputTokens = sum(InputTokens), OutputTokens = sum(OutputTokens), CachedTokens = sum(CachedTokens), P95Ms = round(percentile(DurationMs, 95), 0) by Version = tostring(Properties["gen_ai.agent.version"]), Model = tostring(Properties["gen_ai.request.model"])\n| order by Version desc'
  }
  {
    title: '7. Trace pivot - copy OperationId into Logs, or open the transaction view'
    visualization: 'table'
    query: '${replace(invocations, agentName, '{AgentName}')}| project TimeGenerated, OperationId, Version = tostring(Properties["gen_ai.agent.version"]), DurationMs = round(DurationMs, 0), Success, ResultCode, ErrorType = tostring(Properties["error.type"]), ResponseId = tostring(Properties["gen_ai.response.id"])\n| top 50 by TimeGenerated desc'
  }
]

var queryItems = [for (panel, index) in panels: {
  type: 3
  name: 'prompt-query-${index}'
  content: union({
    version: 'KqlItem/1.0'
    title: panel.title
    query: panel.query
    queryType: 0
    resourceType: 'microsoft.operationalinsights/workspaces'
    crossComponentResources: [
      workspaceId
    ]
    visualization: panel.visualization
    size: panel.visualization == 'tiles' ? 4 : 0
    timeContext: {
      durationMs: 3600000
    }
    timeContextFromParameter: 'TimeRange'
  }, panel.visualization == 'tiles' ? {
    tileSettings: {
      showBorder: false
      titleContent: {
        columnMatch: 'Metric'
        formatter: 1
      }
      leftContent: {
        columnMatch: 'Value'
        formatter: 12
        formatOptions: {
          palette: 'auto'
        }
        numberFormat: {
          unit: 17
          options: {
            style: 'decimal'
            maximumFractionDigits: 2
          }
        }
      }
    }
  } : {})
}]

var intro = '''
# Prompt agent - operations

**Audience:** on-call responder and service owner. **Decision:** do we need to act, and where do we look first?

A prompt agent has no container. Foundry emits every span from the `responsesapi` role into `AppDependencies`: `invoke_agent <agent>:<version>` (availability and version), `chat <model>` (tokens), and `execute_tool` (tool calls). There are no container request rows, so there is no cold-start breakdown and no custom tool role. Task success is a platform-outcome proxy, not an evaluation score. Content capture is on for synthetic data only.
'''

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(applicationInsightsId, 'prompt-agent-operations')
  location: location
  kind: 'shared'
  tags: tags
  properties: {
    displayName: 'Prompt Agent - operations'
    category: 'workbook'
    sourceId: applicationInsightsId
    version: '1.0'
    serializedData: string({
      version: 'Notebook/1.0'
      isLocked: false
      fallbackResourceIds: [
        workspaceId
      ]
      items: concat([
        {
          type: 1
          name: 'intro'
          content: {
            json: intro
          }
        }
        {
          type: 9
          name: 'parameters'
          content: {
            version: 'KqlParameterItem/1.0'
            parameters: [
              {
                id: 'c2b4a7b1-8d2f-4c54-a062-7a1e6b2b0001'
                version: 'KqlParameterItem/1.0'
                name: 'TimeRange'
                label: 'Time range'
                type: 4
                isRequired: true
                value: {
                  durationMs: 3600000
                }
                typeSettings: {
                  selectableValues: [
                    { durationMs: 900000 }
                    { durationMs: 3600000 }
                    { durationMs: 14400000 }
                    { durationMs: 86400000 }
                    { durationMs: 259200000 }
                  ]
                  allowCustom: true
                }
              }
              {
                id: 'c2b4a7b1-8d2f-4c54-a062-7a1e6b2b0002'
                version: 'KqlParameterItem/1.0'
                name: 'AgentName'
                label: 'Agent (service)'
                type: 1
                isRequired: true
                value: agentName
              }
            ]
            style: 'pills'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
          }
        }
      ], queryItems)
    })
  }
}

resource rules 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in alerts: {
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
        dashboard: '${environment().portal}/#@/resource${workbook.id}'
        firstAction: 'Open the runbook, then pivot from the alert rows to OperationId in Logs.'
      }
    }
  }
}]

output workbookId string = workbook.id
output alertRuleNames array = [for alert in alerts: alert.name]
