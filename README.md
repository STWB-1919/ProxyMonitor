# ProxyMonitor
Der ProxyMonitor ist ein automatisierter Windows-Dienst, der sporadisch aktivierte Proxy-Einstellungen auf DELL-Notebooks ohne Benutzer-Admin-Rechte überwacht und deaktiviert.

## Installation

PowerShell als Administrator öffnen und das Skript direkt aus GitHub herunterladen und starten:

```powershell
$installer = Join-Path $env:TEMP 'ProxyMonitor-Install.ps1'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/STWB-1919/ProxyMonitor/main/ProxyMonitor.ps1' -OutFile $installer
& $installer
```

Wichtig: PowerShell muss als Administrator gestartet werden. Bei einem Fehler beendet sich der Installer jetzt nur selbst; die geöffnete PowerShell bleibt erhalten.

Bei einem privaten Repository muss der Download authentifiziert erfolgen. Ohne Git geht das unter Windows 11 über GitHub CLI:

```powershell
winget install --id GitHub.cli
gh auth login
$installer = Join-Path $env:TEMP 'ProxyMonitor-Install.ps1'
$content = gh api repos/STWB-1919/ProxyMonitor/contents/ProxyMonitor.ps1 --jq .content
[IO.File]::WriteAllBytes($installer, [Convert]::FromBase64String(($content -join '')))
& $installer
```

Alternativ im Browser bei GitHub anmelden, im Repository `Code` → `Download ZIP` wählen, das Archiv entpacken und `ProxyMonitor.ps1` in einer als Administrator gestarteten PowerShell ausführen.

Optional kann ein interner Netzwerkpfad geprüft werden:

```powershell
& $installer -NetworkPath '\\bnstore\Austausch\IT\Potulski\Scripte\Proxy'
```

Die direkte Variante mit `irm https://raw.githubusercontent.com/STWB-1919/ProxyMonitor/main/ProxyMonitor.ps1 | iex` funktioniert nur bei einem öffentlichen Repository. Tokens sollten nicht in URLs oder im Skript hinterlegt werden.

Der Installer benötigt NSSM. Falls NSSM nicht vorhanden ist, wird es über Chocolatey installiert. Der Dienst läuft als `LocalSystem` und deaktiviert erkannte Proxy-Einstellungen im System sowie in geladenen Benutzerprofilen.

Standardpfade:

- Dienstskript: `C:\install\ProxyMonitor\ProxyMonitorService.ps1`
- Installationslog: `C:\install\ProxyMonitor\Installation.log`
- Dienstlog: `C:\install\ProxyMonitor\ProxyMonitor.log`
