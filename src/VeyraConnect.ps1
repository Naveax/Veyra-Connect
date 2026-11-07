#requires -Version 5.1
<#
Veyra Connect, Windows 10/11 user-level installer and launcher.
Driver-free Discord TCP connectivity with hufrea/byedpi (ciadpi SOCKS5).
No anti-cheat, game binaries, firewall, certificates, system-wide proxy,
WinDivert installation, or global DNS changes are made automatically.
Windows PowerShell 5.1. Official ByeDPI v0.17.3 SHA256-pinned archives.
#>
[CmdletBinding()]
param(
    [ValidateSet('Install','Launch','Stop','Status','Test','Uninstall','GameMode','AutoStartOn','AutoStartOff','DNSOn','DNSOff','RestoreBridge')]
    [string]$Mode = 'Status',
    [switch]$Quiet,
    [switch]$NoDiscordLaunch,
    [switch]$RestartDiscord
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:AppDir = Join-Path $env:LOCALAPPDATA 'VeyraConnect'
$script:SourceDir = Split-Path -Parent $PSCommandPath
$script:EnginePath = Join-Path $script:AppDir 'VeyraConnect.ps1'
$script:ConfigFile = Join-Path $script:AppDir 'config.json'
$script:ProxyStateFile = Join-Path $script:AppDir 'proxy-state.json'
$script:DnsStateFile = Join-Path $script:AppDir 'dns-state.json'
$script:LogsDir = Join-Path $script:AppDir 'logs'
$script:Port = 18766
$script:Tag = 'VeyraConnect_v1'
$script:RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:RunName = 'VeyraConnect'
$script:ByeDPIVersion = 'v0.17.3'
$script:ArchiveInfo = @{
    X64 = @{ Name='byedpi-17.3-x86_64-w64.zip'; Hash='70d2c94147193cb915f9c6eb5144b8d404dacbcfa90bda2383b6b211afafa456' }
    X86 = @{ Name='byedpi-17.3-i686-w64.zip'; Hash='3f3d0af999371cfa623bd641738a42785e107a9d829b38480ed3d942dafea28a' }
}
$script:StrategyOptions = @(
    @{ Name='split_disorder'; Args=@('--split','1+s','--disorder','3+s') },
    @{ Name='tls_record'; Args=@('--tlsrec','1+s') },
    @{ Name='disorder_auto'; Args=@('--disorder','1','--auto=torst','--tlsrec','1+s') }
)
$script:LogFile = $null

function Say([string]$kind,[string]$message) {
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'),$kind,$message
    if (-not $Quiet -or $kind -in @('FAIL','WARN','READY')) { Write-Host $line }
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}
function Initialize-Log {
    New-Item -ItemType Directory -Path $script:AppDir,$script:LogsDir -Force | Out-Null
    $script:LogFile = Join-Path $script:LogsDir ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.txt')
    Say 'INIT' ('Veyra Connect v1.0.0 | mode=' + $Mode + ' | machine=' + $env:COMPUTERNAME)
}
function Is-Admin {
    $p = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Service-State([string]$name) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return 'Absent' }
    return [string]$svc.Status
}
function Get-Games {
    return @(Get-Process -Name cod,cod22,cod23,cod24,cod25,ModernWarfare,BlackOpsColdWar -ErrorAction SilentlyContinue)
}
function Packet-Filter-State {
    return [pscustomobject]@{
        Bridge = (Service-State 'NaveaxNetBridge')
        Driver = (Service-State 'WinDivert')
        Driver14 = (Service-State 'WinDivert14')
        WinWS = @(Get-Process -Name 'winws' -ErrorAction SilentlyContinue).Count
        GoodbyeDPI = @(Get-Process -Name 'goodbyedpi' -ErrorAction SilentlyContinue).Count
        CoD = @(Get-Games).Count
    }
}
function Assert-GameSafe {
    $s = Packet-Filter-State
    Say 'STATE' ('Bridge=' + $s.Bridge + ', WinDivert=' + $s.Driver + ', WinDivert14=' + $s.Driver14 + ', winws=' + $s.WinWS + ', GoodbyeDPI=' + $s.GoodbyeDPI + ', CoD=' + $s.CoD)
    if ($s.Bridge -eq 'Running' -or $s.Driver -eq 'Running' -or $s.Driver14 -eq 'Running' -or $s.WinWS -gt 0 -or $s.GoodbyeDPI -gt 0) {
        throw 'Packet filter still active. Use OYUN_MODU.cmd before starting Call of Duty. No drivers were modified.'
    }
}
function Load-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) { throw 'Not installed. Run KUR.cmd first.' }
    return (Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Write-Config($cfg) {
    $tmp = $script:ConfigFile + '.tmp'
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $script:ConfigFile -Force
}
function Get-OSArchitecture {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.BuildNumber -lt 17763 -or [int]$os.Version.Split('.')[0] -ne 10) {
        throw 'Only Windows 10 1809+ and Windows 11 are supported.'
    }
    $arch = [string][Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($arch -notin @('X64','X86')) { throw ('Unsupported architecture ' + $arch + '. Windows ARM64 has not been validated.') }
    Say 'OS' ($os.Caption + ' | build=' + $os.BuildNumber + ' | architecture=' + $arch)
    return $arch
}
function Verify-Hash([string]$path,[string]$expected) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ine $expected) { Say 'WARN' ('SHA256 mismatch for ' + [IO.Path]::GetFileName($path)); return $false }
    return $true
}
function Install-Binary([string]$arch) {
    $a = $script:ArchiveInfo[$arch]
    $destination = Join-Path $script:AppDir 'bin'
    $exePath = Join-Path $destination 'ciadpi.exe'
    $hashFile = Join-Path $destination 'verified-archive.sha256'
    $exeHashFile = Join-Path $destination 'ciadpi.sha256'
    if ((Test-Path -LiteralPath $exePath) -and (Test-Path -LiteralPath $hashFile) -and (Test-Path -LiteralPath $exeHashFile)) {
        $saved = (Get-Content -LiteralPath $hashFile -Raw).Trim()
        $exeSaved = (Get-Content -LiteralPath $exeHashFile -Raw).Trim()
        if ($saved -ieq $a.Hash -and (Verify-Hash $exePath $exeSaved)) {
            Say 'INFO' 'Previously verified official ByeDPI binary found.'
            return $exePath
        }
    }
    $cachedArchive = Join-Path $script:AppDir $a.Name
    $bundledArchive = Join-Path $script:SourceDir $a.Name
    if (Verify-Hash $bundledArchive $a.Hash) {
        Say 'VERIFY' 'Local official archive SHA256 OK.'
        $archive = $bundledArchive
    } elseif (Verify-Hash $cachedArchive $a.Hash) {
        Say 'VERIFY' 'Cached official archive SHA256 OK.'
        $archive = $cachedArchive
    } else {
        $url = 'https://github.com/hufrea/byedpi/releases/download/' + $script:ByeDPIVersion + '/' + $a.Name
        Say 'DOWNLOAD' ('Fetching ' + $a.Name + ' from official hufrea/byedpi release.')
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $temp = $cachedArchive + '.download'
        try {
            Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 120
            if (-not (Verify-Hash $temp $a.Hash)) { throw 'Official release archive SHA256 validation failed. Installation stopped.' }
            Move-Item -LiteralPath $temp -Destination $cachedArchive -Force
        } finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
        }
        $archive = $cachedArchive
        Say 'VERIFY' 'Official release archive SHA256 verified.'
    }
    $stage = Join-Path $script:AppDir ('extract_' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $archive -DestinationPath $stage -Force
        $found = @(Get-ChildItem -LiteralPath $stage -File -Filter 'ciadpi.exe' -Recurse -ErrorAction Stop)
        if ($found.Count -ne 1) { throw 'Unexpected official archive content. Expected one ciadpi.exe.' }
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath $found[0].FullName -Destination $exePath -Force
        Set-Content -LiteralPath $hashFile -Value $a.Hash -Encoding ASCII
        Set-Content -LiteralPath $exeHashFile -Value (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash -Encoding ASCII
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
    return $exePath
}
function Discord-Exe {
    $d = Join-Path $env:LOCALAPPDATA 'Discord'
    if (-not (Test-Path -LiteralPath $d)) { return $null }
    foreach ($folder in @(Get-ChildItem -LiteralPath $d -Directory -Filter 'app-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        $candidate = Join-Path $folder.FullName 'Discord.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}
function Get-Listener([int]$port) {
    return @(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}
function Get-OwnProxy {
    if (-not (Test-Path -LiteralPath $script:ProxyStateFile)) { return $null }
    $saved = Get-Content -LiteralPath $script:ProxyStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $saved.ProcessId -or -not $saved.Exe) { return $null }
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$saved.ProcessId) -ErrorAction SilentlyContinue
    if (-not $p -or -not $p.ExecutablePath) { return $null }
    $expected = [IO.Path]::GetFullPath([string]$saved.Exe)
    $allowed = [IO.Path]::GetFullPath((Join-Path $script:AppDir 'bin\ciadpi.exe'))
    if ($expected -ine $allowed) { return $null }
    $running = [IO.Path]::GetFullPath([string]$p.ExecutablePath)
    if ($running -ine $expected) { return $null }
    $startTime = [string]$saved.StartTimeUtc
    $check = Get-Process -Id ([int]$saved.ProcessId) -ErrorAction SilentlyContinue
    if (-not $check) { return $null }
    if ($startTime -and $check.StartTime.ToUniversalTime().ToString('o') -ne $startTime) { return $null }
    $listening = @(Get-Listener $script:Port | Where-Object { $_.OwningProcess -eq [int]$saved.ProcessId })
    if ($listening.Count -eq 0) { return $null }
    return $saved
}
function Stop-OwnProxy {
    $saved = Get-OwnProxy
    if ($saved) {
        Say 'STOP' ('Stopping only verified owned ciadpi PID=' + $saved.ProcessId)
        Stop-Process -Id ([int]$saved.ProcessId) -ErrorAction Stop
    } else { Say 'INFO' 'No verified owned ciadpi instance found; unrelated processes unchanged.' }
    if (Test-Path -LiteralPath $script:ProxyStateFile) { Remove-Item -LiteralPath $script:ProxyStateFile -Force }
}
function Curl-Probe([string]$url,[bool]$useProxy) {
    $argumentList = @('-q','-4','-sS','--connect-timeout','6','--max-time','14', '-o','NUL', '-w','HTTP=%{http_code}|VERIFY=%{ssl_verify_result}')
    if ($useProxy) { $argumentList += @('--proxy',('socks5h://127.0.0.1:' + $script:Port)) }
    else { $argumentList += @('--noproxy','*') }
    $argumentList += $url
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = @(& curl.exe @argumentList 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    $line = ($result | Out-String).Trim()
    $ok = ($exitCode -eq 0 -and $line -match 'HTTP=200\|VERIFY=0')
    return [pscustomobject]@{ Passed=$ok; ExitCode=$exitCode; Response=$line }
}
function Write-ProxyState($process,[string]$exePath,[string]$strategy) {
    $d = [pscustomobject]@{
        ProcessId = [int]$process.Id
        Exe = [string]$exePath
        StartTimeUtc = $process.StartTime.ToUniversalTime().ToString('o')
        Strategy = $strategy
        Port = $script:Port
    }
    $d | ConvertTo-Json | Set-Content -LiteralPath $script:ProxyStateFile -Encoding UTF8
}
function Start-Strategy([string]$exePath,$strategy) {
    if (@(Get-Listener $script:Port).Count -gt 0) { throw ('Port ' + $script:Port + ' is in use. Refusing to take over existing service.') }
    $logOut = Join-Path $script:LogsDir ('ciadpi_' + $strategy.Name + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_out.txt')
    $logErr = Join-Path $script:LogsDir ('ciadpi_' + $strategy.Name + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_err.txt')
    # Bind SOCKS listener on loopback only. No transparent filtering or drivers.
    $argumentList = @('--ip','127.0.0.1','--port',([string]$script:Port),'-I','0.0.0.0') + @($strategy.Args)
    $p = Start-Process -FilePath $exePath -ArgumentList $argumentList -WorkingDirectory (Split-Path -Parent $exePath) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    Start-Sleep -Milliseconds 900
    $owner = @(Get-Listener $script:Port | Where-Object { $_.OwningProcess -eq $p.Id })
    if ($p.HasExited -or $owner.Count -eq 0) {
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue }
        throw ('ciadpi did not bind loopback port, strategy=' + $strategy.Name)
    }
    Write-ProxyState $p $exePath $strategy.Name
    return $p
}
function Start-And-TestProxy($cfg) {
    if (-not (Get-Command 'curl.exe' -ErrorAction SilentlyContinue)) { throw 'curl.exe missing. Windows 10 1809+ normally includes curl.exe.' }
    $owned = Get-OwnProxy
    if ($owned) { Say 'INFO' ('Verified proxy already running on 127.0.0.1:' + $script:Port); return $owned }
    if (@(Get-Listener $script:Port).Count -gt 0) { throw ('Port ' + $script:Port + ' occupied by another process.') }
    $preferred = [string]$cfg.Strategy
    $order = @($script:StrategyOptions | Where-Object { $_.Name -eq $preferred }) + @($script:StrategyOptions | Where-Object { $_.Name -ne $preferred })
    foreach ($strategy in $order) {
        Say 'TEST' ('Trying ByeDPI strategy ' + $strategy.Name)
        try {
            $p = Start-Strategy ([string]$cfg.Exe) $strategy
            $pass = 0
            foreach ($attempt in 1..3) {
                $r = Curl-Probe 'https://discord.com/api/v10/gateway' $true
                Say 'PROBE' ($strategy.Name + ' trial=' + $attempt + ' exit=' + $r.ExitCode + ' ' + $r.Response)
                if ($r.Passed) { $pass++ }
            }
            if ($pass -ge 2) {
                $cfg.Strategy = $strategy.Name
                Write-Config $cfg
                Say 'READY' ('Verified SOCKS5 Discord API ' + $pass + '/3, strategy=' + $strategy.Name)
                return (Get-OwnProxy)
            }
            Say 'WARN' ('Strategy failed threshold: ' + $pass + '/3')
        } catch { Say 'WARN' ('Strategy failed: ' + $_.Exception.Message) }
        Stop-OwnProxy
        Start-Sleep -Milliseconds 350
    }
    throw 'No driverless strategy passed HTTPS tests. No proxy left running. Check logs; external gateway may be required.'
}
function Launch-Discord([bool]$forceRestart) {
    $exe = Discord-Exe
    if (-not $exe) { Say 'WARN' 'Discord stable executable not found in LocalAppData. Install Discord desktop first.'; return }
    $running = @(Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $flagged = @(Get-CimInstance Win32_Process -Filter "Name='Discord.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'proxy-server=socks5://127\.0\.0\.1:18766' })
        if ($flagged.Count -gt 0) { Say 'READY' 'Discord already running with local SOCKS5 launch flag.'; return }
        if (-not $forceRestart) {
            Say 'WARN' 'Discord already running without Veyra flags. Quit Discord from system tray, then run BASLAT.cmd again.'
            return
        }
        Say 'WARN' 'RestartDiscord requested. Unsaved Discord drafts can be lost.'
        $running | Stop-Process -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
    $argumentList = @('--proxy-server=socks5://127.0.0.1:' + $script:Port,'--disable-quic')
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -ArgumentList $argumentList
    Say 'READY' 'Launched Discord with application-only SOCKS5 settings. Test text, voice and screen sharing manually.'
}
function Create-CmdFiles {
    $names = [ordered]@{
        'KUR.cmd'='Install'
        'BASLAT.cmd'='Launch'
        'DISCORD_YENIDEN_BASLAT.cmd'='Launch'
        'OYUN_MODU.cmd'='GameMode'
        'DURUM.cmd'='Status'
        'TEST_ET.cmd'='Test'
        'DURDUR.cmd'='Stop'
        'OTOMATIK_BASLAT_AC.cmd'='AutoStartOn'
        'OTOMATIK_BASLAT_KAPAT.cmd'='AutoStartOff'
        'DNS_ONAR_OPSIYONEL.cmd'='DNSOn'
        'DNS_GERI_AL.cmd'='DNSOff'
        'ESKI_BRIDGE_AC.cmd'='RestoreBridge'
        'KALDIR.cmd'='Uninstall'
    }
    foreach ($item in $names.GetEnumerator()) {
        $content = '@echo off' + "`r`n" + 'cd /d "%~dp0"' + "`r`n" +
          'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VeyraConnect.ps1" -Mode ' + $item.Value + "`r`n" +
          'echo.' + "`r`n" + 'pause' + "`r`n"
        if ($item.Key -eq 'DISCORD_YENIDEN_BASLAT.cmd') {
            $content = $content -replace ' -Mode Launch', ' -Mode Launch -RestartDiscord'
        }
        Set-Content -LiteralPath (Join-Path $script:AppDir $item.Key) -Value $content -Encoding ASCII
    }
}
function Create-Shortcuts {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $targets = @(
        @{ Label='Veyra Connect'; Cmd='BASLAT.cmd' },
        @{ Label='Veyra Oyun Modu'; Cmd='OYUN_MODU.cmd' },
        @{ Label='Veyra Durum'; Cmd='DURUM.cmd' }
    )
    foreach ($t in $targets) {
        $lnk = $shell.CreateShortcut((Join-Path $desktop ($t.Label + '.lnk')))
        $lnk.TargetPath = Join-Path $script:AppDir $t.Cmd
        $lnk.WorkingDirectory = $script:AppDir
        $lnk.Description = 'Veyra Connect - Discord TCP only'
        $lnk.Save()
    }
}
function Do-Install {
    $arch = Get-OSArchitecture
    $exe = Install-Binary $arch
    $existing = $null
    if (Test-Path -LiteralPath $script:ConfigFile) { $existing = Load-Config }
    $strategy = 'auto'
    if ($existing -and $existing.Strategy) { $strategy = [string]$existing.Strategy }
    $cfg = [pscustomobject]@{
        Version='1.0.0'; Engine='ByeDPI'; UpstreamVersion=$script:ByeDPIVersion
        Architecture=$arch; Exe=$exe; ExeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash; Strategy=$strategy; Port=$script:Port
        InstalledAt=(Get-Date).ToString('o')
    }
    Write-Config $cfg
    $current = [IO.Path]::GetFullPath($PSCommandPath)
    $target = [IO.Path]::GetFullPath($script:EnginePath)
    if ($current -ine $target) { Copy-Item -LiteralPath $current -Destination $target -Force }
    foreach ($name in @('README.md','LICENSE_BYEDPI.txt')) {
        $src = Join-Path $script:SourceDir $name
        if (Test-Path -LiteralPath $src) {
            $dst = Join-Path $script:AppDir $name
            if ([IO.Path]::GetFullPath($src) -ine [IO.Path]::GetFullPath($dst)) { Copy-Item -LiteralPath $src -Destination $dst -Force }
        }
    }
    $mit = @'
MIT License

Copyright (c) 2024 hufrea

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'@
    [IO.File]::WriteAllText((Join-Path $script:AppDir 'LICENSE_BYEDPI.txt'), $mit, [Text.Encoding]::UTF8)
    $readme = @'
Veyra Connect v1.0.0 | Windows 10 (1809+) / Windows 11

Desktop-only Discord TCP proxy launcher with ByeDPI v0.17.3.
This app uses a local SOCKS5 listener on 127.0.0.1:18766. No WinDivert
installer, RICOCHET modification, system proxy change or firewall edit.

Shortcuts:
- Veyra Connect : start local proxy and Discord
- Veyra Oyun Modu : optionally stop existing packet filtering with consent
- Veyra Durum : status/test

Install from VeyraConnect_Kur.bat, no admin required in the default path.
First install needs internet access to download verified ByeDPI from GitHub.
Potential Discord restart prompts for explicit consent.

For separate controls use .cmd files in %LOCALAPPDATA%\VeyraConnect.
KALDIR.cmd performs per-user uninstall; does not remove the user's
previous network configuration or legacy network tools.

Caution: SOCKS5 over Chromium does NOT route media UDP. Voice and screen
sharing must be verified on each computer. It is not a VPN or anti-cheat bypass.

Third-party: ByeDPI (hufrea/byedpi) under MIT License.
Official website: https://github.com/hufrea/byedpi
'@
    [IO.File]::WriteAllText((Join-Path $script:AppDir 'README.txt'), $readme, [Text.Encoding]::UTF8)
    Create-CmdFiles
    Create-Shortcuts
    Say 'READY' ('Installed for current user: ' + $script:AppDir)
    Say 'INFO' 'Desktop shortcuts created. No background autostart enabled by default.'
    Say 'INFO' 'To uninstall: %LOCALAPPDATA%\VeyraConnect\KALDIR.cmd'
    $filters = Packet-Filter-State
    if ($filters.Bridge -eq 'Running' -or $filters.Driver -eq 'Running' -or $filters.WinWS -gt 0 -or $filters.GoodbyeDPI -gt 0) {
        Say 'WARN' 'Legacy packet filter is active. Use the optional Veyra Oyun Modu shortcut before CoD; it will ask before stopping any kernel driver.'
        return
    }
    try {
        $null = Start-And-TestProxy $cfg
        if (-not $NoDiscordLaunch) {
            $restart = [bool]$RestartDiscord
            $discordRunning = @(Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)
            if ($discordRunning.Count -gt 0 -and -not $restart) {
                Say 'WARN' 'Discord is already running. It needs restarting for the new per-app proxy.'
                $confirmation = Read-Host 'Restart Discord now? Unsaved drafts may be lost [E/H]'
                $restart = ($confirmation -match '^(?i:e|evet|y|yes)$')
                if (-not $restart) { Say 'INFO' 'Skipped Discord restart. Use Veyra Connect desktop shortcut after exiting Discord.' }
            }
            if ($discordRunning.Count -eq 0 -or $restart) { Launch-Discord $restart }
        }
    } catch { Say 'WARN' ('Installation completed but live proxy not proven: ' + $_.Exception.Message) }
}
function Do-Launch {
    Assert-GameSafe
    $cfg = Load-Config
    if (-not (Test-Path -LiteralPath ([string]$cfg.Exe))) { throw 'ciadpi.exe missing. Run KUR.cmd again.' }
    $allowedExe = [IO.Path]::GetFullPath((Join-Path $script:AppDir 'bin\ciadpi.exe'))
    if ([IO.Path]::GetFullPath([string]$cfg.Exe) -ine $allowedExe) { throw 'Unexpected executable path in configuration.' }
    if (-not $cfg.ExeHash -or -not (Verify-Hash ([string]$cfg.Exe) ([string]$cfg.ExeHash))) { throw 'Installed executable hash changed. Run KUR.cmd to repair.' }
    $null = Start-And-TestProxy $cfg
    if (-not $NoDiscordLaunch) { Launch-Discord ([bool]$RestartDiscord) }
}
function Do-Test {
    $f = Packet-Filter-State
    Say 'STATE' ('Bridge=' + $f.Bridge + ', Driver=' + $f.Driver + ', WinWS=' + $f.WinWS + ', GoodByeDPI=' + $f.GoodbyeDPI + ', CoD=' + $f.CoD)
    $cfg = Load-Config
    $own = Get-OwnProxy
    Say 'STATE' ('Veyra proxy running=' + [bool]($null -ne $own) + '; port=' + $script:Port + '; strategy=' + $cfg.Strategy)
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { Say 'WARN' 'curl.exe not found.'; return }
    foreach ($endpoint in @('https://discord.com/api/v10/gateway','https://cdn.discordapp.com/bad-domains/current_revision.txt')) {
        $direct = Curl-Probe $endpoint $false
        Say 'DIRECT' ($endpoint + ' exit=' + $direct.ExitCode + ' ' + $direct.Response)
        if ($own) {
            $via = Curl-Probe $endpoint $true
            Say 'SOCKS' ($endpoint + ' exit=' + $via.ExitCode + ' ' + $via.Response)
        }
    }
    foreach ($domain in @('discord.com','gateway.discord.gg')) {
        $answers = @(Resolve-DnsName -Name $domain -Type A -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -ExpandProperty IPAddress)
        Say 'DNS' ($domain + ' A=' + ($answers -join ','))
    }
    Say 'INFO' 'TCP tests cannot prove Discord authenticated messages, voice UDP, screen share, or CoD game stability.'
    Say 'INFO' ('Log saved at ' + $script:LogFile)
}
function Do-GameMode {
    if (-not (Is-Admin)) {
        Say 'INFO' 'Requesting administrator access to stop existing packet-filter services.'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Mode GameMode'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
        return
    }
    if (@(Get-Games).Count -gt 0) { throw 'CoD is already running. No driver/service changes while the game is open.' }
    $s = Packet-Filter-State
    Say 'STATE' ('Before: Bridge=' + $s.Bridge + ', Driver=' + $s.Driver + ', WinWS=' + $s.WinWS + ', GoodbyeDPI=' + $s.GoodbyeDPI)
    if ($s.GoodbyeDPI -gt 0) { throw 'Close GoodbyeDPI from its own app first. No other process killed.' }
    if ($s.Bridge -eq 'Running') {
        Stop-Service -Name 'NaveaxNetBridge' -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
    $winws = @(Get-Process -Name 'winws' -ErrorAction SilentlyContinue)
    if ($winws.Count -gt 0) { throw 'winws is still active after stopping Bridge. Other owner may be using it; WinDivert not stopped.' }
    foreach ($driverName in @('WinDivert','WinDivert14')) {
        if ((Service-State $driverName) -eq 'Running') {
            Say 'WARN' ($driverName + ' is still running. Another application could be using it.')
            $answer = Read-Host ('Stop ' + $driverName + ' kernel driver? [E/H]')
            if ($answer -notmatch '^(?i:e|evet|y|yes)$') { throw 'Driver stop declined. Game-safe mode not established.' }
            $null = & sc.exe stop $driverName
            Start-Sleep -Seconds 2
        }
    }
    Assert-GameSafe
    Say 'READY' 'Game-safe baseline set. No game or anti-cheat files modified. Run BASLAT.cmd for Discord.'
}
function Do-RestoreBridge {
    if (-not (Is-Admin)) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Mode RestoreBridge'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
        return
    }
    if (@(Get-Games).Count -gt 0) { throw 'CoD detected. Do not restore packet filtering during a live game.' }
    if ((Service-State 'NaveaxNetBridge') -eq 'Absent') { throw 'Legacy NaveaxNetBridge not installed.' }
    Start-Service -Name 'NaveaxNetBridge' -ErrorAction Stop
    Say 'READY' 'Legacy Bridge restored. Stop it using OYUN_MODU.cmd before Call of Duty.'
}
function Do-AutoStart([bool]$enable) {
    if ($enable) {
        $installed = [IO.Path]::GetFullPath($script:EnginePath)
        if (-not (Test-Path -LiteralPath $installed)) { throw 'Install first.' }
        $command = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $installed + '" -Mode Launch -Quiet'
        New-Item -Path $script:RunKey -Force | Out-Null
        New-ItemProperty -Path $script:RunKey -Name $script:RunName -Value $command -PropertyType String -Force | Out-Null
        Say 'READY' 'Enabled per-user start at logon; no elevated service created.'
    } else {
        if (Get-ItemProperty -Path $script:RunKey -Name $script:RunName -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $script:RunKey -Name $script:RunName
        }
        Say 'READY' 'Disabled per-user automatic start.'
    }
}
function Remove-OwnDnsRule {
    if (-not (Test-Path -LiteralPath $script:DnsStateFile)) { Say 'INFO' 'No Veyra-owned DNS rule saved.'; return }
    if (-not (Is-Admin)) { throw 'Administrator is required to undo scoped NRPT rule.' }
    $saved = Get-Content -LiteralPath $script:DnsStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($saved.Marker -ne $script:Tag) { throw 'DNS ownership marker does not match.' }
    foreach ($name in @($saved.Names)) {
        $owned = Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name -and $_.Comment -eq $script:Tag }
        if ($owned) { Remove-DnsClientNrptRule -Name $name -Force -ErrorAction Stop }
    }
    Remove-Item -LiteralPath $script:DnsStateFile -Force
    Clear-DnsClientCache
    Say 'READY' 'Removed only Veyra-created DNS rule.'
}
function Do-DNSOn {
    if (-not (Is-Admin)) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Mode DNSOn'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
        return
    }
    if (Test-Path -LiteralPath $script:DnsStateFile) { Say 'INFO' 'Veyra DNS rule already recorded.'; return }
    $namespaces = @('discord.com','.discord.com','discord.gg','.discord.gg','discordapp.com','.discordapp.com','discordapp.net','.discordapp.net','discord.media','.discord.media','discordcdn.com','.discordcdn.com')
    $overlap = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object {
        $_.Comment -ne $script:Tag -and @($_.Namespace | Where-Object { $_ -in $namespaces }).Count -gt 0
    })
    if ($overlap.Count) { throw 'Existing external NRPT policy overlaps Discord. Refusing modification.' }
    Say 'WARN' 'Optional NRPT only. On Windows 10, Windows DNS queries are not automatically encrypted as DoH.'
    Say 'WARN' 'NRPT will NOT fix TLS packet blocking. Browser SOCKS5 resolves TCP domains on proxy side.'
    $yes = Read-Host 'Apply Discord-only Cloudflare NRPT rule? [E/H]'
    if ($yes -notmatch '^(?i:e|evet|y|yes)$') { Say 'INFO' 'Skipped.'; return }
    $rule = Add-DnsClientNrptRule -Namespace $namespaces -NameServers @('1.1.1.1','1.0.0.1') -Comment $script:Tag -DisplayName 'Veyra Discord DNS (optional)' -PassThru -ErrorAction Stop
    try {
        [pscustomobject]@{ Marker=$script:Tag; Names=@([string]$rule.Name); Date=(Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $script:DnsStateFile -Encoding UTF8
        Clear-DnsClientCache
        Say 'READY' 'Optional NRPT created. This does not modify global adapter DNS.'
    } catch {
        Remove-DnsClientNrptRule -Name $rule.Name -Force -ErrorAction SilentlyContinue
        throw
    }
}
function Do-Uninstall {
    $yes = Read-Host 'Remove Veyra Connect from this user? [E/H]'
    if ($yes -notmatch '^(?i:e|evet|y|yes)$') { Say 'INFO' 'Uninstall canceled.'; return }
    Stop-OwnProxy
    Do-AutoStart $false
    if (Test-Path -LiteralPath $script:DnsStateFile) {
        if (-not (Is-Admin)) {
            Say 'WARN' 'Optional DNS rule exists. Run DNS_GERI_AL.cmd as administrator before deleting installation.'
            return
        }
        Remove-OwnDnsRule
    }
    $desktop = [Environment]::GetFolderPath('Desktop')
    foreach ($label in @('Veyra Connect','Veyra Oyun Modu','Veyra Durum')) {
        $file = Join-Path $desktop ($label + '.lnk')
        if (Test-Path -LiteralPath $file) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($file)
            if ($shortcut.TargetPath.StartsWith(($script:AppDir + '\'),[System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $file -Force
            }
        }
    }
    Say 'INFO' 'Legacy Bridge, Windows DNS adapter, Discord and Call of Duty were not modified.'
    $script:LogFile = $null
    Remove-Item -LiteralPath $script:AppDir -Recurse -Force -ErrorAction Stop
    Write-Host '[READY] Veyra Connect uninstalled for current user.'
}

try {
    Initialize-Log
    switch ($Mode) {
        'Install'       { Do-Install }
        'Launch'        { Do-Launch }
        'Stop'          { Stop-OwnProxy; Say 'READY' 'Stopped owned SOCKS5. Discord may need normal relaunch.' }
        'Status'        { Do-Test }
        'Test'          { Do-Test }
        'Uninstall'     { Do-Uninstall }
        'GameMode'      { Do-GameMode }
        'AutoStartOn'   { Do-AutoStart $true }
        'AutoStartOff'  { Do-AutoStart $false }
        'DNSOn'         { Do-DNSOn }
        'DNSOff'        {
            if (-not (Is-Admin)) {
                $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Mode DNSOff'
                Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
            } else { Remove-OwnDnsRule }
        }
        'RestoreBridge' { Do-RestoreBridge }
    }
} catch {
    Say 'FAIL' $_.Exception.Message
    Say 'INFO' ('Log: ' + $script:LogFile)
    exit 1
}

exit 0
