param(
    [string] $BaseUrl = 'http://localhost:8088'
)

$ErrorActionPreference = 'Stop'

$cases = @(
    'Get details for user 1.',
    'Show incomplete tasks for user 1.',
    'Show posts from user 1.',
    'Use Microsoft Learn to explain Azure managed identity.',
    'Show user 1 details and incomplete tasks.',
    'Show user 1 details and use Microsoft Learn to explain managed identity.'
)

foreach ($prompt in $cases) {
    Write-Host "`n> $prompt" -ForegroundColor Cyan
    $body = @{ input = $prompt; stream = $false; store = $false } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/responses" `
        -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
    $message = $response.output | Where-Object type -eq 'message' | Select-Object -Last 1
    $text = $message.content | Where-Object type -eq 'output_text' | Select-Object -ExpandProperty text
    $tools = $response.output | Where-Object type -eq 'function_call' | Select-Object -ExpandProperty name
    Write-Host ($text -join "`n")
    Write-Host "Tools: $($tools -join ', ')" -ForegroundColor DarkGray
}
