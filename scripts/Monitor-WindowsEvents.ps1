param(
    [string]$ConfigPath = ".\\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $ConfigPath)) {
    throw "Config file not found at '$ConfigPath'. Copy config.sample.json to config.json and update it."
}

$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($config.openai_api_key)) {
    throw "openai_api_key is empty in config file."
}

$hoursBack = if ($config.hours_back) { [int]$config.hours_back } else { 1 }
$maxEvents = if ($config.max_events) { [int]$config.max_events } else { 200 }
$temperature = if ($config.temperature) { [double]$config.temperature } else { 0.2 }
$model = if ($config.model) { [string]$config.model } else { "gpt-4.1-mini" }

$logNames = @('System', 'Application')
if ($config.log_names -and $config.log_names.Count -gt 0) {
    $logNames = @($config.log_names)
}

$startTime = (Get-Date).AddHours(-$hoursBack)

$events = Get-WinEvent -FilterHashtable @{
    LogName = $logNames
    StartTime = $startTime
    Level = @(1, 2)
} -MaxEvents $maxEvents |
    Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, MachineName, LogName, Message

if (-not $events -or $events.Count -eq 0) {
    Write-Host "No Critical/Error events found in the last $hoursBack hour(s)."
    exit 0
}

$lines = foreach ($event in $events) {
    @(
        "Timestamp: $($event.TimeCreated.ToString('o'))"
        "Severity: $($event.LevelDisplayName)"
        "Source: $($event.ProviderName)"
        "EventId: $($event.Id)"
        "Machine: $($event.MachineName)"
        "Log: $($event.LogName)"
        "Message: $($event.Message -replace '\\s+', ' ')"
        "---"
    ) -join "`n"
}

$logPayload = $lines -join "`n"

$analysisPrompt = @"
You are a Windows server reliability assistant.
Analyze these Critical/Error Windows events from the last $hoursBack hour(s).

Return:
1) Top incidents grouped by event source + event id.
2) Suspected root causes.
3) Immediate actions to take now.
4) A short priority list (P1/P2/P3).
5) Mention if any events look repetitive or correlated.

Keep response concise and actionable.
"@

$body = @{
    model = $model
    temperature = $temperature
    input = @(
        @{
            role = "system"
            content = @(
                @{
                    type = "text"
                    text = $analysisPrompt
                }
            )
        },
        @{
            role = "user"
            content = @(
                @{
                    type = "text"
                    text = $logPayload
                }
            )
        }
    )
} | ConvertTo-Json -Depth 10

$headers = @{
    "Authorization" = "Bearer $($config.openai_api_key)"
    "Content-Type" = "application/json"
}

$response = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -Body $body

$analysisText = $response.output_text
if ([string]::IsNullOrWhiteSpace($analysisText)) {
    $analysisText = "No output_text returned. Raw response:`n$($response | ConvertTo-Json -Depth 10)"
}

$outputDir = if ($config.output_directory) { [string]$config.output_directory } else { ".\\output" }
if (-not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$eventFile = Join-Path $outputDir "events-$timestamp.txt"
$analysisFile = Join-Path $outputDir "analysis-$timestamp.md"

$logPayload | Out-File -FilePath $eventFile -Encoding UTF8
$analysisText | Out-File -FilePath $analysisFile -Encoding UTF8

Write-Host "Saved events to: $eventFile"
Write-Host "Saved analysis to: $analysisFile"
Write-Host "\n=== ChatGPT Analysis ===\n"
Write-Host $analysisText
