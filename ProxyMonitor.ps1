[CmdletBinding()]
param(
    [string]$LocalScriptPath = 'C:\install\ProxyMonitor\ProxyMonitorService.ps1',
    [string]$NetworkPath
)

$ErrorActionPreference = 'Stop'
$localDir = Split-Path -Path $LocalScriptPath -Parent
$logFile = Join-Path -Path $localDir -ChildPath 'Installation.log'

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')] [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $colors = @{ INFO = 'Green'; WARNING = 'Yellow'; ERROR = 'Red' }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
    try {
        "$timestamp - [$Level] $Message" | Out-File -Append -FilePath $logFile -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Host "[$timestamp] [WARNING] Installations-Log konnte nicht geschrieben werden: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Directory {
    param([Parameter(Mandatory)] [string]$Path)

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Verzeichnis erstellt: $Path"
        }
        else {
            Write-Log "Verzeichnis existiert: $Path"
        }
        return $true
    }
    catch {
        Write-Log "Fehler beim Erstellen von $Path`: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Test-NetworkPath {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Netzwerkpfad nicht erreichbar: $Path" 'ERROR'
        return $false
    }
    Write-Log 'Netzwerkpfad OK'
    return $true
}

function Get-NssmPath {
    $command = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $knownPaths = @(
        "$env:ChocolateyInstall\bin\nssm.exe",
        "$env:ProgramData\chocolatey\bin\nssm.exe"
    )
    return $knownPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Install-NSSM {
    Write-Log 'Pruefe, ob NSSM bereits installiert ist...'
    $nssmPath = Get-NssmPath
    if ($nssmPath) {
        Write-Log "NSSM bereits installiert: $nssmPath"
        return $nssmPath
    }

    $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
    if (-not $choco) {
        Write-Log 'Chocolatey nicht gefunden. NSSM muss installiert werden.' 'ERROR'
        return $null
    }

    try {
        Write-Log 'Starte Chocolatey-Installation von NSSM...' 'WARNING'
        & $choco.Source install nssm --yes --no-progress
        if ($LASTEXITCODE -ne 0) {
            throw "Chocolatey beendet mit Exit-Code $LASTEXITCODE"
        }

        $nssmPath = Get-NssmPath
        if (-not $nssmPath) {
            throw 'NSSM wurde installiert, ist aber nicht auffindbar.'
        }
        Write-Log "NSSM erfolgreich installiert: $nssmPath"
        return $nssmPath
    }
    catch {
        Write-Log "Fehler bei NSSM-Installation: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

function Create-ProxyMonitorScript {
    param([Parameter(Mandatory)] [string]$Path)

    $script = @'
$logPath = 'C:\install\ProxyMonitor\ProxyMonitor.log'
$checkInterval = 30

function Write-Log {
    param([Parameter(Mandatory)] [string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try {
        "$timestamp - $Message" | Out-File -Append -FilePath $logPath -Encoding UTF8 -ErrorAction Stop
    }
    catch {
    }
}

if (-not (Test-Path -LiteralPath (Split-Path -Path $logPath -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path -Path $logPath -Parent) -Force | Out-Null
}

function Disable-Proxy {
    param(
        [Parameter(Mandatory)] [string]$RegistryPath,
        [Parameter(Mandatory)] [string]$Scope
    )

    try {
        $settings = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
        if ($settings.ProxyEnable -eq 1) {
            Write-Log "$Scope-Proxy erkannt: $($settings.ProxyServer)"
            Set-ItemProperty -Path $RegistryPath -Name ProxyEnable -Value 0 -Force
            Write-Log "$Scope-Proxy deaktiviert"
        }
    }
    catch {
        Write-Log "Fehler bei $Scope-Proxy: $($_.Exception.Message)"
    }
}

Write-Log 'ProxyMonitor gestartet'
while ($true) {
    Disable-Proxy -RegistryPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Scope 'System'

    Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
        ForEach-Object {
            $userSettingsPath = "Registry::$($_.Name)\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
            Disable-Proxy -RegistryPath $userSettingsPath -Scope "Benutzer $($_.PSChildName)"
        }

    Start-Sleep -Seconds $checkInterval
}
'@

    $script = $script.Replace('C:\install\ProxyMonitor', $localDir)

    try {
        $parent = Split-Path -Path $Path -Parent
        if (-not (Ensure-Directory -Path $parent)) {
            return $false
        }
        Set-Content -LiteralPath $Path -Value $script -Encoding UTF8 -Force
        Write-Log "Skript erstellt: $Path"
        return $true
    }
    catch {
        Write-Log "Fehler beim Erstellen des Skripts: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Install-ProxyMonitorService {
    param(
        [Parameter(Mandatory)] [string]$ScriptPath,
        [Parameter(Mandatory)] [string]$NssmPath
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        Write-Log "Skript-Datei nicht gefunden: $ScriptPath" 'ERROR'
        return $false
    }

    $service = Get-Service -Name ProxyMonitor -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log 'Dienst existiert bereits und wird entfernt...' 'WARNING'
        try {
            & $NssmPath stop ProxyMonitor | Out-Null
            $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
            & $NssmPath remove ProxyMonitor confirm | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "NSSM konnte den vorhandenen Dienst nicht entfernen (Exit-Code $LASTEXITCODE)."
            }
            Write-Log 'Alte Version entfernt'
        }
        catch {
            Write-Log "Fehler beim Entfernen des Dienstes: $($_.Exception.Message)" 'ERROR'
            return $false
        }
    }

    try {
        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $psArgs = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$ScriptPath`""
        & $NssmPath install ProxyMonitor $psExe $psArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "NSSM install fehlgeschlagen (Exit-Code $LASTEXITCODE)." }

        & $NssmPath set ProxyMonitor AppDirectory $localDir | Out-Null
        & $NssmPath set ProxyMonitor AppNoConsole 1 | Out-Null
        & $NssmPath set ProxyMonitor ObjectName LocalSystem | Out-Null
        & $NssmPath set ProxyMonitor Start SERVICE_AUTO_START | Out-Null
        & $NssmPath set ProxyMonitor AppRestartDelay 5000 | Out-Null
        & $NssmPath set ProxyMonitor AppThrottle 1500 | Out-Null
        & $NssmPath set ProxyMonitor AppExit Default Restart | Out-Null
        & $NssmPath set ProxyMonitor AppStdout (Join-Path $localDir 'ProxyMonitor.log') | Out-Null
        & $NssmPath set ProxyMonitor AppStderr (Join-Path $localDir 'ProxyMonitor.log') | Out-Null

        & $NssmPath start ProxyMonitor | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "NSSM start fehlgeschlagen (Exit-Code $LASTEXITCODE)." }
        $service = Get-Service -Name ProxyMonitor -ErrorAction Stop
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        Write-Log 'Dienst laeuft erfolgreich'
        return $true
    }
    catch {
        Write-Log "Fehler beim Installieren oder Starten des Dienstes: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

Clear-Host
Write-Host 'STWB ProxyMonitor V.1.0' -ForegroundColor Cyan

if (-not (Test-Administrator)) {
    Write-Host 'Fehler: Administrator erforderlich' -ForegroundColor Red
    return
}

if (-not (Ensure-Directory -Path $localDir)) { return }
Write-Log "Start - Benutzer: $env:USERNAME, Computer: $env:COMPUTERNAME"

if ($NetworkPath -and (-not (Test-NetworkPath -Path $NetworkPath))) { return }
$nssmPath = Install-NSSM
if (-not $nssmPath) { return }
if (-not (Create-ProxyMonitorScript -Path $LocalScriptPath)) { return }
if (-not (Install-ProxyMonitorService -ScriptPath $LocalScriptPath -NssmPath $nssmPath)) { return }

Write-Host "Installation erfolgreich. Dienst-Log: $(Join-Path $localDir 'ProxyMonitor.log')" -ForegroundColor Green