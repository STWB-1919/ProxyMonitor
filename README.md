# ProxyMonitor
Der ProxyMonitor ist ein automatisierter Windows-Dienst, der sporadisch aktivierte Proxy-Einstellungen auf DELL-Notebooks ohne Benutzer-Admin-Rechte überwacht und deaktiviert.

## Installation

PowerShell als Administrator öffnen und das Skript direkt aus GitHub herunterladen und starten:

```powershell
$installer = Join-Path $env:TEMP 'ProxyMonitor-Install.ps1'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/STWB-1919/ProxyMonitor/main/ProxyMonitor.ps1' -OutFile $installer
& $installer
```

Optional kann ein interner Netzwerkpfad geprüft werden:

```powershell
& $installer -NetworkPath '\\bnstore\Austausch\IT\Potulski\Scripte\Proxy'
```

Alternativ kann der Installer mit `irm https://raw.githubusercontent.com/STWB-1919/ProxyMonitor/main/ProxyMonitor.ps1 | iex` direkt ausgeführt werden. Vor dem Ausführen sollte der heruntergeladene Inhalt geprüft werden.

Der Installer benötigt NSSM. Falls NSSM nicht vorhanden ist, wird es über Chocolatey installiert. Der Dienst läuft als `LocalSystem` und deaktiviert erkannte Proxy-Einstellungen im System sowie in geladenen Benutzerprofilen.

Standardpfade:

- Dienstskript: `C:\install\ProxyMonitor\ProxyMonitorService.ps1`
- Installationslog: `C:\install\ProxyMonitor\Installation.log`
- Dienstlog: `C:\install\ProxyMonitor\ProxyMonitor.log`
