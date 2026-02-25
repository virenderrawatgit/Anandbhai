# Windows Server Log Monitor + ChatGPT Analysis

This project checks Windows Event Logs every hour (or on demand), sends **Critical/Error** events to ChatGPT, and saves a concise incident analysis.

## What it does
- Reads Windows event logs (`System`, `Application` by default).
- Filters events with severity:
  - `Critical` (Level 1)
  - `Error` (Level 2)
- Sends those events to OpenAI for summarization + action plan.
- Stores both raw events and AI analysis in an output folder.

## Files
- `scripts/Monitor-WindowsEvents.ps1` — main PowerShell script.
- `config.sample.json` — configuration template.

## Setup

1. Copy config file:
   ```powershell
   Copy-Item .\config.sample.json .\config.json
   ```

2. Edit `config.json` and set your API key:
   ```json
   {
     "openai_api_key": "YOUR_OPENAI_API_KEY"
   }
   ```

3. Run script manually:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Monitor-WindowsEvents.ps1 -ConfigPath .\config.json
   ```

## Schedule every 1 hour (Task Scheduler)

Run this once in elevated PowerShell:

```powershell
$taskName = "WindowsLogToChatGPTHourly"
$repoPath = "C:\path\to\Anandbhai"
$scriptPath = Join-Path $repoPath "scripts\Monitor-WindowsEvents.ps1"
$configPath = Join-Path $repoPath "config.json"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ConfigPath `"$configPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description "Send Critical/Error Windows events to ChatGPT every hour"
```

## Notes
- Keep your API key secure; do not commit `config.json`.
- If you want additional logs, add them in `log_names` (e.g., `Security`, custom app logs).
- Output files are written to `output_directory` from config.
