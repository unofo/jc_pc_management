#Requires -RunAsAdministrator
# Recurring cleanup: removes what Windows updates can bring back - Teams, To Do, News, Power Automate, Movies & TV,
# Feedback Hub, People and the other apps in $apps below, OneDrive (once no user folder lives inside it) - and re-applies the
# policies and per-user settings (no Bing web results in Start menu search, Game Bar / Widgets off, no ads /
# suggestions). Both Copilots are removed (2026-11-19). Taskbar pins are never touched (only the icons' alignment: left); the Explorer look is left to the staff (pc_setup.ps1 sets it once).
# Re-runs itself at every boot (as SYSTEM, scheduled task RemoveBloat).
# Started by pc_setup.ps1 (first-time setup: installs programs, Office without OneNote, moves folders out of OneDrive) as its
# last step; can also be run alone from an elevated PowerShell.
# Undo:             Unregister-ScheduledTask RemoveBloat; delete the policy values below; reinstall from Store.
# ASCII only on purpose: Windows PowerShell 5.1 misreads BOM-less UTF-8.

$ErrorActionPreference = 'Continue'
$dir = "$env:ProgramData\RemoveBloat"
New-Item -ItemType Directory -Force $dir | Out-Null
# log.txt holds only the latest run. Before it is overwritten, its warnings and errors - and the fact that it stopped
# before the end - are added to problems.txt, which is kept for good and goes to the NAS with the audit (2026-11-19).
if (Test-Path "$dir\log.txt") {
    $last = Get-Content "$dir\log.txt" -ErrorAction SilentlyContinue
    $when = (Get-Item "$dir\log.txt").LastWriteTime.ToString('s')
    # Korean Windows writes a warning as "<gyeong-go>:" (character codes; ASCII only here) and errors with the English
    # FullyQualifiedErrorId line (seen 2026-11-19: a Korean warning slipped through when only 'WARNING' was looked for)
    $warnKo = [string][char]0xACBD + [char]0xACE0 + ':'
    $bad = @($last | Where-Object { ($_ -match 'WARNING|Exception|FullyQualifiedErrorId|error|failed' -or $_.StartsWith($warnKo)) -and $_ -notmatch 'Not deprovisioned|On the disk only' })
    if (-not ($last -match '^Finished: cleanup\.')) { $bad += 'DID NOT FINISH (stopped before the end, or still running when the PC went off)' }
    $bad | Select-Object -Unique | Select-Object -First 30 | ForEach-Object { Add-Content "$dir\problems.txt" "$when $_" }
}
Start-Transcript "$dir\log.txt" -Force | Out-Null
# reg add that names the key when it fails (a bare reg error only says "Access is denied", not where)
function Add-Reg { $o = @(reg add @args /f 2>&1)[0]; if ($LASTEXITCODE) { Write-Warning "reg add failed: $($args[0]) /v $($args[2]) : $o" } }
# Startup entries whose program file is gone (decided 2026-11-19: SignKorea / AnySign left theirs on a PC after their
# programs were removed). Only an .exe on a local fixed drive that is not there: network paths (maybe not up at boot),
# commands without an .exe and - for a user - %variables% (they would expand to SYSTEM's folders here) are left alone.
# Each one removed goes to changes.txt with its full command, so it can be put back.
function Remove-DeadRun([string]$key, [bool]$user) {
    $k = Get-Item "Registry::$key" -ErrorAction SilentlyContinue
    if (-not $k) { return }
    foreach ($n in $k.GetValueNames()) {
        $raw = [string]$k.GetValue($n, '', 'DoNotExpandEnvironmentNames')
        if (($user -and $raw -like '*%*') -or $raw -notmatch '^\s*"?([^"]+?\.exe)') { continue }
        $exe = [Environment]::ExpandEnvironmentVariables($Matches[1])
        if ($exe -notmatch '^[A-Za-z]:\\') { continue }
        try { if (([IO.DriveInfo]$exe.Substring(0, 1)).DriveType -ne 'Fixed') { continue } } catch { continue }
        if (Test-Path -LiteralPath $exe) { continue }
        Remove-ItemProperty -LiteralPath "Registry::$key" -Name $n -ErrorAction SilentlyContinue
        Add-Content "$dir\changes.txt" "$(Get-Date -Format s) Startup entry removed (its file is gone): $key | $n | $raw"
        "Startup entry removed (its file is gone): $n"
    }
    $k.Close()
}
# Startup programs: only the AI apps below are switched off (at every boot). Switching off everything but a short list
# (decided 2026-11-19 evening, dropped the same night) also caught programs the office needs - the scan receivers
# (FBKRSSU, Sindoh MyScan) and others nobody here knows of. Which programs start on each PC is in the audit (startup=).
# Off = the way Settings > Apps > Startup does it (StartupApproved, first byte odd = off), not deleted. The "once per entry"
# mode (marks in ...\RemoveBloat\StartupSeen) stays in the function, unused. Each one switched off goes to changes.txt.
$keepStartup = 'Tailscale|RustDesk|SecurityHealth|GoogleUpdater'
# The AI apps (decided 2026-11-19): Claude, Gemini, ChatGPT, Perplexity and their kin (Perplexity's Comet, OpenAI's other
# apps ...) never start at sign-in - switched off at EVERY boot, also when someone switched them on. Matched on the entry's
# name or command, and for Store apps on the package name.
$aiStartup = 'Claude|Anthropic|Gemini|ChatGPT|OpenAI|Codex|Perplexity|Comet'
function New-RegKey([string]$key) { if (-not (Test-Path -LiteralPath "Registry::$key")) { New-Item -Path "Registry::$key" -Force | Out-Null } }   # -Force only for a missing key: on an existing one it would empty it
# $only: switch off only the entries matching it, at every run (the AI apps); without it: every entry not kept, once
function Disable-Startups([string]$runKey, [string]$approved, [string]$folder, [string]$only) {
    $seen = $approved -replace 'Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved', 'RemoveBloat\StartupSeen'
    $items = @()
    if ($runKey -and ($k = Get-Item "Registry::$runKey" -ErrorAction SilentlyContinue)) {
        $items += @($k.GetValueNames() | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ n = $_; c = [string]$k.GetValue($_) } }); $k.Close()
    }
    if ($folder) { $items += @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' | ForEach-Object { [pscustomobject]@{ n = $_.Name; c = $_.FullName } }) }
    foreach ($e in $items) {
        if ($only) { if ("$($e.n) $($e.c)" -notmatch $only) { continue } }
        else {
            if ("$($e.n) $($e.c)" -match $keepStartup) { continue }
            if ($null -ne (Get-ItemProperty -LiteralPath "Registry::$seen" -Name $e.n -ErrorAction SilentlyContinue).($e.n)) { continue }   # handled before
            New-RegKey $seen; Set-ItemProperty -LiteralPath "Registry::$seen" -Name $e.n -Value (Get-Date -Format s)
        }
        $cur = (Get-ItemProperty -LiteralPath "Registry::$approved" -Name $e.n -ErrorAction SilentlyContinue).($e.n)
        if ($cur -and ($cur[0] -band 1)) { continue }                 # already off
        New-RegKey $approved
        Set-ItemProperty -LiteralPath "Registry::$approved" -Name $e.n -Value ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Type Binary
        Add-Content "$dir\changes.txt" "$(Get-Date -Format s) Startup switched off: $($e.n) ($($e.c))"
        "Startup switched off: $($e.n)"
    }
}
# Store apps start at sign-in through a "startup task" in the app, not a Run entry. Its switch lives in the user's
# classes hive (UsrClass.dat): ...\AppModel\SystemAppData\<package>\<task> State: 0 = off (default), 1 = off by the
# person, 2 = on (4 = on by policy). Read on a test PC (Claude: ClaudeStartup, ChatGPT: App), 2026-11-19.
function Disable-AppStartupTasks([string]$classes) {
    Get-ChildItem -LiteralPath "Registry::$classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData" -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match $aiStartup } | ForEach-Object {
            $pfn = $_.PSChildName
            Get-ChildItem -LiteralPath $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                $s = (Get-ItemProperty -LiteralPath $_.PSPath -Name State -ErrorAction SilentlyContinue).State
                if ($s -eq 2 -or $s -eq 4) {
                    Set-ItemProperty -LiteralPath $_.PSPath -Name State -Value 1 -Type DWord
                    Add-Content "$dir\changes.txt" "$(Get-Date -Format s) Startup task switched off: $pfn $($_.PSChildName) (was $s)"
                    "Startup task switched off: $pfn"
                }
            }
        }
}
# Settings made ONCE per user (or per PC), then left to the person (decided 2026-11-19): $true the first time for $root
# (HKU\<user> or HKLM), never again. Marks: ...\RemoveBloat\Once.
# the PC-wide marks of "remove once" (apps / programs): set when it was removed or was not there, so a later install stays
function Test-OnceDone([string]$name) { $null -ne (Get-ItemProperty -LiteralPath 'Registry::HKLM\SOFTWARE\RemoveBloat\Once' -Name $name -ErrorAction SilentlyContinue).$name }
function Set-OnceDone([string]$name) { New-RegKey 'HKLM\SOFTWARE\RemoveBloat\Once'; Set-ItemProperty -LiteralPath 'Registry::HKLM\SOFTWARE\RemoveBloat\Once' -Name $name -Value (Get-Date -Format s) }
function Test-FirstTime([string]$root, [string]$name) {
    $k = if ($root -eq 'HKLM') { 'HKLM\SOFTWARE\RemoveBloat\Once' } else { "$root\Software\RemoveBloat\Once" }
    if ($null -ne (Get-ItemProperty -LiteralPath "Registry::$k" -Name $name -ErrorAction SilentlyContinue).$name) { return $false }
    New-RegKey $k; Set-ItemProperty -LiteralPath "Registry::$k" -Name $name -Value (Get-Date -Format s)
    $true
}

# --- Self-update (boot task only): take a newer pc_cleanup.ps1 from GitHub when it carries our signature.
# The certificate is self-signed, so a good signature reads 'UnknownError' (untrusted root): the pinned thumbprint is what
# counts; a changed file reads 'HashMismatch'. A person running this by hand always gets the file they run.
# History: update.txt next to log.txt. The version before the last update: pc_cleanup.old.ps1.
# Raise $version for every release: PCs only take a higher number (so no downgrade either). Keep that line bare:
# the logon task at the end copies it to the NAS as this PC's status.
$version = 2026111816
$updateUrl = 'https://raw.githubusercontent.com/unofo/jc_pc_management/main/pc_cleanup.ps1'
$signer = 'CDB8786DBAB645148EA2A8B82EFBE9CE854C06FA'
$self = "$dir\pc_cleanup.ps1"
$isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
if ($isSystem -and $PSCommandPath -eq $self) {
    $new = "$dir\pc_cleanup.new.ps1"
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $got = $false
    foreach ($try in 1..6) {     # the boot task starts before the network is up: up to 2 minutes
        try { Invoke-WebRequest $updateUrl -OutFile $new -UseBasicParsing -TimeoutSec 30; $got = $true; break } catch { Start-Sleep 20 }
    }
    if (-not $got) { 'Update: not checked (no download).' }
    else {
        $sig = Get-AuthenticodeSignature $new
        $v = if ((Get-Content $new -Raw) -match '(?m)^\$version = (\d+)') { [long]$Matches[1] } else { 0 }
        if ($sig.SignerCertificate.Thumbprint -ne $signer -or $sig.Status -notin 'Valid', 'UnknownError') {
            Write-Warning "Update ignored: signature $($sig.Status)."
        } elseif ($v -le $version) { "Update: none (this $version, published $v)." }
        else {
            Add-Content "$dir\update.txt" "$(Get-Date -Format s) $version -> $v"
            Copy-Item $self "$dir\pc_cleanup.old.ps1" -Force
            "Finished: cleanup. Updated to $v - the new version runs now."      # not a failed run for problems.txt
            Stop-Transcript | Out-Null
            Move-Item $new $self -Force
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $self
            exit
        }
    }
}

# Two lists (decided 2026-11-19): $apps go at EVERY boot (Windows puts them back by itself, or nobody here should have
# them); $appsOnce go ONCE per PC - someone who wants one later may install it from the Store and it stays.
$apps = 'MSTeams', 'MicrosoftTeams',
        'Microsoft.BingNews', 'Microsoft.PowerAutomateDesktop', 'Microsoft.ZuneVideo',
        'Microsoft.WindowsFeedbackHub', 'Microsoft.People', 'Microsoft.OneDriveSync',
        'Microsoft.6365217CE6EB4',                  # Microsoft Defender app (NOT Windows Security = Microsoft.SecHealthUI, which stays)
        'Microsoft.Office.OneNote',                 # OneNote for Windows 10
        'Microsoft.OutlookForWindows',              # new Outlook
        'microsoft.windowscommunicationsapps',      # Mail and Calendar
        'Microsoft.SkypeApp', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider',
        'Microsoft.XboxGameOverlay', 'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.PhotosLegacy',                   # the older of the two Photos apps (Microsoft.Windows.Photos stays)
        'Microsoft.XboxGamingOverlay',              # Game Bar (GameDVR is switched off below so Win+G shows no error)
        'Microsoft.Edge.GameAssist',                # "Microsoft Edge for Game Bar" (Edge inside Game Bar)
        'MicrosoftWindows.Client.WebExperience',    # Widgets
        'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.Windows.DevHome',
        # added 2026-11-17 (meeting room PC). Microsoft Solitaire is already above; this is the Solitaire that PC makers preload.
        '26720RandomSaladGamesLLC.SimpleSolitaire', '7EE7776C.LinkedInforWindows',
        'AdobeSystemsIncorporated.AdobeCreativeCloudExpress',  # Adobe Express
        # preloaded by the PC maker (names read from an HP laptop, 2026-11-17)
        '5A894077.McAfeeSecurity',                  # McAfee trial; Windows Security (Defender) takes over by itself
        'C27EB4BA.DropboxOEM',                      # "Dropbox promotion"
        'PricelinePartnerNetwork.Booking.comAPACBigsavingso',  # Booking.com (the name really ends like this)
        '4DF9E0F8.Netflix',
        # added 2026-11-18. Names as Microsoft publishes them, not yet seen on one of our PCs.
        'MicrosoftCorporationII.MicrosoftFamily',   # Microsoft Family
        'Microsoft.MinecraftUWP', 'Microsoft.4297127D64EC6', 'Microsoft.MinecraftEducationEdition',  # Minecraft, its launcher, Education
        'Microsoft.MixedReality.Portal',            # Mixed Reality Portal (added 2026-11-19)
        # Microsoft 365 Copilot (the old Office hub): at every boot - Office puts it on PCs by itself (moved from "once", 2026-11-19)
        'Microsoft.MicrosoftOfficeHub'
$appsOnce = 'Microsoft.Todos', 'Clipchamp.Clipchamp', 'Microsoft.WindowsSoundRecorder', 'Microsoft.BingWeather', 'Microsoft.WindowsMaps',
        'MicrosoftCorporationII.QuickAssist',
        'Microsoft.Whiteboard',                     # Microsoft Whiteboard (added 2026-11-17)
        'Microsoft.MSPaint',                        # Paint 3D (NOT Paint: that is Microsoft.Paint, which stays)
        'Microsoft.Copilot',                        # Copilot (2026-11-19: not used here; the Edge-based Copilot program: below)
        'Microsoft.Microsoft3DViewer'               # 3D Viewer (added 2026-11-19)
# Kept on purpose: Photos, Sticky Notes, Phone Link, Media Player (ZuneMusic) + WebMediaExtensions (the only video player left),
# Camera, Alarms & Clock.
$pub = @{ 'Clipchamp.Clipchamp' = 'yxz26nhyzhsrt'; 'Microsoft.SkypeApp' = 'kzf8qxf38zg5c'
          'MicrosoftWindows.Client.WebExperience' = 'cw5n1h2txyewy'      # publisher id when not Microsoft's usual one
          '26720RandomSaladGamesLLC.SimpleSolitaire' = 'kx24dqmazqk8j'; '7EE7776C.LinkedInforWindows' = 'w1wdnht996qgy'
          'AdobeSystemsIncorporated.AdobeCreativeCloudExpress' = 'ynb6jyjzte8ga'
          '5A894077.McAfeeSecurity' = 'wafk5atnkzcwy'; 'C27EB4BA.DropboxOEM' = 'xbfy0k16fey96'
          'PricelinePartnerNetwork.Booking.comAPACBigsavingso' = 'mgae2k3ys4ra0'; '4DF9E0F8.Netflix' = 'mcm4njqhnhss8' }

# --- Copilot desktop program (Edge-based, Program Files (x86)\Microsoft\Copilot; 2026-11-19 both Copilots go): FIRST,
# because it leaves a Store-app tag that can only be removed after it (seen 2026-11-14). Its uninstaller + --force-uninstall,
# at most 5 minutes. As SYSTEM (the boot task) it gets past Edge Update's lock (exit code 60 in an admin window, 2026-11-16).
# ONCE (as Copilot in $appsOnce): marked when removed or not there; a failed removal is tried again at the next boot.
$cpEntries = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.UninstallString -like '*\Microsoft\Copilot\*' })
if (-not (Test-OnceDone 'CopilotDesktop')) {
    $cpOk = $true
    foreach ($e in $cpEntries) {
        'Removing the Copilot desktop program...'
        $cp = Start-Process cmd -ArgumentList "/c `"$($e.UninstallString) --force-uninstall`"" -PassThru -WindowStyle Hidden
        if (-not $cp.WaitForExit(300000)) { Stop-Process -Id $cp.Id -Force -ErrorAction SilentlyContinue; $cpOk = $false; Write-Warning 'Copilot desktop program: uninstall did not end in 5 minutes.' }
        elseif ($cp.ExitCode) { $cpOk = $false; Write-Warning "Copilot desktop program: uninstall ended with code $($cp.ExitCode) (60 = Edge Update busy: the boot task tries again)." }
    }
    if ($cpOk) { Set-OnceDone 'CopilotDesktop' }
}

# --- Store apps: remove for all users, deprovision so new users / feature updates skip them
$prov =Get-AppxProvisionedPackage -Online
foreach ($n in @($apps) + @($appsOnce)) {
    if ($appsOnce -contains $n) {     # once per PC: after that, an install by a person stays
        if (Test-OnceDone "App.$n") { continue }
        Set-OnceDone "App.$n"
    }
    # can fail with "path not found" when the provisioned copy's files are already gone (seen 2026-11-13): harmless,
    # the Deprovisioned key below still keeps the app away
    $prov | Where-Object DisplayName -eq $n | ForEach-Object {
        try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null }
        catch { Write-Warning "Not deprovisioned: $n ($($_.Exception.Message.Trim())) - blocked by the Deprovisioned key instead." }
    }
    Get-AppxPackage -AllUsers -Name $n | Remove-AppxPackage -AllUsers
    $id = if ($pub[$n]) { $pub[$n] } else { '8wekyb3d8bbwe' }
    New-Item -Force "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\${n}_$id" | Out-Null
}

# --- Old Windows Media Player (the second "Media Player": a Windows feature, not a Store app)
Get-WindowsCapability -Online -Name 'Media.WindowsMediaPlayer*' -ErrorAction SilentlyContinue |
    Where-Object State -eq 'Installed' | Remove-WindowsCapability -Online -ErrorAction SilentlyContinue | Out-Null
Get-WindowsOptionalFeature -Online -FeatureName WindowsMediaPlayer -ErrorAction SilentlyContinue |
    Where-Object State -eq 'Enabled' | Disable-WindowsOptionalFeature -Online -NoRestart -ErrorAction SilentlyContinue | Out-Null

# --- Classic Teams machine-wide installer (comes with Office)
'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
    Where-Object DisplayName -eq 'Teams Machine-Wide Installer' |
    ForEach-Object { Start-Process msiexec -ArgumentList "/x $($_.PSChildName) /qn /norestart" -Wait }

# --- Programs not wanted on any PC (decided 2026-11-18), removed with their own uninstaller. Found in Windows' list of
# installed programs: by name, ALYac by its folder (its name in that list is Korean).
#   quiet = Melon Player (once per PC), McAfee Security Scan Plus and ESTsoft ALTools (every run): without a window.
#   by hand = antivirus programs (V3, ALYac ...): they have no quiet uninstall. Their uninstall window is opened only
#   when a person runs this (pc_setup.bat, or this file from an administrator PowerShell) and the person clicks through it;
#   the boot task only writes that they are still there.
$programs = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } | Where-Object { $_.DisplayName -and $_.UninstallString })
function Start-Uninstall($p, $quiet, $switches) {   # runs $p's uninstaller, at most 5 minutes (a window nobody answers must not hold the boot task)
    $cmd = if ($switches) { "$($p.UninstallString) $switches" }
           elseif ($p.UninstallString -match 'msiexec') { "msiexec /x $($p.PSChildName) $(if ($quiet) { '/qn' }) /norestart" }
           elseif ($quiet -and $p.QuietUninstallString) { $p.QuietUninstallString }
           else { "$($p.UninstallString)$(if ($quiet) { ' /S' })" }
    $proc = Start-Process cmd -ArgumentList "/c `"$cmd`"" -PassThru -WindowStyle Hidden
    if (-not $proc.WaitForExit(300000)) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; Write-Warning "Uninstall of $($p.DisplayName) did not end in 5 minutes." }
}
# Melon Player: ONCE per PC (2026-11-19) - someone who installs Melon again keeps it. McAfee Security Scan Plus: at
# EVERY boot - it comes bundled with other free programs' installers (Adobe Reader ...), nobody installs it on purpose.
$quiet = @()
foreach ($q in @{ n = 'Melon'; like = 'Melon Player*'; once = $true }, @{ n = 'McAfeeScan'; like = 'McAfee Security Scan*'; once = $false }) {
    $found = @($programs | Where-Object { $_.DisplayName -like $q.like })
    $quiet += $found                                    # never offered as "by hand" below either
    if ($q.once -and (Test-OnceDone "Program.$($q.n)")) { continue }
    foreach ($p in $found) { "Removing $($p.DisplayName)..."; Start-Uninstall $p $true }
    Set-OnceDone "Program.$($q.n)"
}
# Third-party security and "PC health" programs in general (decided 2026-11-18): Windows Security does that job.
#   - every antivirus that Windows' Security Center knows, except Microsoft's own (this finds ALYac, V3 ... by the name
#     they registered, whatever language it is in)
#   - the well-known suites and tune-up tools by name
# NOT meant: the small modules that bank / tax / certificate web sites install (TouchEn, AnySign, Delfino, MagicLine,
# IPinside, CrossEX, nProtect Online Security, WIZVERA ...): without them internet banking stops, and they are not listed here.
# AhnLab is no longer looked for by name (2026-11-19, was 11-18): AhnLab Safe Transaction is such a bank module and it
# cannot be removed without a person anyway. AhnLab V3 is still found as an antivirus (Windows' Security Center list).
$av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
    ForEach-Object displayName | Where-Object { $_ -and $_ -notmatch 'Windows Defender|Microsoft Defender' })
# ESTsoft's ALTools (decided 2026-11-19, the same evening; was: only AL Manager and ALTools update): ALL of them go at every
# boot - AL Manager, ALTools update, ALZip, ALSee, ALSong ... - EXCEPT ALPDF and ALCapture, which are kept on purpose
# (useful; without ALTools update they no longer update themselves). Windows itself opens zip / 7z / rar. ALYac is an
# antivirus and goes "by hand" below. Found by their folder (\ESTsoft\...), so the Korean names do not matter.
# Inno Setup uninstallers (unins000.exe) run without a window with /VERYSILENT (AL Manager / ALTools update: done on a PC,
# 2026-11-19, exit code 0); others get /S, at most 5 minutes. Leftovers: the 'ALNotify' autostart and ESTsoft tasks.
$alQuiet = @($programs | Where-Object {
    $w = "$($_.UninstallString) $($_.InstallLocation)"
    $w -like '*\ESTsoft\*' -and $w -notmatch '\\(ALPDF|ALCapture|ALYac)\\' })
foreach ($p in $alQuiet) {
    $n = if ($p.DisplayName -match '^[ -~]+$') { $p.DisplayName } else { ("$($p.UninstallString) $($p.InstallLocation)" -replace '^.*\\ESTsoft\\([^\\]+)\\.*$', '$1') }
    "Removing ESTsoft $n..."
    Start-Uninstall $p $true $(if ($p.UninstallString -match 'unins\d+\.exe') { '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' } else { '/S' })
}
if ($alQuiet) {
    cmd /c 'reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" /v ALNotify /f >nul 2>&1'
    cmd /c 'reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v ALNotify /f >nul 2>&1'
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { "$($_.Actions.Execute)" -like '*ESTsoft*ALUpdate*' -or "$($_.Actions.Execute)" -like '*ESTsoft*ALToolsManager*' } |
        Unregister-ScheduledTask -Confirm:$false
}
$quiet += $alQuiet
# Browsers other than Chrome and Edge (decided 2026-11-19: one browser, Chrome; Edge cannot go). Found by their folder, so
# a Korean display name does not matter. Quiet switches: Chromium setups (Whale, Brave, Vivaldi) take --force-uninstall,
# Opera's launcher --runimmediately, Firefox's helper.exe /S. The user's profile (bookmarks, passwords) stays on the disk -
# none of these switches deletes it; the guide (step 13) puts Whale's bookmarks into Chrome.
# shortcut: a browser installed for one user only (Whale / Opera often are) is seen only when that user runs this file
# (pc_setup.bat does); the boot task does not look into other users' installs. Upgrade if such browsers keep showing up.
$userPrograms = if (-not $isSystem) { @(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and $_.UninstallString }) }
$browserSwitch = [ordered]@{ '*\Naver Whale\*' = '--force-uninstall'; '*\BraveSoftware\*' = '--force-uninstall'; '*\Vivaldi\*' = '--force-uninstall'
    '*\Opera*\launcher.exe*' = '--runimmediately --deleteuserprofile=0'; '*\Mozilla Firefox\*' = '/S' }
# NOT at boot, only when a person runs this (2026-11-19): a browser's saved passwords can only be taken along by exporting
# them from that browser (guide step 5) - removed at boot, a PC not yet done with the guide would lose that way. In the
# guide, pc_setup (step 7, after the export) runs this file and removes them then.
foreach ($p in $(if ($isSystem) { @() } else { @($programs) + @($userPrograms) })) {
    $where = "$($p.UninstallString) $($p.InstallLocation)"
    $sw = @($browserSwitch.Keys | Where-Object { $where -like $_ } | ForEach-Object { $browserSwitch[$_] })[0]
    if (-not $sw -or $where -like '*\Google\Chrome\*' -or $where -like '*\Microsoft\Edge*') { continue }
    $n = if ($p.DisplayName -match '^[ -~]+$') { $p.DisplayName } else { ($where -replace '^.*\\(Naver Whale|BraveSoftware|Vivaldi|Opera[^\\]*|Mozilla Firefox)\\.*$', '$1') }
    "Removing browser $n..."; Start-Uninstall $p $true $sw
}
$known = 'McAfee*', 'Norton*', 'Avast*', 'AVG *', 'Avira*', 'Kaspersky*', 'ESET *', 'Bitdefender*', 'Malwarebytes*',
         'Trend Micro*', 'ViRobot*', 'CCleaner*', 'IObit*', 'Advanced SystemCare*', 'Driver Booster*'
$byHand = @($programs | Where-Object {
    $d = $_.DisplayName
    $_.PSChildName -notin $quiet.PSChildName -and (
        ($known | Where-Object { $d -like $_ }) -or ($av | Where-Object { $d -like "*$_*" }) -or
        "$($_.UninstallString) $($_.InstallLocation)" -like '*\ALYac\*')
})
foreach ($p in $byHand) {
    # ASCII in the log: a Korean name is written by what it is
    $n = if ($p.DisplayName -match '^[ -~]+$') { $p.DisplayName } elseif ("$($p.UninstallString) $($p.InstallLocation)" -like '*\ALYac\*') { 'ALYac' } else { 'an antivirus (Korean name)' }
    if ($isSystem) { "Still installed: $n. Not removed at boot (its uninstaller needs a person): run pc_cleanup.ps1 from an administrator PowerShell."; continue }
    Write-Host "Uninstall window of $n is opening: click through it (it may ask to type a code). The script goes on when it closes." -ForegroundColor Yellow
    Start-Uninstall $p $false
}

# --- Every profile: per-user settings. Also look whether Desktop/Documents/... still live inside OneDrive
# (moving them out is the job of pc_setup.ps1 = [first-time setup]; until then OneDrive stays).
$folders = 'Desktop', 'Personal', 'My Pictures', 'My Music', 'My Video'
$keepOneDrive = $false
foreach ($p in Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\S-1-5-21-*') {
    $sid = $p.PSChildName; $prof = $p.ProfileImagePath
    $hive = $sid
    if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {          # user not logged in: load their hive
        $hive = "RB_$sid"
        reg load "HKU\$hive" "$prof\NTUSER.DAT" 2>$null | Out-Null
        if ($LASTEXITCODE) { continue }
    }
    $k = Get-Item "Registry::HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue
    $desk = "$prof\Desktop"
    if ($k) {
        foreach ($name in $folders) {
            $v = ([string]$k.GetValue($name, '', 'DoNotExpandEnvironmentNames')) -replace '%USERPROFILE%', $prof.Replace('$', '$$')
            if ($v.StartsWith("$prof\OneDrive", [StringComparison]::OrdinalIgnoreCase)) { $keepOneDrive = $true; Write-Warning "Still inside OneDrive: $v" }
            if ($name -eq 'Desktop' -and $v) { $desk = $v }
        }
        $k.Close()
    }
    # SalesMap moved on the NAS (2026-11-18): \\<nas>\SalesMap -> \\<nas>\Tools\sales_map. Point this user's desktop icon and
    # data folder setting (local.json, written with \\\\ or with //) at the new place. Nothing to change = nothing written.
    $nasRx = '(jc-nas|192\.168\.0\.171)'
    $lnk = "$desk\SalesMap.lnk"
    if (Test-Path -LiteralPath $lnk) {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $a = $s.Arguments -replace "(?i)(\\\\$nasRx)\\SalesMap\\", '$1\Tools\sales_map\'
        if ($a -ne $s.Arguments) { $s.Arguments = $a; $s.Save(); "SalesMap icon now points to the new NAS folder: $lnk" }
    }
    $cfg = "$prof\AppData\Roaming\SalesMap\local.json"
    if (Test-Path -LiteralPath $cfg) {
        $j = [IO.File]::ReadAllText($cfg)
        $n = $j -replace "(?i)((?:\\\\\\\\|//)$nasRx)(\\\\|/)SalesMap(?=\3)", '$1$3Tools$3sales_map'
        if ($n -ne $j) { [IO.File]::WriteAllText($cfg, $n); "SalesMap data folder now points to the new NAS folder: $cfg" }
    }
    # Classic Teams installed per user (the second "Microsoft Teams" entry on some PCs)
    $tu = "$prof\AppData\Local\Microsoft\Teams\Update.exe"
    if (Test-Path -LiteralPath $tu) { Start-Process $tu -ArgumentList '--uninstall -s' -Wait }
    # OneDrive is removed: its installer's autostart left in the user's own Run key (seen in the audit of a PC, 2026-11-19)
    if (-not $keepOneDrive) { cmd /c "reg delete `"HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Run`" /v OneDriveSetup /f >nul 2>&1" }
    Remove-DeadRun "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Run" $true
    $sa = "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"
    # the AI apps: at every boot (Run entries, the Startup folder, and the Store apps' startup tasks in UsrClass.dat)
    Disable-Startups "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Run" "$sa\Run" $null $aiStartup
    Disable-Startups $null "$sa\StartupFolder" "$prof\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" $aiStartup
    $cls = "${sid}_Classes"
    if (-not (Test-Path "Registry::HKEY_USERS\$cls")) {
        $cls = "RBC_$sid"; reg load "HKU\$cls" "$prof\AppData\Local\Microsoft\Windows\UsrClass.dat" 2>$null | Out-Null
        if ($LASTEXITCODE) { $cls = $null }
    }
    if ($cls) { Disable-AppStartupTasks "HKU\$cls"; if ($cls -like 'RBC_*') { [gc]::Collect(); [gc]::WaitForPendingFinalizers(); reg unload "HKU\$cls" 2>$null | Out-Null } }
    # Game Bar is removed: turn game capture off so Win+G / a controller does not pop up "get an app for ms-gamingoverlay"
    Add-Reg "HKU\$hive\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 0
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 0
    # Start menu / taskbar search: no Bing web results (local results only). Applies after sign-out.
    Add-Reg "HKU\$hive\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0
    # File Explorer Home: no files from the Microsoft account's cloud (OneDrive / Office.com) among the recent files - OneDrive
    # is removed here, and old cloud files kept showing up (2026-11-17). = Folder Options > "Show files from Office.com" off.
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Explorer" /v ShowCloudFilesInQuickAccess /t REG_DWORD /d 0
    # Settings sync ("Remember my preferences") is NOT switched off here: on Windows 11 26300 neither the old SettingSync values
    # nor CloudStore\SyncPolicies\Default (1 = on, 3 = off when the person flips the switch) change the switch when a script
    # writes them (tried on a Home PC, 2026-11-18). A person turns it off: step 11 of pc_guide.ps1 opens that page.
    # Ads and suggestions: lock screen tips, Start / Settings suggestions, silently installed apps, "finish setting up" screen,
    # "Windows welcome experience" after updates (310093).
    # Per-user settings, not policies, so they work on Home too.
    $cdm = "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($v in 'RotatingLockScreenOverlayEnabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                   'SystemPaneSuggestionsEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled') {
        Add-Reg $cdm /v $v /t REG_DWORD /d 0
    }
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 0
    # Start menu: no tips / promoted apps. (File extensions, Explorer start page, Task View button: pc_setup.ps1 sets them
    # once - staff may change them afterwards, so they are not re-applied here.)
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0
    # No "sign in with a Microsoft account" nudges (decided 2026-11-19; Windows sign-in moves to local accounts): the Start
    # menu's account notifications and the account notifications in Settings.
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_AccountNotifications /t REG_DWORD /d 0
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications" /v EnableAccountNotifications /t REG_DWORD /d 0
    # Office without OneDrive (2026-11-19, tried on a test PC): OneDrive is gone from these PCs, so Office's Open / Save As no
    # longer offers it (3 = no online storage). The recent-files list itself comes from the account and is not filtered.
    Add-Reg "HKU\$hive\Software\Policies\Microsoft\Office\16.0\Common\Internet" /v OnlineStorage /t REG_DWORD /d 3
    # Office animations off (decided 2026-11-19, tried on a test PC): the selection box in Excel jumps instead of gliding from
    # cell to cell, which makes Excel feel much faster. ONCE per user: the person may switch it back (delete the value).
    # (Excel's "optimize for compatibility" with several displays was set here for a while: dropped the same evening.)
    if (Test-FirstTime "HKU\$hive" 'NoOfficeAnimations') { Add-Reg "HKU\$hive\Software\Microsoft\Office\16.0\Common\Graphics" /v DisableAnimations /t REG_DWORD /d 1 }
    # Terminal (decided 2026-11-19): command windows open in Windows Terminal, and Terminal opens with Windows PowerShell
    # 5.1 - some PCs had Command Prompt there, where a pasted PowerShell command fails. 5.1, not PowerShell 7: it is on
    # every PC, and the commands handed out for these PCs are written and tried for it (7 was set for an hour, then
    # dropped). The "default terminal app" ONCE per user (DelegationConsole / DelegationTerminal = Windows Terminal);
    # Terminal's own default profile at every boot, only when it is Command Prompt ({0caa0dad-...}) -> Windows PowerShell
    # ({61c54bbd-...}). Any other choice is left alone.
    if (Test-FirstTime "HKU\$hive" 'TerminalDefault') {
        Add-Reg "HKU\$hive\Console\%%Startup" /v DelegationConsole /t REG_SZ /d '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
        Add-Reg "HKU\$hive\Console\%%Startup" /v DelegationTerminal /t REG_SZ /d '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'
    }
    $wt = "$prof\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path -LiteralPath $wt) {
        $j = [IO.File]::ReadAllText($wt)
        $n = $j -replace '("defaultProfile"\s*:\s*")\{0caa0dad-35be-5f56-a8ff-afceeeaa6101\}(")', '${1}{61c54bbd-c2c6-5271-96e7-009a87ff44bf}${2}'
        if ($n -ne $j) { [IO.File]::WriteAllText($wt, $n, (New-Object Text.UTF8Encoding $false)); "Terminal opens with Windows PowerShell now (was Command Prompt): $wt" }
    }
    # Taskbar icons on the LEFT, not centred (decided 2026-11-19, every PC). ONCE per user: the person may centre them again.
    if (Test-FirstTime "HKU\$hive" 'TaskbarLeft') { Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 }
    # no advertising ID, no "tailored experiences" from diagnostic data (decided 2026-11-19)
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0
    Add-Reg "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0
    # Chrome is the browser here (decided 2026-11-19): no Edge icon on this user's desktop
    Remove-Item -LiteralPath "$desk\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
    # Storage Sense on (decided 2026-11-19): once a month, temp files apps do not use and recycle-bin items older than 30
    # days. Downloads are never touched (32 = 0, 512 = 0): old files there are a person's decision.
    $ss = "HKU\$hive\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
    foreach ($v in @{ n = '01'; d = 1 }, @{ n = '2048'; d = 30 }, @{ n = '04'; d = 1 }, @{ n = '08'; d = 1 }, @{ n = '256'; d = 30 }, @{ n = '32'; d = 0 }, @{ n = '512'; d = 0 }) {
        Add-Reg $ss /v $v.n /t REG_DWORD /d $v.d
    }
    # Office: macros in files from the internet (mail attachments, downloads) are blocked - the usual way ransomware gets in.
    # Microsoft 365 does this by default; set so it stays. Files on the NAS or made here are not affected.
    foreach ($app in 'excel', 'word', 'powerpoint') {
        Add-Reg "HKU\$hive\Software\Policies\Microsoft\Office\16.0\$app\security" /v blockcontentexecutionfrominternet /t REG_DWORD /d 1
    }
    # No lock when away (decided 2026-11-19, later the same day: local accounts without a password are planned, so a lock
    # means nothing) - the screen just switches off after 15 minutes (power settings, below). Version 2026111812 had set a
    # blank screen saver with a lock: take that back. A screen saver the person chose stays, only without the lock.
    # ONCE per user (2026-11-19): the management PCs get a PIN and a lock by hand, which must stay.
    $dk = "HKU\$hive\Control Panel\Desktop"
    if (Test-FirstTime "HKU\$hive" 'NoLock') {
        Add-Reg $dk /v ScreenSaverIsSecure /t REG_SZ /d 0
        if ((Get-ItemProperty "Registry::$dk" -Name SCRNSAVE.EXE -ErrorAction SilentlyContinue).'SCRNSAVE.EXE' -like '*\scrnsave.scr') {
            Add-Reg $dk /v ScreenSaveActive /t REG_SZ /d 0
        }
    }
    if ($hive -ne $sid) { [gc]::Collect(); [gc]::WaitForPendingFinalizers(); reg unload "HKU\$hive" 2>$null | Out-Null }
}

# --- OneDrive: uninstall (only when no user folder lives inside it)
if ($keepOneDrive) {
    Write-Warning 'OneDrive NOT removed on this PC: user folders are still inside it. Run pc_setup.bat once.'
} else {
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" |
        Where-Object { Test-Path $_ } | ForEach-Object { Start-Process $_ -ArgumentList '/uninstall' -Wait }
    Get-ChildItem "$env:ProgramFiles\Microsoft OneDrive\*\OneDriveSetup.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue |
        ForEach-Object { Start-Process $_.FullName -ArgumentList '/uninstall /allusers' -Wait }
}

# startup entries of the whole PC (64- and 32-bit) whose program is gone
Remove-DeadRun 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' $false
Remove-DeadRun 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' $false
$sa = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
Disable-Startups 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' "$sa\Run" $null $aiStartup
Disable-Startups 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' "$sa\Run32" $null $aiStartup
Disable-Startups $null "$sa\StartupFolder" "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" $aiStartup

# new user profiles: drop the OneDriveSetup autorun from the default hive
reg load HKU\RBDefault "$env:SystemDrive\Users\Default\NTUSER.DAT" 2>$null | Out-Null
# through cmd: with 2>$null PowerShell 5.1 still writes reg's "not found" into the log as a red error
cmd /c 'reg delete "HKU\RBDefault\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDriveSetup /f >nul 2>&1'
[gc]::Collect(); reg unload HKU\RBDefault 2>$null | Out-Null

# --- ASUS Armoury Crate: ASUS mainboards make Windows run a small program stored in the BIOS at every boot (WPBT);
# it keeps offering / downloading Armoury Crate. Tell Windows not to run BIOS-supplied programs and switch its service off.
# (Same effect as BIOS > Tool > "Download & Install ARMOURY CRATE app" = Disabled. Applies from the next boot.)
Add-Reg 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' /v DisableWpbtExecution /t REG_DWORD /d 1
Get-Service AsusUpdateCheck -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Service $_.Name -Force -ErrorAction SilentlyContinue; Set-Service $_.Name -StartupType Disabled }

# --- Policies
function Set-Policy($key, $name) { Add-Reg "HKLM\SOFTWARE\Policies\Microsoft\$key" /v $name /t REG_DWORD /d 1 }
if (-not $keepOneDrive) { Set-Policy 'Windows\OneDrive' 'DisableFileSyncNGSC' }   # OneDrive cannot run or sync
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' /v AllowGameDVR /t REG_DWORD /d 0   # Game Bar off
# Edge: the Microsoft account that signs in to Windows (and Office) must not end up in the browser (decided 2026-11-17).
# BrowserSignin 0 = no sign-in to Edge, so no sync either; the second one = Edge does not sign in to Microsoft web sites
# with the Windows account by itself. Chrome needs nothing: it only knows Google accounts. Applies when Edge is restarted.
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v BrowserSignin /t REG_DWORD /d 0
# One browser, Chrome (decided 2026-11-19): Edge cannot be uninstalled here and some sites / programs still open it (IE
# mode), so it stays - but it no longer starts by itself, runs in the background, asks to become the default browser,
# advertises, or puts its icon back on the desktop. Its icon on the shared desktop goes.
foreach ($v in @{ n = 'StartupBoostEnabled'; d = 0 }, @{ n = 'BackgroundModeEnabled'; d = 0 }, @{ n = 'DefaultBrowserSettingEnabled'; d = 0 },
               @{ n = 'ShowRecommendationsEnabled'; d = 0 }, @{ n = 'PromotionalTabsEnabled'; d = 0 }, @{ n = 'HideFirstRunExperience'; d = 1 },
               # first start of Edge (decided 2026-11-19, "allow nothing"): no sign-in (BrowserSignin above, and no silent
               # sign-in with the Windows account), no sharing of browsing data for personalisation / feedback, no sync
               @{ n = 'ImplicitSignInEnabled'; d = 0 }, @{ n = 'SyncDisabled'; d = 1 }, @{ n = 'PersonalizationReportingEnabled'; d = 0 },
               @{ n = 'UserFeedbackAllowed'; d = 0 }, @{ n = 'EdgeShoppingAssistantEnabled'; d = 0 }, @{ n = 'ConfigureDoNotTrack'; d = 1 }) {
    Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v $v.n /t REG_DWORD /d $v.d
}
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' /v CreateDesktopShortcutDefault /t REG_DWORD /d 0
Remove-Item -LiteralPath "$env:PUBLIC\Desktop\Microsoft Edge.lnk" -Force -ErrorAction SilentlyContinue
# Diagnostic data (Edge on Windows 10/11 follows Windows here): only the required minimum goes to Microsoft (1; 0 works on
# Enterprise only), no feedback questions. Per user: no tailored experiences / advertising ID (in the profile loop).
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v AllowTelemetry /t REG_DWORD /d 1
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v DoNotShowFeedbackNotifications /t REG_DWORD /d 1
# Local accounts: no security questions for a forgotten password (easy to guess; the admin resets it instead).
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' /v NoLocalPasswordResetQuestions /t REG_DWORD /d 1
# Windows sign-in cannot become a Microsoft account (2026-11-19, tried on a test PC): 1 = no Microsoft account can be added
# to Windows or switched to. Signing in INSIDE Excel / Word / PowerPoint / Copilot still works and stays after a restart;
# the Store installs without a sign-in. (3 would also block signing in to Windows with one - not wanted.)
Add-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v NoConnectedUser /t REG_DWORD /d 1
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v MSAWebSiteSSOUsingThisProfileAllowed /t REG_DWORD /d 0
# Settings sync ("Remember my preferences") off as a policy (2 = off; the second value = the person cannot turn it back
# on). Windows 11 Home ignores it (2026-11-18: the switch stayed on); kept for Pro, not yet seen there.
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\SettingSync' /v DisableSettingSync /t REG_DWORD /d 2
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\SettingSync' /v DisableSettingSyncUserOverride /t REG_DWORD /d 1
# No Widgets policy (Dsh\AllowNewsAndInterests): Windows 11 locks that key (access denied even as admin,
# 2026-11-13). Widgets are gone anyway: their app (MicrosoftWindows.Client.WebExperience) is removed and deprovisioned above.
Set-Policy 'Windows\CloudContent'   'DisableWindowsConsumerFeatures' # no auto-installed suggested apps (ignored on Home/Pro)

# Every change below is also appended to changes.txt (kept for good, never overwritten) and goes to the NAS with the audit:
# the audit runs after the changes, so without this nobody could tell later which PC had UAC off etc. before (2026-11-19).
$changes = "$dir\changes.txt"
function Save-Change([string]$m) { Add-Content $changes "$(Get-Date -Format s) $m"; $m }
function Set-SshFirewall {   # port 22 only from Tailscale addresses AND only through the Tailscale adapter: some mobile
    # hotspots / providers hand out 100.64.x.x addresses too, so the address alone is not enough (2026-11-19)
    if (-not (Get-NetFirewallRule -Name sshd-tailscale -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name sshd-tailscale -DisplayName 'sshd (Tailscale only)' -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress 100.64.0.0/10 -Action Allow | Out-Null
    }
    if ((Get-NetFirewallRule -Name sshd-tailscale | Get-NetFirewallInterfaceFilter).InterfaceAlias -ne 'Tailscale') {
        if (Get-NetAdapter -Name Tailscale -ErrorAction SilentlyContinue) { Set-NetFirewallRule -Name sshd-tailscale -InterfaceAlias Tailscale; Save-Change 'SSH firewall: through the Tailscale connection only' }
        else { Write-Warning 'SSH firewall: no Tailscale adapter on this PC yet - Tailscale addresses only for now.' }
    }
}
function Set-DwordNoted($key, $name, $value, $what) {   # sets HKLM value $name = $value; notes it when it was different before
    $now = (Get-ItemProperty "Registry::$key" -Name $name -ErrorAction SilentlyContinue).$name
    if ($now -ne $value) { Add-Reg $key /v $name /t REG_DWORD /d $value; Save-Change "$what (was $(if ($null -eq $now) { 'not set' } else { $now }))" }
}

# --- Network discovery off (decided 2026-11-19): this PC no longer shows up in other PCs' "Network" folder. The NAS and
# printers are reached by address, which does not need it. FDResPub (Function Discovery Resource Publication) is the
# service that announces this PC.
# shortcut: only stops the announcing; the firewall group "Network Discovery" stays as it is (WSD printers may use it), so
# Settings may still show discovery as on. Disable that group too if a PC still shows up.
$fd = Get-Service FDResPub -ErrorAction SilentlyContinue
if ($fd -and $fd.StartType -ne 'Disabled') {
    Stop-Service FDResPub -Force -ErrorAction SilentlyContinue; Set-Service FDResPub -StartupType Disabled
    Save-Change 'Network discovery: this PC no longer announces itself on the network.'
}

# Networks "Public", not "Private" (decided 2026-11-19): other PCs on the office network cannot connect in, so one
# infected PC does not spread to the rest. The NAS, printers, the internet, RustDesk and Tailscale are this PC going OUT
# and work the same. Tailscale's own connection is left as it is (SSH comes in through it; its firewall rule is for any
# network type). Scans INTO the PC by FTP: FBKRSSU's firewall rule already covers Public (checked on an office PC); Sindoh's
# MyScan For Desktop had Private only, so its rule is widened to every network type.
# ONCE per network (2026-11-19): a network seen before is left as it is, so a PC that really needs "Private" can be set
# back by hand. Seen networks (by name): HKLM\SOFTWARE\RemoveBloat\NetworkSeen.
$ns = 'HKLM\SOFTWARE\RemoveBloat\NetworkSeen'
Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -ne 'Tailscale' -and $_.Name } | ForEach-Object {
    if ($null -ne (Get-ItemProperty -LiteralPath "Registry::$ns" -Name $_.Name -ErrorAction SilentlyContinue).($_.Name)) { return }
    New-RegKey $ns; Set-ItemProperty -LiteralPath "Registry::$ns" -Name $_.Name -Value (Get-Date -Format s)
    if ($_.NetworkCategory -eq 'Private') {
        Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Public -ErrorAction SilentlyContinue
        Save-Change "Network '$($_.Name)' ($($_.InterfaceAlias)) set to Public (was Private)"
    }
}
Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue | Where-Object Program -like '*\myscanfordesktop.exe' | Get-NetFirewallRule |
    Where-Object { $_.Direction -eq 'Inbound' -and $_.Profile -ne 'Any' } | ForEach-Object {
        Set-NetFirewallRule -Name $_.Name -Profile Any; Save-Change "Firewall: '$($_.DisplayName)' allowed on every network type (was $($_.Profile))"
    }

# --- Speed (decided 2026-11-19). Services that only slow the boot / sit in memory:
#   gupdate, gupdatem = the OLD Google updater (Chrome updates itself with the new GoogleUpdater); timed out at every boot on
#   one PC. HP Print Scan Doctor = a diagnosis tool's service; printer drivers are separate and stay.
foreach ($s in @(Get-Service gupdate, gupdatem -ErrorAction SilentlyContinue) + @(Get-Service | Where-Object DisplayName -like 'HP Print Scan Doctor*')) {
    if ($s.StartType -ne 'Disabled') { Stop-Service $s.Name -Force -ErrorAction SilentlyContinue; Set-Service $s.Name -StartupType Disabled; Save-Change "Service off: $($s.DisplayName)" }
}
# Delivery Optimization: updates come from Microsoft only, not shared with / from other PCs (its cache grew to 12-17 GB).
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' /v DODownloadMode /t REG_DWORD /d 0
# Desktops: no hibernation file (as big as part of the memory; a desktop does not hibernate). Laptops keep it.
if (-not (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) -and (Test-Path "$env:SystemDrive\hiberfil.sys")) { powercfg /hibernate off; Save-Change 'Hibernation off (desktop).' }
# Never sleep on mains power, also when locked (RustDesk must always reach the PC). The screen may still switch off.
powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 15       # screen off after 15 minutes away (no lock; decided 2026-11-19)

# --- Windows leftovers, once a month: crash dumps of drivers, Windows' temp files older than a week, error reports, the
# Delivery Optimization cache. Nothing of a person's. Stamp = leftovers.txt (date of the last run).
$stamp = "$dir\leftovers.txt"
if (-not (Test-Path $stamp) -or (Get-Item $stamp).LastWriteTime -lt (Get-Date).AddDays(-30)) {
    $n = 0; $bytes = 0
    $old = (Get-Date).AddDays(-7)
    $files = @(Get-ChildItem "$env:SystemRoot\LiveKernelReports" -Recurse -File -Force -ErrorAction SilentlyContinue) +
             @(Get-ChildItem "$env:SystemRoot\Temp" -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt $old) +
             @(Get-ChildItem "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Recurse -File -Force -ErrorAction SilentlyContinue)
    foreach ($f in $files) { $l = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue; if (-not (Test-Path -LiteralPath $f.FullName)) { $n++; $bytes += $l } }
    Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content $stamp (Get-Date -Format s)
    "Leftovers: $n file(s), $([math]::Round($bytes / 1GB, 2)) GB deleted; Delivery Optimization cache emptied."
}

# --- Security (decided 2026-11-19): the same on every PC. Each line changes only what differs, and says so.
$sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
# UAC on: with it off, Windows' sign-in window for a new Microsoft account never opens (two PCs, 2026-11-19). Takes a restart.
if ((Get-ItemProperty $sys).EnableLUA -ne 1) { Set-ItemProperty $sys EnableLUA 1 -Type DWord; Write-Warning (Save-Change 'UAC was off: now on, after the next restart.') }
if ((Get-ItemProperty $sys).ConsentPromptBehaviorAdmin -eq 0) { Set-ItemProperty $sys ConsentPromptBehaviorAdmin 5 -Type DWord; Save-Change 'UAC prompt for administrators was never: back to the default.' }
# Windows Update not paused / not switched off (one PC had no updates for two years).
$ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$pause = @((Get-Item $ux -ErrorAction SilentlyContinue).Property | Where-Object { $_ -like 'Pause*' })
if ($pause) { Remove-ItemProperty $ux -Name $pause; Save-Change 'Windows Update was paused: pause removed.' }
$wuau = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
if ((Get-ItemProperty $wuau -ErrorAction SilentlyContinue).NoAutoUpdate -eq 1) { Remove-ItemProperty $wuau -Name NoAutoUpdate; Save-Change 'Automatic updates were switched off: back on.' }
# Windows Update (decided 2026-11-19): released updates as soon as Windows offers them (no previews, no optional drivers),
# updates for other Microsoft products (Office), a notice when a restart is due.
# At every boot a scan is started; Windows then downloads and installs by itself, the
# person restarts when it suits (no restart in active hours 8-20 anyway). "Get me up to date" stays off: it restarts at once.
# Released updates only, NO previews (decided 2026-11-19, the same evening): "latest updates as soon as available" and
# automatic optional updates bring the monthly preview update - all PCs on the same day, before it is fully tested
# (bank modules, Douzone, SewonERP, printers). Done by the policy "optional updates" = 0 (off) alone: the switch's own
# value (UX\Settings IsContinuousInnovationOptedIn) is set back to 1 by Windows whatever is written there (a test PC, 2026-11-19).
Set-DwordNoted 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' AllowOptionalContent 0 'Windows Update: optional (preview) updates off'
Set-DwordNoted 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' AllowMUUpdateService 1 'Windows Update: updates for other Microsoft products'
# Microsoft Store apps update by themselves (2026-11-19): Windows Terminal, the AI apps, Notepad ... (4 = on).
Set-DwordNoted 'HKLM\SOFTWARE\Policies\Microsoft\WindowsStore' AutoDownload 4 'Store: apps update automatically'
# Office on its released channel (Current), not Beta / Preview (decided 2026-11-19, at every boot: a PC had been put on
# the Beta channel; joining the Office Insider program again would move it back). Only where Office (Click-to-Run) is there.
$c2r = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$cur = 'http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
$uc = (Get-ItemProperty $c2r -ErrorAction SilentlyContinue).UpdateChannel
if ($uc -and $uc -notlike '*492350f6-3a01-4f97-b9c0-c7c6ddf67d60*') { Set-ItemProperty $c2r UpdateChannel $cur; Save-Change "Office update channel back to Current (was $uc)" }
Set-DwordNoted 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' RestartNotificationsAllowed2 1 'Windows Update: notify when a restart is needed'
# active hours 8:00-20:00 = no automatic restart then (decided 2026-11-19; pc_setup had set 7-22 once). Fixed, not "adjust automatically".
Set-DwordNoted 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' SmartActiveHoursState 0 'Windows Update: fixed active hours'
Set-DwordNoted 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' ActiveHoursStart 8 'Windows Update: active hours from 8:00'
Set-DwordNoted 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' ActiveHoursEnd 20 'Windows Update: active hours until 20:00'
try {   # the "other Microsoft products" switch only works with the Microsoft Update service registered
    $sm = New-Object -ComObject Microsoft.Update.ServiceManager
    if (-not @($sm.Services | Where-Object ServiceID -eq '7971f918-a847-4430-9279-4a52d1efe18d')) { [void]$sm.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, ''); Save-Change 'Windows Update: Microsoft Update service registered' }
} catch { Write-Warning "Microsoft Update service not registered: $($_.Exception.Message)" }
Start-Process "$env:SystemRoot\System32\UsoClient.exe" -ArgumentList StartScan -WindowStyle Hidden -ErrorAction SilentlyContinue
# Firewall on for every network type.
$off = @(Get-NetFirewallProfile | Where-Object { -not $_.Enabled })
if ($off) { Set-NetFirewallProfile -All -Enabled True; Save-Change "Firewall was off ($($off.Name -join ', ')): now on." }
# Windows Security (the only antivirus now): real-time protection on; block potentially unwanted apps (bundled adware,
# "PC optimizers", toolbars that come along with free programs). Nothing happens if another antivirus is in charge.
$mp = Get-MpPreference -ErrorAction SilentlyContinue
if ($mp) {
    if ($mp.DisableRealtimeMonitoring) { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue; Save-Change 'Real-time protection was off: now on.' }
    if ($mp.PUAProtection -ne 1) { Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue; Save-Change 'Blocking of potentially unwanted apps was off: now on.' }
}
# SMB1 = the old file-sharing protocol (WannaCry); the NAS and Windows 10/11 use SMB2/3. Takes a restart.
if ((Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State -eq 'Enabled') {
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null; Write-Warning (Save-Change 'SMB1 was on: removed, after the next restart.')
}
# No Remote Desktop / Remote Assistance into this PC (RustDesk is the way in), no AutoRun from USB sticks and CDs.
Set-DwordNoted 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 1 'Remote Desktop off'
Set-DwordNoted 'HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance' fAllowToGetHelp 0 'Remote Assistance off'
Set-DwordNoted 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' NoDriveTypeAutoRun 255 'AutoRun off for all drives'
# SSH on every PC (decided 2026-11-19), so the admin can look at a PC without anyone there: installed if missing (some
# minutes, once; no network = next boot), starts with Windows, only the admin PC's key (a PUBLIC key - safe to publish;
# the private one never leaves the admin's PC, and has a passphrase), no password sign-in, and the firewall lets in only
# what comes through the Tailscale connection (the Tailscale access rules allow port 22 from the admin's PC only).
$sshKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICJGRz24EU02+DBya0R6Okt6S44ArGIIRsb3KKV2p9e'
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    try { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null; Save-Change 'SSH server installed' }
    catch { Write-Warning "SSH server not installed (tried again at the next boot): $($_.Exception.Message)" }
}
if (Get-Service sshd -ErrorAction SilentlyContinue) {
    # first on: a PC where an older guide closed SSH has it "Disabled", and a disabled service cannot be (re)started below
    # (2026-11-19: the key-only setting was then rolled back as if it had broken sshd)
    $st = (Get-Service sshd).StartType
    if ($st -ne 'Automatic') { Set-Service sshd -StartupType Automatic; Save-Change "SSH: starts with Windows now (was $st)" }
    if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd -ErrorAction SilentlyContinue }   # also writes the default sshd_config at the first start
    $cf = "$env:ProgramData\ssh\sshd_config"
    $k = "$env:ProgramData\ssh\administrators_authorized_keys"
    if ((Get-Content $k -ErrorAction SilentlyContinue) -join "`n" -ne $sshKey) {
        Set-Content $k $sshKey -Encoding ASCII
        icacls $k /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null      # sshd ignores the file otherwise
        Save-Change 'SSH: admin key written'
    }
    $t = @(Get-Content $cf -ErrorAction SilentlyContinue)
    if ($t -and -not (($t -match '^\s*PasswordAuthentication\s+no\s*$') -and ($t -match '^\s*ChallengeResponseAuthentication\s+no\s*$'))) {     # first value counts: put it first
        Copy-Item $cf "$cf.before_keyonly" -Force
        Set-Content $cf (@('PasswordAuthentication no', 'ChallengeResponseAuthentication no') + @($t | Where-Object { $_ -notmatch '^\s*(PasswordAuthentication|ChallengeResponseAuthentication|KbdInteractiveAuthentication)\s' })) -Encoding ASCII
        Restart-Service sshd -ErrorAction SilentlyContinue
        if ((Get-Service sshd).Status -ne 'Running') { Copy-Item "$cf.before_keyonly" $cf -Force; Start-Service sshd -ErrorAction SilentlyContinue; Write-Warning 'SSH: key-only setting made sshd fail - old setting back.' }
        else { Save-Change 'SSH: password sign-in off (key only)' }
    }
    Disable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue      # Windows' own rule = from anywhere
    Set-SshFirewall
}
# Common hardening (decided 2026-11-19, "A-F"):
# LLMNR off: another device on the network can answer a mistyped name and catch the sign-in (the NAS is reached by address
# or by Tailscale's own names, which do not use LLMNR).
Set-DwordNoted 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' EnableMulticast 0 'LLMNR off'
# WDigest: no password kept in memory in plain text (off by default since Windows 8.1; an old program can switch it on).
Set-DwordNoted 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' UseLogonCredential 0 'WDigest plain-text passwords off'
# PowerShell 2.0: an old engine without today's protections, used to get round them. Gone from recent Windows anyway.
foreach ($f in 'MicrosoftWindowsPowerShellV2Root', 'MicrosoftWindowsPowerShellV2') {
    if ((Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue).State -eq 'Enabled') {
        Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue | Out-Null; Save-Change "$f was on: removed" }
}
# Network protection: Windows Security blocks known malicious sites for every browser and program, not only Edge.
if ($mp -and $mp.EnableNetworkProtection -ne 1) { Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction SilentlyContinue; Save-Change "Network protection on (was $($mp.EnableNetworkProtection))" }
# Guest account off, Remote Registry service off.
Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -like '*-501' -and $_.Enabled } | ForEach-Object { Disable-LocalUser $_; Save-Change "Guest account was on: off" }
$rr = Get-Service RemoteRegistry -ErrorAction SilentlyContinue
if ($rr -and $rr.StartType -ne 'Disabled') { Stop-Service RemoteRegistry -Force -ErrorAction SilentlyContinue; Set-Service RemoteRegistry -StartupType Disabled; Save-Change "Remote Registry off (was $($rr.StartType))" }
# Local accounts: locked for 15 minutes after 10 wrong passwords (guessing). Read through secedit: its keys are English
# whatever the Windows language (net accounts prints Korean). A PIN has its own, separate protection.
$cfg = "$dir\secpol.inf"
secedit /export /cfg $cfg /areas SECURITYPOLICY /quiet | Out-Null
$m = Select-String -Path $cfg -Pattern '^LockoutBadCount\s*=\s*(\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1
$bad = if ($m) { [int]$m.Matches[0].Groups[1].Value } else { -1 }
Remove-Item $cfg -ErrorAction SilentlyContinue
if ($bad -ne 10) { net accounts /lockoutthreshold:10 /lockoutduration:15 /lockoutwindow:15 | Out-Null; Save-Change "Account lockout after 10 wrong passwords, 15 minutes (threshold was $bad)" }

# --- Persist: copy self and re-run at every startup as SYSTEM
if ($PSCommandPath -ne $self) { Copy-Item $PSCommandPath $self -Force }
Register-ScheduledTask -TaskName RemoveBloat -Force `
    -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$self`"") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Settings ($onBattery = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) `
    -Principal (New-ScheduledTaskPrincipal -UserId SYSTEM -RunLevel Highest) | Out-Null   # default = AC power only: notebooks

# --- Audit (read only, 2026-11-19): how this PC's security settings stand, one "name=value" per line in audit.txt; the
# logon task below copies it to the NAS as <PC name>_audit.txt so all PCs can be compared. Runs after the changes above:
# the "changed=" lines at its end say what was different before.
function Get-RegValue($key, $name) { (Get-ItemProperty "Registry::$key" -Name $name -ErrorAction SilentlyContinue).$name }
$au = [ordered]@{}
$au.date    = Get-Date -Format s
$au.version = $version
$os = Get-CimInstance Win32_OperatingSystem
$au.windows = "$($os.Caption) $($os.BuildNumber)"
$au.activated = [bool](Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Where-Object LicenseStatus -eq 1)
$sys = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$au.uac       = Get-RegValue $sys EnableLUA                     # 1 = on
$au.uacPrompt = Get-RegValue $sys ConsentPromptBehaviorAdmin    # 5 = default, 0 = never asks
$au.firewall  = (Get-NetFirewallProfile | ForEach-Object { "$($_.Name):$($_.Enabled)" }) -join ' '
$au.netProfile = (Get-NetConnectionProfile | ForEach-Object { "$($_.InterfaceAlias):$($_.NetworkCategory)" }) -join ' | '
$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
$au.defender  = if ($mp) { "realtime:$($mp.RealTimeProtectionEnabled) tamper:$($mp.IsTamperProtected) signaturesDays:$($mp.AntivirusSignatureAge)" } else { 'no status' }
$au.antivirus = (Get-CimInstance -Namespace root\SecurityCenter2 AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object displayName) -join ', '
$au.smartAppControl = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy' VerifiedAndReputablePolicyState   # 1 = on, 2 = evaluation, 0 = off
$au.smartScreen = Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' SmartScreenEnabled
$au.memoryIntegrity = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' Enabled
$au.lsaProtection = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' RunAsPPL
$au.secureBoot = try { Confirm-SecureBootUEFI -ErrorAction Stop } catch { 'n/a' }
$tpm = Get-CimInstance -Namespace root\cimv2\Security\MicrosoftTpm Win32_Tpm -ErrorAction SilentlyContinue
$au.tpm = if ($tpm) { "ready:$($tpm.IsEnabled_InitialValue) spec:$($tpm.SpecVersion.Split(',')[0])" } else { 'none' }
$au.bitlocker = (Get-CimInstance -Namespace root\cimv2\Security\MicrosoftVolumeEncryption Win32_EncryptableVolume -Filter "DriveLetter='C:'" -ErrorAction SilentlyContinue).ProtectionStatus   # 1 = on
$au.smb1 = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State
$au.shares = (Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '\$$' } | ForEach-Object { "$($_.Name)=$($_.Path)" }) -join ' | '
$au.remoteDesktop = if ((Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections) -eq 0) { 'on' } else { 'off' }
$au.remoteAssistance = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance' fAllowToGetHelp
$au.remoteRegistry = (Get-Service RemoteRegistry -ErrorAction SilentlyContinue).StartType
$au.sshd = $(if ($s = Get-Service sshd -ErrorAction SilentlyContinue) { "$($s.Status)/$($s.StartType)" } else { 'not installed' })
$au.autoLogon = "$(Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' AutoAdminLogon) user:$(Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' DefaultUserName)"
$au.localUsers = (Get-LocalUser | Where-Object Enabled | ForEach-Object { "$($_.Name)($($_.PrincipalSource),pwRequired:$($_.PasswordRequired))" }) -join ' '
$au.admins = (Get-LocalGroupMember -SID S-1-5-32-544 -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', '
$au.guest = (Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' }).Enabled
$au.lastUpdate = (Get-HotFix | Sort-Object InstalledOn -Descending -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { "$($_.HotFixID) $($_.InstalledOn)" })
$au.updatesPaused = Get-RegValue 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' PauseUpdatesExpiryTime
$au.networkDiscovery = (Get-Service FDResPub -ErrorAction SilentlyContinue).StartType
$au.autoplayOff = Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' NoDriveTypeAutoRun
$au.sleepOnAC = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String 'AC' | Select-Object -Last 1) -replace '.*:\s*', ''
# Hardware and health (2026-11-19): which PC needs a part (an HDD instead of an SSD is the biggest slowdown) or attention.
$au.cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$au.ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$au.disks = (Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FriendlyName) $($_.MediaType) $([math]::Round($_.Size / 1GB))GB $($_.HealthStatus)" }) -join ' | '
$c = Get-PSDrive C; $au.freeC = "$([math]::Round($c.Free / 1GB))GB ($([math]::Round(100 * $c.Free / ($c.Free + $c.Used)))%)"
$bios = Get-CimInstance Win32_BIOS; $au.bios = "$($bios.SMBIOSBIOSVersion) $($bios.ReleaseDate.ToString('yyyy-MM-dd'))"
$au.lastBootSeconds = (Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction SilentlyContinue |
    ForEach-Object { [math]::Round(([xml]$_.ToXml()).Event.EventData.Data.Where({ $_.Name -eq 'BootTime' }).'#text' / 1000) })
$au.startup = (Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | ForEach-Object Name | Sort-Object -Unique) -join ', '
# Old programs with known holes or no support any more (Java 6-8 updates aside, Flash, Silverlight, QuickTime, old Reader).
$au.oldPrograms = ($programs | Where-Object { $_.DisplayName -match '^(Java [6-8]|Java\(TM\)|Adobe Flash|Microsoft Silverlight|QuickTime|Adobe Reader (X|XI|9))' } |
    ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" } | Sort-Object -Unique) -join ', '
foreach ($p in Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.Loaded -and $_.LocalPath -like 'C:\Users\*' }) {   # only users whose settings are loaded now
    $d = "HKU\$($p.SID)\Control Panel\Desktop"
    $au["lock_$(Split-Path $p.LocalPath -Leaf)"] = "screensaver:$(Get-RegValue $d ScreenSaveActive) timeout:$(Get-RegValue $d ScreenSaveTimeOut) secure:$(Get-RegValue $d ScreenSaverIsSecure)"
}
$au.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content "$dir\audit.txt" -Encoding UTF8
# what this script changed on this PC, ever (the values above are AFTER those changes)
if (Test-Path $changes) { Get-Content $changes | ForEach-Object { "changed=$_" } | Add-Content "$dir\audit.txt" -Encoding UTF8 }
# what went wrong in earlier runs (warnings, errors, runs that did not finish) - the latest 40
if (Test-Path "$dir\problems.txt") { Get-Content "$dir\problems.txt" -Tail 40 | ForEach-Object { "problem=$_" } | Add-Content "$dir\audit.txt" -Encoding UTF8 }

# --- Status for the admin: 2 minutes after any user logs on, write this PC's $version line to the NAS as <PC name>.txt
# (file date = last logon). As the user, because only users have the NAS login (SYSTEM does not); office address first,
# then the Tailscale name. conhost --headless = no window flashes up. No NAS = nothing happens, next logon tries again.
$nas = "Tools\pc_management\status\$($env:COMPUTERNAME.ToLower()).txt"     # lowercase file name (2026-11-18); the name as it is at this boot
$nasAudit = $nas -replace '\.txt$', '_audit.txt'
$nasLog = $nas -replace '\.txt$', '_log.txt'       # the latest run in full (problems.txt in the audit keeps the history)
$find = "findstr /b /l `$version $self"
$logon = New-ScheduledTaskTrigger -AtLogOn; $logon.Delay = 'PT2M'
Register-ScheduledTask -TaskName RemoveBloatStatus -Force `
    -Action (New-ScheduledTaskAction -Execute conhost.exe -Argument "--headless cmd /c ($find > \\192.168.0.171\$nas 2>nul && copy /y $dir\audit.txt \\192.168.0.171\$nasAudit >nul) || ($find > \\jc-nas\$nas && copy /y $dir\audit.txt \\jc-nas\$nasAudit >nul) & (copy /y $dir\log.txt \\192.168.0.171\$nasLog >nul 2>&1 || copy /y $dir\log.txt \\jc-nas\$nasLog >nul 2>&1)") `
    -Trigger $logon -Settings $onBattery `
    -Principal (New-ScheduledTaskPrincipal -GroupId S-1-5-32-545) | Out-Null   # S-1-5-32-545 = Users
# Someone is usually logged on before this boot run gets here; a task registered after the logon misses that logon
# (seen 2026-11-18: never ran until started by hand). So run it once now - nobody logged on yet = the trigger does it.
Start-ScheduledTask RemoveBloatStatus -ErrorAction SilentlyContinue

# --- Network drives: at logon Windows shows mapped drives with a red X until someone opens them (the network, or Tailscale,
# is not up yet when it tries). 30 s after logon, touch each of this user's mapped drives (HKCU\Network) - that is what a
# click does - and retry every 30 s for 5 minutes for the ones not reachable yet. Never deletes or changes a mapping.
$touch = 'foreach ($i in 1..10) { $k = @(Get-ChildItem HKCU:\Network -ErrorAction SilentlyContinue | Where-Object { -not (Test-Path ($_.PSChildName + '':\'')) }); if (-not $k) { break }; Start-Sleep 30 }'
$logon = New-ScheduledTaskTrigger -AtLogOn; $logon.Delay = 'PT30S'
Register-ScheduledTask -TaskName RemoveBloatDrives -Force `
    -Action (New-ScheduledTaskAction -Execute conhost.exe -Argument ("--headless powershell.exe -NoProfile -EncodedCommand " + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($touch)))) `
    -Trigger $logon -Settings $onBattery `
    -Principal (New-ScheduledTaskPrincipal -GroupId S-1-5-32-545) | Out-Null

# --- Self-check: anything still installed is listed here and in log.txt
# "Staged" for every entry = the files lie on the disk (factory image) but no user has the app; Windows keeps such copies and
# they cannot come back by themselves (deprovisioned above). Listed in a plain line, not as a warning (HP laptop, 2026-11-17).
function Test-StagedOnly($p) { $s = @($p.PackageUserInformation | ForEach-Object { "$($_.InstallState)" }); [bool]$s.Count -and -not @($s -ne 'Staged').Count }
$pk = @($apps | ForEach-Object { Get-AppxPackage -AllUsers -Name $_ })
$left = @($pk | Where-Object { -not (Test-StagedOnly $_) } | Select-Object -ExpandProperty Name -Unique)
$staged = @($pk | Select-Object -ExpandProperty Name -Unique | Where-Object { $left -notcontains $_ })
if ($left) { Write-Warning "Still installed: $($left -join ', ')" } else { 'OK: all listed apps removed.' }
if ($staged) { "On the disk only, installed for no user (harmless): $($staged -join ', ')" }

'Finished: cleanup.'
Stop-Transcript | Out-Null

# SIG # Begin signature block
# MIIFZwYJKoZIhvcNAQcCoIIFWDCCBVQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUirD1MK975ZWXxd8tZn/sZlfK
# H9mgggMEMIIDADCCAeigAwIBAgIQbJgRWdpsZZhGIWivjED1ojANBgkqhkiG9w0B
# AQsFADAYMRYwFAYDVQQDDA1KQyBwY19jbGVhbnVwMB4XDTI2MTExODAyMTEzOVoX
# DTQ2MTExODAyMjEzOVowGDEWMBQGA1UEAwwNSkMgcGNfY2xlYW51cDCCASIwDQYJ
# KoZIhvcNAQEBBQADggEPADCCAQoCggEBANdF7OMIUMnW2D5RUDZQ4yq+XfJ+JYAx
# +bIKWYIHucLxxBXQEBe5Aqeq/ms8fBMFSSy2bWY2Tif03AkNTpmguU6a0C8twoP3
# /wPMJRIKIlNAveUvE7/yoCWBje42K2au0semOd4NLRt6VDtPvf0pmIn1Pug5njgE
# WnZFz7TOkPAzG9084rCkj43frkTnYITV0uMx7sTwNyKJLWzlNCSxu1xVuPVN6AbK
# QkgzOJPFLNDUkteMar1kTKc819ZIT7JhI0z88cWw6UsaTTjaMq5g1NW+fIH+jc6J
# QQqgV4o/xmbvv6VQ7GFpVH5Sqbssb0XQURHYPlgFI54mKv/DgNmeXqUCAwEAAaNG
# MEQwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQW
# BBQRqDmV5cjFQCOjGhQVtwfn7ehD/jANBgkqhkiG9w0BAQsFAAOCAQEASGlmtLtl
# xnNJpLpKgomczBMLPJVPi7UtD/SFUSXhDdyNJwn8QKCWX4jUesz8EldjWWpQALox
# CSzDHi/dV8jCnjkUmSk/VqGr5Y4a5DxvQe9GJtt7QuNoXYch/UXtcoEe40AyCBZf
# 9TwXbZD3li+5AwOoUFFfYoyqxDBDy1JCrQcFEWDoeNAvmtjNHh4WU4cWij+08XwM
# inetfMzkEIEfJ1Gzn358rySqV5nP5TF6ijVI9gGcV3nCxwtUn/wBxzlh6Nwbz3aj
# 9PYFwOVVcvdbdZjFqz7w7Sk5LufiMhRdCNM4mb1uZnpsN5KaETtIE1OxWZkbyaDu
# 09BEDZn0MYk+BzGCAc0wggHJAgEBMCwwGDEWMBQGA1UEAwwNSkMgcGNfY2xlYW51
# cAIQbJgRWdpsZZhGIWivjED1ojAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEK
# MAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3
# AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUDiuZ4Vi3TrP5UFDL
# ebUVxfnNTSowDQYJKoZIhvcNAQEBBQAEggEAZeUID0xxWUERTtJifrmYaKhnvRN5
# VtUOdmbo/1G4sFatOvI6tmexknqcGETc9CKDJC4ZR4bas8v57/7kExLFTg60LHua
# xgfdZdbC/OTDk4Ft6wCl8EfVgjKbTR6frYsrazWfLlobuH0sgyqt3F1I58+dN3Fr
# BgfG1VyfD8FYyzK7EUPuKU3rTMBKBATe8P4XJAJ/QsesQlfWTyRmNX2r1Cv3Rgdg
# 1+Gk89CAOwE8JILbD8gOo/uXcisTXDD9Ahya2cjLzVOultuKQL55uWZf0ZIayLul
# nVBWHI5S0d5MmwytCYNvcWIt791eD74SvQPqw5vxz/v2QjW3UDEbqXIhTA==
# SIG # End signature block
