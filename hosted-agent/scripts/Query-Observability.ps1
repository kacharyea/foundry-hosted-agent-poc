[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ResourceGroup,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $WorkspaceName,
    [string] $TraceId = ''
)

$ErrorActionPreference = 'Stop'
$filter = if ([string]::IsNullOrWhiteSpace($TraceId)) {
    'TimeGenerated > ago(2h)'
} else {
    $safeTrace = $TraceId -replace '[^a-fA-F0-9]', ''
    if ($safeTrace.Length -ne 32) { throw 'TraceId must contain exactly 32 hexadecimal characters.' }
    "OperationId == '$safeTrace'"
}

$workspaceId = az monitor log-analytics workspace show --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName --query customerId -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($workspaceId)) {
    throw "Could not resolve Log Analytics workspace '$WorkspaceName'."
}

Write-Host 'Requests' -ForegroundColor Cyan
az monitor log-analytics query --workspace $workspaceId `
    --analytics-query "AppRequests | where $filter | where Name != 'GET /readiness' | project TimeGenerated,Name,ResultCode,Success,DurationMs,OperationId,AppRoleName,AppVersion | order by TimeGenerated desc" -o table
if ($LASTEXITCODE -ne 0) { throw 'Workspace request query failed.' }

Write-Host "`nDependencies and tool/model calls" -ForegroundColor Cyan
az monitor log-analytics query --workspace $workspaceId `
    --analytics-query "AppDependencies | where $filter | where Name startswith 'invoke_agent' or Name startswith 'chat ' or Name startswith 'execute_tool' or Name startswith 'tool.' or Target in ('jsonplaceholder.typicode.com','learn.microsoft.com') | project TimeGenerated,Name,Target,ResultCode,Success,DurationMs,OperationId,ParentId,AppRoleName,AppVersion | order by TimeGenerated asc" -o table
if ($LASTEXITCODE -ne 0) { throw 'Workspace dependency query failed.' }

Write-Host "`nFailed requests and dependencies" -ForegroundColor Cyan
az monitor log-analytics query --workspace $workspaceId `
    --analytics-query "union AppRequests, AppDependencies | where $filter | where Success == false | extend ErrorType=tostring(Properties['error.type']) | project TimeGenerated,Type,Name,Target=column_ifexists('Target',''),ResultCode,ErrorType,DurationMs,OperationId,AppRoleName | order by TimeGenerated desc" -o table
if ($LASTEXITCODE -ne 0) { throw 'Workspace failure query failed.' }

Write-Host "`nExceptions" -ForegroundColor Cyan
az monitor log-analytics query --workspace $workspaceId `
    --analytics-query "AppExceptions | where $filter | project TimeGenerated,ExceptionType,OuterMessage,OperationId,AppRoleName | order by TimeGenerated desc" -o table
if ($LASTEXITCODE -ne 0) { throw 'Workspace exception query failed.' }
