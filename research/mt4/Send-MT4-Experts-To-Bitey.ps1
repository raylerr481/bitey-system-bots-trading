param(
  [Parameter(Mandatory = $true)]
  [string]$TerminalDataPath,
  [string]$ApiUrl = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/signal-event",
  [int]$PollMilliseconds = 500
)

$ErrorActionPreference = "Stop"
$logsDir = Join-Path $TerminalDataPath "MQL4\Logs"
if (-not (Test-Path -LiteralPath $logsDir -PathType Container)) {
  throw "No existe la carpeta de logs de MT4: $logsDir. Usa la ruta de Archivo > Abrir carpeta de datos."
}
if (-not $ApiUrl.StartsWith("https://")) { throw "ApiUrl debe usar HTTPS." }

# Define SBT_MT4_TOKEN in the PowerShell process environment when the backend requires it.
# Never put a GitHub PAT, database key, or account password in this script.
$token = [Environment]::GetEnvironmentVariable("SBT_MT4_TOKEN")
$spoolPath = Join-Path $TerminalDataPath "SBT_Experts_pending.jsonl"
$collectorLog = Join-Path $TerminalDataPath "SBT_Experts_Collector.log"
$activePath = ""
$stream = $null
$reader = $null
$lastSpoolAttempt = [DateTime]::MinValue

function Write-CollectorLog([string]$message) {
  $stamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
  Add-Content -LiteralPath $collectorLog -Encoding UTF8 -Value "$stamp $message"
}

function Protect-LogLine([string]$line) {
  $safe = $line
  $safe = [regex]::Replace($safe, '(?i)(password|passwd|token|authorization|api[_-]?key)\s*[:=]\s*[^,\s|;]+', '$1=[REDACTED]')
  $safe = [regex]::Replace($safe, '(?i)(login|account)\s*[:=]\s*\d{4,}', '$1=[REDACTED]')
  $safe = [regex]::Replace($safe, '(?i)(account|login)\s*#\s*\d{4,}', '$1#=[REDACTED]')
  return $safe
}

function Convert-LogLineToEvent([string]$line, [string]$sourceFile) {
  $safe = Protect-LogLine $line
  $symbol = "MT4_TERMINAL"
  $timeframe = "UNKNOWN"
  $decision = "UNKNOWN"
  $brokerTime = $null

  if ($safe -match '^\s*(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)') {
    $brokerTime = $Matches[1]
  }
  if ($safe -match '(?<sym>[A-Za-z0-9._-]+),(?<tf>MN1|W1|D1|H4|H1|M30|M15|M5|M1)\s*:') {
    $symbol = $Matches['sym']
    $timeframe = $Matches['tf']
  }
  if ($safe -match '(?i)\bdecision\s*=\s*(BUY|SELL|WAIT|BLOCK|SUCCESS|FAIL)\b') {
    $decision = $Matches[1].ToUpperInvariant()
  }

  $eventId = [guid]::NewGuid().ToString("N")
  return [ordered]@{
    schema_version = "1.0"
    event_id = $eventId
    event_time_utc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    broker_time = $brokerTime
    event_type = "experts_log_line"
    symbol = $symbol
    canonical_symbol = $null
    timeframe = $timeframe
    bar_time = $null
    ea_version = "mt4-experts-collector-1.0"
    source_commit = "research/v1.99-telemetry-and-evidence"
    variant_id = $null
    decision = $decision
    reason = "MT4_EXPERTS_LOG"
    risk_policy = "ALL_ACCOUNTS_REAL_RISK"
    spread_points = $null
    atr = $null
    intended_risk_usd = $null
    effective_capital_usd = 500.0
    stop_distance = $null
    target_distance = $null
    evidence_type = "MT4_EXPERTS_LOG_LINE"
    models = @()
    training_metrics = $null
    holdout_metrics = $null
    order = $null
    notes = $safe
    source_log = [IO.Path]::GetFileName($sourceFile)
  }
}

function Send-Event($event) {
  $json = ConvertTo-Json -InputObject $event -Depth 8 -Compress
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($token)) { $headers["X-MT4-Token"] = $token }
  try {
    $null = Invoke-RestMethod -Uri $ApiUrl -Method Post -ContentType "application/json; charset=utf-8" -Headers $headers -Body $json -TimeoutSec 8
    Write-CollectorLog ("SENT event_id=" + $event.event_id + " symbol=" + $event.symbol + " decision=" + $event.decision)
    return $true
  } catch {
    Add-Content -LiteralPath $spoolPath -Encoding UTF8 -Value $json
    Write-CollectorLog ("QUEUED event_id=" + $event.event_id + " error=" + $_.Exception.Message)
    return $false
  }
}

function Flush-Spool {
  if (-not (Test-Path -LiteralPath $spoolPath)) { return }
  $pending = @(Get-Content -LiteralPath $spoolPath -Encoding UTF8)
  if ($pending.Count -eq 0) { return }
  $remaining = New-Object System.Collections.Generic.List[string]
  foreach ($item in $pending) {
    try {
      $event = ConvertFrom-Json -InputObject $item
      $headers = @{}
      if (-not [string]::IsNullOrWhiteSpace($token)) { $headers["X-MT4-Token"] = $token }
      $null = Invoke-RestMethod -Uri $ApiUrl -Method Post -ContentType "application/json; charset=utf-8" -Headers $headers -Body $item -TimeoutSec 8
      Write-CollectorLog ("RETRIED event_id=" + $event.event_id)
    } catch {
      $remaining.Add($item)
    }
  }
  if ($remaining.Count -eq 0) {
    Remove-Item -LiteralPath $spoolPath -Force
  } else {
    Set-Content -LiteralPath $spoolPath -Encoding UTF8 -Value $remaining
  }
}

Write-CollectorLog "START logsDir=$logsDir endpoint=$ApiUrl"
Write-Host "Bitey SBT Experts collector activo."
Write-Host "Logs: $logsDir"
Write-Host "Endpoint: $ApiUrl"
Write-Host "Solo lee nuevas líneas; no modifica MT4 ni envía órdenes."
Write-Host "Ctrl+C para detener."

try {
  while ($true) {
    $latest = Get-ChildItem -LiteralPath $logsDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($null -eq $latest) {
      Start-Sleep -Milliseconds $PollMilliseconds
      continue
    }

    if ($latest.FullName -ne $activePath) {
      if ($null -ne $reader) { $reader.Dispose(); $reader = $null }
      if ($null -ne $stream) { $stream.Dispose(); $stream = $null }
      $activePath = $latest.FullName
      $stream = [System.IO.File]::Open($activePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::Default, $true)
      $stream.Position = $stream.Length
      $reader.DiscardBufferedData()
      Write-CollectorLog "FOLLOW file=$activePath mode=TAIL_NEW_LINES_ONLY"
      Write-Host "Siguiendo $activePath"
    }

    while ($null -ne ($line = $reader.ReadLine())) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $event = Convert-LogLineToEvent -line $line -sourceFile $activePath
      Send-Event $event
      Start-Sleep -Milliseconds 100
    }

    if (([DateTime]::UtcNow - $lastSpoolAttempt).TotalSeconds -ge 30) {
      Flush-Spool
      $lastSpoolAttempt = [DateTime]::UtcNow
    }
    Start-Sleep -Milliseconds $PollMilliseconds
  }
} finally {
  if ($null -ne $reader) { $reader.Dispose() }
  if ($null -ne $stream) { $stream.Dispose() }
  Write-CollectorLog "STOP"
}
