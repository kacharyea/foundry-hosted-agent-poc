targetScope = 'resourceGroup'

param location string
param workspaceId string
param applicationInsightsId string
param agentName string
param tags object

// Workbook parameters substituted at render time: {AgentName}, {Version}. The time range is applied to
// every query through timeContextFromParameter, so queries contain no explicit time filter.
// Platform spans (invoke_agent) are emitted by the Foundry service role "agentsv2"; container and tool
// spans use the agent name and "<agent>-tools" roles. The platform span is the source of truth for
// availability because it also records failures where the container never started.
var platform = '''
AppRequests
| where AppRoleName == "agentsv2" and Name == "invoke_agent"
| where tostring(Properties["gen_ai.agent.name"]) == "{AgentName}"
| extend Ver = tostring(Properties["gen_ai.agent.version"])
| where Ver in ({Version})
'''

var externalFilter = '''
| where DependencyType == "HTTP"
| where not(Target endswith ".services.ai.azure.com" or Target endswith ".openai.azure.com" or Target has "agent365" or Target has "login.microsoftonline")
| where not(Target == "learn.microsoft.com" and ResultCode == "405")
'''

var panels = [
  {
    title: '1. Service health - is the agent healthy now?'
    visualization: 'tiles'
    query: concat('let p =\n', platform, ''';
union
  (p | summarize Value = todouble(count()) | extend Metric = "Requests", Ord = 1),
  (p | summarize Value = round(100.0 * countif(Success == true) / max_of(count(), 1), 1) | extend Metric = "Task success %", Ord = 2),
  (p | summarize Value = round(100.0 * countif(Success == false) / max_of(count(), 1), 1) | extend Metric = "Failure %", Ord = 3),
  (p | summarize Value = round(percentile(DurationMs, 95) / 1000.0, 1) | extend Metric = "P95 latency (s)", Ord = 4)
| order by Ord asc
| project Metric, Value
''')
    size: 4
  }
  {
    title: '2. Requests and failures over time'
    visualization: 'timechart'
    query: concat(platform, '''
| summarize Requests = count(), Failures = countif(Success == false) by bin(TimeGenerated, 5m)
''')
    size: 0
  }
  {
    title: '3. P95 latency by version - a version change shows as a new series'
    visualization: 'timechart'
    query: concat(platform, '''
| summarize P95Seconds = round(percentile(DurationMs, 95) / 1000.0, 1) by bin(TimeGenerated, 5m), Version = Ver
''')
    size: 0
  }
  {
    title: '4. Version rollout markers - first and last seen per version (change check)'
    visualization: 'table'
    query: concat(platform, '''
| summarize FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated), Requests = count(),
    Failures = countif(Success == false), P95Ms = round(percentile(DurationMs, 95), 0) by Version = Ver
| extend FailurePct = round(100.0 * Failures / Requests, 1)
| order by FirstSeen desc
''')
    size: 0
  }
  {
    title: '5. Top failing operations - tools, model calls, and external dependencies'
    visualization: 'table'
    query: concat('''
AppDependencies
| where AppRoleName in ("{AgentName}", "{AgentName}-tools")
| where AppVersion in ({Version})
| where Name startswith "tool." or Name startswith "chat " or Name startswith "execute_tool" or DependencyType == "HTTP"
| where not(DependencyType == "HTTP" and (Target endswith ".services.ai.azure.com" or Target endswith ".openai.azure.com" or Target has "agent365" or Target has "login.microsoftonline"))
| where not(Target == "learn.microsoft.com" and ResultCode == "405")
| extend ErrorType = tostring(Properties["error.type"])
| summarize Calls = count(), Failures = countif(Success == false), P95Ms = round(percentile(DurationMs, 95), 0)
    by Operation = iff(DependencyType == "HTTP", strcat("HTTP ", Target), Name), ErrorType
| extend FailurePct = round(100.0 * Failures / Calls, 1),
    Classification = iff(ErrorType in ("invalid_user_id", "invalid_query"), "Expected controlled error", "Investigate")
| where Failures > 0
| top 15 by Failures desc
''')
    size: 0
  }
  {
    title: '6. Tool quality - calls, failures, and tail latency per tool'
    visualization: 'table'
    query: '''
AppDependencies
| where AppRoleName == "{AgentName}-tools" and Name startswith "tool."
| where AppVersion in ({Version})
| extend Tool = tostring(Properties["gen_ai.tool.name"]), ErrorType = tostring(Properties["error.type"])
| summarize Calls = count(), Failures = countif(Success == false),
    Unexpected = countif(Success == false and ErrorType !in ("invalid_user_id", "invalid_query")),
    P50Ms = round(percentile(DurationMs, 50), 0), P95Ms = round(percentile(DurationMs, 95), 0) by Tool
| extend UnexpectedPct = round(100.0 * Unexpected / Calls, 1)
| order by Tool asc
'''
    size: 0
  }
  {
    title: '7. Cold start versus warm - where the time goes'
    visualization: 'table'
    query: concat(platform, '''
| extend Start = tostring(Properties["hosted_agent.latency.start_type"]),
    InfraMs = tolong(Properties["hosted_agent.latency.infra_setup_ms"]),
    ReadinessMs = tolong(Properties["hosted_agent.latency.container_readiness_ms"]),
    ContainerMs = tolong(Properties["hosted_agent.latency.container_response_ms"])
| summarize Requests = count(), P50TotalMs = round(percentile(DurationMs, 50), 0), P95TotalMs = round(percentile(DurationMs, 95), 0),
    AvgInfraMs = round(avg(InfraMs), 0), AvgReadinessMs = round(avg(ReadinessMs), 0), AvgContainerMs = round(avg(ContainerMs), 0) by StartType = Start
''')
    size: 0
  }
  {
    title: '8. Model usage and cost signals - tokens by version'
    visualization: 'table'
    query: '''
AppDependencies
| where AppRoleName == "{AgentName}" and Name startswith "chat "
| where AppVersion in ({Version})
| extend InputTokens = tolong(Properties["gen_ai.usage.input_tokens"]), OutputTokens = tolong(Properties["gen_ai.usage.output_tokens"]),
    Model = tostring(Properties["gen_ai.request.model"])
| summarize ModelCalls = count(), InputTokens = sum(InputTokens), OutputTokens = sum(OutputTokens),
    P95Ms = round(percentile(DurationMs, 95), 0) by Version = AppVersion, Model
| order by Version desc
'''
    size: 0
  }
  {
    title: '9. External dependency health - Foundry platform probes and benign MCP 405 rows excluded'
    visualization: 'table'
    query: concat('''
AppDependencies
| where AppRoleName == "{AgentName}"
| where AppVersion in ({Version})
''', externalFilter, '''
| summarize Calls = count(), Failures = countif(Success == false), P95Ms = round(percentile(DurationMs, 95), 0) by Target
| extend FailurePct = round(100.0 * Failures / Calls, 1)
| order by Failures desc
''')
    size: 0
  }
  {
    title: '10. Trace pivot - copy OperationId into Logs, or open the transaction view'
    visualization: 'table'
    query: concat(platform, '''
| project TimeGenerated, OperationId, Version = Ver, DurationMs = round(DurationMs, 0), Success, ResultCode,
    ConversationId = tostring(Properties["gen_ai.conversation.id"]), StartType = tostring(Properties["hosted_agent.latency.start_type"])
| top 50 by TimeGenerated desc
''')
    size: 0
  }
]

var queryItems = [for (panel, index) in panels: {
  type: 3
  name: 'ops-query-${index}'
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
    size: panel.size
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
# Hosted Agent - operations

**Audience:** on-call responder and service owner. **Decision:** do we need to act, and where do we look first?

Decision rail: **1 Declare?** impact plus failure or latency breach. **2 Scope?** service, version, time range. **3 Pivot?** OperationId or conversation ID (panel 10). **4 Act?** owner, runbook, and the rollback script.

Design test: if a tile changes, the next decision should be obvious. Platform `invoke_agent` spans are the availability source of truth because they also capture failures where the container never started. Expected controlled tool errors and benign Foundry or MCP probe rows are excluded from failure views. Task success is a platform-outcome proxy; it is not an evaluation score (evaluators arrive in Session 3). Content capture is on for synthetic data only.
'''

var parameterItem = {
  type: 9
  name: 'parameters'
  content: {
    version: 'KqlParameterItem/1.0'
    parameters: [
      {
        id: 'b1a3f6a0-7c1e-4b43-9d51-6f0d5a1a0001'
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
        id: 'b1a3f6a0-7c1e-4b43-9d51-6f0d5a1a0002'
        version: 'KqlParameterItem/1.0'
        name: 'AgentName'
        label: 'Agent (service)'
        type: 1
        isRequired: true
        value: agentName
      }
      {
        id: 'b1a3f6a0-7c1e-4b43-9d51-6f0d5a1a0003'
        version: 'KqlParameterItem/1.0'
        name: 'Version'
        label: 'Version'
        type: 2
        isRequired: true
        multiSelect: true
        quote: '\''
        delimiter: ','
        query: 'AppRequests\n| where AppRoleName == "agentsv2" and Name == "invoke_agent"\n| where tostring(Properties["gen_ai.agent.name"]) == "{AgentName}"\n| extend Ver = tostring(Properties["gen_ai.agent.version"])\n| where isnotempty(Ver)\n| summarize by Ver\n| order by toint(Ver) desc'
        typeSettings: {
          additionalResourceOptions: [
            'value::all'
          ]
          showDefault: false
        }
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        crossComponentResources: [
          workspaceId
        ]
        timeContext: {
          durationMs: 2592000000
        }
        value: [
          'value::all'
        ]
      }
    ]
    style: 'pills'
    queryType: 0
    resourceType: 'microsoft.operationalinsights/workspaces'
  }
}

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(applicationInsightsId, 'hosted-agent-operations')
  location: location
  kind: 'shared'
  tags: tags
  properties: {
    displayName: 'Hosted Agent - operations'
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
        parameterItem
      ], queryItems)
    })
  }
}

output workbookId string = workbook.id
