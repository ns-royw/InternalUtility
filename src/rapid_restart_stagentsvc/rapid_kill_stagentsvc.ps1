#Requires -RunAsAdministrator
# =====================================================================
# ENG-1108299  SSL ctx crash repro + fix verification script
#   Loop: kill stAgentSvc -> poll every 1s until the watchdog
#   (stAgentSvcMon) restarts it -> let it run 31s -> kill again.
#   Repeat up to 1000 times. Stops early if a crash dump is produced.
# =====================================================================
$ErrorActionPreference = 'Continue'

# ========= Configurable parameters =========
$AgentSvc         = 'stAgentSvc'                             # main service name
$WatchdogSvc      = 'stWatchdog'                             # watchdog service name (process is stAgentSvcMon.exe)
$AgentImage       = 'stAgentSvc.exe'                         # main service process image
$AgentProcName    = 'stAgentSvc'                             # for Get-Process (without .exe)
$LogDir           = 'C:\ProgramData\netskope\stagent\Logs'  # dump and log directory
$MaxCycles        = 1000                                     # number of kill cycles
$RunAfterStartSec = 61                                       # how long to let the agent run after it restarts, before killing again
$RestartWaitSec   = 120                                      # safety cap for waiting for the watchdog restart (seconds)
# ===========================================

function Log([string]$msg, [string]$color = 'Gray') {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -ForegroundColor $color
}

function Get-Dumps {
    if (Test-Path $LogDir) {
        return @(Get-ChildItem -Path $LogDir -Filter '*.dmp' -File -ErrorAction SilentlyContinue)
    }
    return @()
}

function Test-SvcRunning([string]$name) {
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    return ($null -ne $s -and $s.Status -eq 'Running')
}

function Test-AgentProc {
    return ($null -ne (Get-Process -Name $AgentProcName -ErrorAction SilentlyContinue))
}

# Poll every second until the agent process is back up.
# Returns 'DUMP' (dump found), 'UP' (process detected), or 'TIMEOUT'.
function Wait-AgentRestart([int]$timeoutSec) {
    for ($i = 0; $i -lt $timeoutSec; $i++) {
        if ((Get-Dumps).Count -gt 0) { return 'DUMP' }
        if (Test-AgentProc)          { return 'UP'   }
        Start-Sleep -Seconds 1
    }
    return 'TIMEOUT'
}

# Sleep for N seconds, checking for a dump each second.
# Returns 'DUMP' if a dump appears, otherwise 'DONE'.
function Wait-Seconds-CheckDump([int]$sec) {
    for ($i = 0; $i -lt $sec; $i++) {
        if ((Get-Dumps).Count -gt 0) { return 'DUMP' }
        Start-Sleep -Seconds 1
    }
    return 'DONE'
}

function Get-NewestLog {
    $logs = Get-ChildItem -Path $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    if ($logs) { return $logs[0].FullName }
    return $null
}

# Check handoff order: PASS = SYN_TUNNEL sent before handoff; FAIL = handoff before SYN_TUNNEL (old race).
function Test-HandoverOrder([string]$logPath) {
    if (-not $logPath -or -not (Test-Path $logPath)) {
        Log "handover check: log file not found" 'Yellow'; return
    }
    $pat  = 'SSL connected to the|sending client ver|Inserting sock \d+ to map'
    $hits = Select-String -Path $logPath -Pattern $pat -ErrorAction SilentlyContinue
    if (-not $hits) { Log "handover check: markers not found in log (ensure log level is at least info)" 'Yellow'; return }

    $state = 'idle'   # idle -> connected -> synsent
    $pass = 0; $fail = 0
    foreach ($h in $hits) {
        $line = $h.Line
        if     ($line -match 'SSL connected to the')      { $state = 'connected' }
        elseif ($line -match 'sending client ver')        { if ($state -eq 'connected') { $state = 'synsent' } }
        elseif ($line -match 'Inserting sock \d+ to map') {
            if ($state -eq 'synsent') {
                $pass++                                   # correct: SYN_TUNNEL sent, then handoff
            } else {
                $fail++                                   # wrong: handoff before SYN_TUNNEL was sent
                Log ("  [FAIL] handoff before SYN_TUNNEL (old order): {0}" -f $line.Trim()) 'Red'
            }
            $state = 'idle'
        }
    }
    $col = if ($fail -eq 0) { 'Green' } else { 'Red' }
    Log ("handover order @ {0} => PASS={1}, FAIL={2}" -f (Split-Path $logPath -Leaf), $pass, $fail) $col

    $dbg = Select-String -Path $logPath -Pattern 'handover SSLClient to nsssl:wait\(\) done' -ErrorAction SilentlyContinue
    if ($dbg) { Log ("  (debug) handover marker seen {0} time(s)" -f $dbg.Count) 'DarkGray' }
    return $fail
}

# ---------- Step 1: stop stAgentSvc ----------
Log "Step 1: stopping $AgentSvc ..." 'Cyan'
Stop-Service -Name $AgentSvc -Force -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 30 -and (Test-AgentProc); $i++) { Start-Sleep -Seconds 1 }
if (Test-AgentProc) { taskkill /F /IM $AgentImage 2>$null | Out-Null; Start-Sleep -Seconds 2 }
Log "  $AgentSvc stopped" 'Green'

# ---------- Step 2: clean the log directory ----------
Log "Step 2: cleaning $LogDir ..." 'Cyan'
if (Test-Path $LogDir) {
    Get-ChildItem -Path $LogDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Log "  log directory cleared" 'Green'
} else {
    Log "  log directory does not exist; it will be created after the service starts" 'Yellow'
}

# ---------- Step 3: start stAgentSvc ----------
Log "Step 3: starting $AgentSvc ..." 'Cyan'
Start-Service -Name $AgentSvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# ---------- Step 4: verify both services are running ----------
Log "Step 4: checking service status ..." 'Cyan'
$agentUp = Test-SvcRunning $AgentSvc
$wdUp    = Test-SvcRunning $WatchdogSvc
Log ("  {0} = {1}" -f $AgentSvc,    $(if ($agentUp) {'Running'} else {'NOT running'})) $(if ($agentUp) {'Green'} else {'Red'})
Log ("  {0} = {1}" -f $WatchdogSvc, $(if ($wdUp)    {'Running'} else {'NOT running'})) $(if ($wdUp)    {'Green'} else {'Red'})
if (-not $agentUp -or -not $wdUp) {
    Log "Both services are not running. Verify service names (watchdog may be stWatchdog / stAgentSvcMon) and retry." 'Red'
    return
}

# ---------- Steps 5/6/7: kill -> poll 1s for restart -> run 31s -> kill again ----------
Log "Steps 5/6/7: kill $AgentImage, poll 1s until restart, run ${RunAfterStartSec}s, repeat (up to $MaxCycles cycles) ..." 'Cyan'
$found = $false
$totalFail = 0
for ($cycle = 1; $cycle -le $MaxCycles; $cycle++) {

    # Step 5: kill stAgentSvc (if running)
    if (Test-AgentProc) {
        Log ("Cycle {0}: taskkill {1}" -f $cycle, $AgentImage)
        taskkill /F /IM $AgentImage 2>$null | Out-Null
    } else {
        Log ("Cycle {0}: agent not currently running; nothing to kill" -f $cycle) 'Yellow'
    }

    # Step 6: poll every second until the watchdog restarts the agent (checking dumps each second)
    $r = Wait-AgentRestart $RestartWaitSec
    if ($r -eq 'DUMP')    { $found = $true; break }
    if ($r -eq 'TIMEOUT') {
        Log ("Cycle {0}: watchdog did not restart the agent within {1}s (check $WatchdogSvc)" -f $cycle, $RestartWaitSec) 'Yellow'
        continue
    }
    Log ("Cycle {0}: watchdog restarted $AgentImage" -f $cycle) 'Green'

    # Step 7: let it run for 31s after startup, checking for a dump each second
    if ((Wait-Seconds-CheckDump $RunAfterStartSec) -eq 'DUMP') { $found = $true; break }

    # Verify handoff order for this connection cycle before killing again
    $f = Test-HandoverOrder (Get-NewestLog)
    if ($f -is [int]) { $totalFail += $f }
}

# ---------- Results ----------
Log "=== Test finished ===" 'Cyan'
$dumps = Get-Dumps
if ($dumps.Count -gt 0) {
    Log ("Crash dump detected, test stopped! {0} dump(s):" -f $dumps.Count) 'Red'
    $dumps | ForEach-Object { Log ("  {0}  ({1:N0} bytes, {2})" -f $_.FullName, $_.Length, $_.LastWriteTime) 'Red' }
} else {
    Log ("Completed {0} cycle(s) with no dump produced." -f ($cycle - 1)) 'Green'
}
$col = if ($totalFail -eq 0) { 'Green' } else { 'Red' }
Log ("Total handoff-order FAIL count = {0}" -f $totalFail) $col
Log "=== Final handover-order verification (newest log) ===" 'Cyan'
Test-HandoverOrder (Get-NewestLog) | Out-Null