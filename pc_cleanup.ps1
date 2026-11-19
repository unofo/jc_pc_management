#Requires -RunAsAdministrator
# Recurring cleanup: removes what Windows updates can bring back - Teams, To Do, News, Power Automate, Movies & TV,
# Feedback Hub, People and the other apps in $apps below, OneDrive (once no user folder lives inside it) - and re-applies the
# policies and per-user settings (no Bing web results in Start menu search, Game Bar / Widgets off, no ads /
# suggestions). Copilot is left alone (2026-11-17). The taskbar is never touched; the Explorer look is left to the staff (pc_setup.ps1 sets it once).
# Re-runs itself at every boot (as SYSTEM, scheduled task RemoveBloat).
# Started by pc_setup.ps1 (first-time setup: installs programs, Office without OneNote, moves folders out of OneDrive) as its
# last step; can also be run alone from an elevated PowerShell.
# Undo:             Unregister-ScheduledTask RemoveBloat; delete the policy values below; reinstall from Store.
# ASCII only on purpose: Windows PowerShell 5.1 misreads BOM-less UTF-8.

$ErrorActionPreference = 'Continue'
$dir = "$env:ProgramData\RemoveBloat"
New-Item -ItemType Directory -Force $dir | Out-Null
Start-Transcript "$dir\log.txt" -Force | Out-Null
# reg add that names the key when it fails (a bare reg error only says "Access is denied", not where)
function Add-Reg { $o = @(reg add @args /f 2>&1)[0]; if ($LASTEXITCODE) { Write-Warning "reg add failed: $($args[0]) /v $($args[2]) : $o" } }

# --- Self-update (boot task only): take a newer pc_cleanup.ps1 from GitHub when it carries our signature.
# The certificate is self-signed, so a good signature reads 'UnknownError' (untrusted root): the pinned thumbprint is what
# counts; a changed file reads 'HashMismatch'. A person running this by hand always gets the file they run.
# History: update.txt next to log.txt. The version before the last update: pc_cleanup.old.ps1.
# Raise $version for every release: PCs only take a higher number (so no downgrade either). Keep that line bare:
# the logon task at the end copies it to the NAS as this PC's status.
$version = 2026111810
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
            Stop-Transcript | Out-Null
            Move-Item $new $self -Force
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $self
            exit
        }
    }
}

$apps = 'MSTeams', 'MicrosoftTeams',
        'Microsoft.Todos', 'Microsoft.BingNews', 'Microsoft.PowerAutomateDesktop', 'Microsoft.ZuneVideo',
        'Microsoft.WindowsFeedbackHub', 'Microsoft.People', 'Microsoft.OneDriveSync',
        'Clipchamp.Clipchamp',
        'Microsoft.6365217CE6EB4',                  # Microsoft Defender app (NOT Windows Security = Microsoft.SecHealthUI, which stays)
        'Microsoft.Office.OneNote',                 # OneNote for Windows 10
        'Microsoft.OutlookForWindows',              # new Outlook
        'microsoft.windowscommunicationsapps',      # Mail and Calendar
        'Microsoft.SkypeApp', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.WindowsSoundRecorder',
        'Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider',
        'Microsoft.XboxGameOverlay', 'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.BingWeather',
        'Microsoft.PhotosLegacy',                   # the older of the two Photos apps (Microsoft.Windows.Photos stays)
        'Microsoft.WindowsMaps',
        'Microsoft.XboxGamingOverlay',              # Game Bar (GameDVR is switched off below so Win+G shows no error)
        'Microsoft.Edge.GameAssist',                # "Microsoft Edge for Game Bar" (Edge inside Game Bar)
        'MicrosoftWindows.Client.WebExperience',    # Widgets
        'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.Windows.DevHome',
        'MicrosoftCorporationII.QuickAssist',
        'Microsoft.Whiteboard',                     # Microsoft Whiteboard (added 2026-11-17)
        # added 2026-11-17 (meeting room PC). Microsoft Solitaire is already above; this is the Solitaire that PC makers preload.
        '26720RandomSaladGamesLLC.SimpleSolitaire', '7EE7776C.LinkedInforWindows',
        'AdobeSystemsIncorporated.AdobeCreativeCloudExpress',  # Adobe Express
        # preloaded by the PC maker (names read from an HP laptop, 2026-11-17)
        '5A894077.McAfeeSecurity',                  # McAfee trial; Windows Security (Defender) takes over by itself
        'C27EB4BA.DropboxOEM',                      # "Dropbox promotion"
        'PricelinePartnerNetwork.Booking.comAPACBigsavingso',  # Booking.com (the name really ends like this)
        '4DF9E0F8.Netflix',
        'Microsoft.MSPaint',                        # Paint 3D (NOT Paint: that is Microsoft.Paint, which stays)
        # added 2026-11-18. Names as Microsoft publishes them, not yet seen on one of our PCs.
        'MicrosoftCorporationII.MicrosoftFamily',   # Microsoft Family
        'Microsoft.MinecraftUWP', 'Microsoft.4297127D64EC6', 'Microsoft.MinecraftEducationEdition'   # Minecraft, its launcher, Education
# Kept on purpose: Photos, Sticky Notes, Phone Link, Media Player (ZuneMusic) + WebMediaExtensions (the only video player left),
# Camera, Alarms & Clock, Copilot (Store app and the Edge-based desktop program) and
# Microsoft 365 Copilot (Microsoft.MicrosoftOfficeHub, the old Office hub) - kept since 2026-11-17.
$pub = @{ 'Clipchamp.Clipchamp' = 'yxz26nhyzhsrt'; 'Microsoft.SkypeApp' = 'kzf8qxf38zg5c'
          'MicrosoftWindows.Client.WebExperience' = 'cw5n1h2txyewy'      # publisher id when not Microsoft's usual one
          '26720RandomSaladGamesLLC.SimpleSolitaire' = 'kx24dqmazqk8j'; '7EE7776C.LinkedInforWindows' = 'w1wdnht996qgy'
          'AdobeSystemsIncorporated.AdobeCreativeCloudExpress' = 'ynb6jyjzte8ga'
          '5A894077.McAfeeSecurity' = 'wafk5atnkzcwy'; 'C27EB4BA.DropboxOEM' = 'xbfy0k16fey96'
          'PricelinePartnerNetwork.Booking.comAPACBigsavingso' = 'mgae2k3ys4ra0'; '4DF9E0F8.Netflix' = 'mcm4njqhnhss8' }

# --- Store apps: remove for all users, deprovision so new users / feature updates skip them
$prov =Get-AppxProvisionedPackage -Online
foreach ($n in $apps) {
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
#   quiet = Melon Player, McAfee Security Scan Plus: uninstalled without a window, at every run.
#   by hand = AhnLab (V3, Safe Transaction) and ALYac: they have no quiet uninstall. Their uninstall window is opened only
#   when a person runs this (pc_setup.bat, or this file from an administrator PowerShell) and the person clicks through it;
#   the boot task only writes that they are still there. A bank site that needs AhnLab Safe Transaction installs it again.
$programs = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } | Where-Object { $_.DisplayName -and $_.UninstallString })
function Start-Uninstall($p, $quiet) {        # runs $p's uninstaller, at most 5 minutes (a window nobody answers must not hold the boot task)
    $cmd = if ($p.UninstallString -match 'msiexec') { "msiexec /x $($p.PSChildName) $(if ($quiet) { '/qn' }) /norestart" }
           elseif ($quiet -and $p.QuietUninstallString) { $p.QuietUninstallString }
           else { "$($p.UninstallString)$(if ($quiet) { ' /S' })" }
    $proc = Start-Process cmd -ArgumentList "/c `"$cmd`"" -PassThru -WindowStyle Hidden
    if (-not $proc.WaitForExit(300000)) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; Write-Warning "Uninstall of $($p.DisplayName) did not end in 5 minutes." }
}
$quiet = @($programs | Where-Object { $_.DisplayName -like 'Melon Player*' -or $_.DisplayName -like 'McAfee Security Scan*' })
foreach ($p in $quiet) { "Removing $($p.DisplayName)..."; Start-Uninstall $p $true }
# Third-party security and "PC health" programs in general (decided 2026-11-18): Windows Security does that job.
#   - every antivirus that Windows' Security Center knows, except Microsoft's own (this finds ALYac, V3 ... by the name
#     they registered, whatever language it is in)
#   - the well-known suites and tune-up tools by name
# NOT meant: the small modules that bank / tax / certificate web sites install (TouchEn, AnySign, Delfino, MagicLine,
# IPinside, CrossEX, nProtect Online Security, WIZVERA ...): without them internet banking stops, and they are not listed here.
# AhnLab Safe Transaction is such a module too, but it is removed with the other AhnLab products (asked for 2026-11-18).
$av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
    ForEach-Object displayName | Where-Object { $_ -and $_ -notmatch 'Windows Defender|Microsoft Defender' })
# ALTools' own advertising: 'AL Manager' and 'ALTools update' pop up offers to install ALYac and other programs (asked for
# 2026-11-19). Their names are Korean, written here as character codes. ALZip, ALSee and ALCapture themselves stay.
$alAds = ([string][char]0xC54C + [char]0xB9E4 + [char]0xB2C8 + [char]0xC800 + '*'), ([string][char]0xC54C + [char]0xD234 + [char]0xC988 + ' *')
$known = 'AhnLab*', 'McAfee*', 'Norton*', 'Avast*', 'AVG *', 'Avira*', 'Kaspersky*', 'ESET *', 'Bitdefender*', 'Malwarebytes*',
         'Trend Micro*', 'ViRobot*', 'CCleaner*', 'IObit*', 'Advanced SystemCare*', 'Driver Booster*'
$byHand = @($programs | Where-Object {
    $d = $_.DisplayName
    $_.PSChildName -notin $quiet.PSChildName -and (
        ($known + $alAds | Where-Object { $d -like $_ }) -or ($av | Where-Object { $d -like "*$_*" }) -or
        "$($_.UninstallString) $($_.InstallLocation)" -like '*\ALYac\*')
})
foreach ($p in $byHand) {
    # ASCII in the log: a Korean name is written by what it is
    $n = if ($p.DisplayName -match '^[ -~]+$') { $p.DisplayName } elseif ($alAds | Where-Object { $p.DisplayName -like $_ }) { 'ALTools manager / update' } else { 'ALYac' }
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
    # writes them (tried on a Home PC, 2026-11-18). A person turns it off: step 12 of pc_guide.ps1 opens that page.
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
# Copilot is no longer removed (2026-11-17): take back the blocks that older versions of this script left behind,
# so Copilot may return (Windows update / Store).
cmd /c 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /f >nul 2>&1'
'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider', 'Microsoft.MicrosoftOfficeHub' | ForEach-Object {
    Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\${_}_8wekyb3d8bbwe" -ErrorAction SilentlyContinue }
# Missing (older versions removed them)? Install from the Microsoft Store - signed by the Store, always its latest version.
# Only when a person runs this: winget's Store source does not work for SYSTEM (the boot task). If winget fails, the
# Store page is opened so the person presses [Install]. Installs for the account that runs this.
foreach ($a in @{ n = 'Microsoft.Copilot'; id = '9NHT9RB2F4HD' }, @{ n = 'Microsoft.MicrosoftOfficeHub'; id = '9WZDNCRD29V9' }) {
    if (Get-AppxPackage -AllUsers -Name $a.n) { "$($a.n): already installed."; continue }
    if ($isSystem) { "$($a.n): missing. Not installed at boot - run pc_cleanup.ps1 once from an administrator PowerShell."; continue }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        "$($a.n): installing from the Microsoft Store..."
        winget install --id $a.id --source msstore --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    }
    if (Get-AppxPackage -AllUsers -Name $a.n) { "$($a.n): installed." }
    else { Write-Warning "$($a.n) NOT installed: press [Install] on the Store page that opens."; Start-Process "ms-windows-store://pdp/?ProductId=$($a.id)" }
}
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' /v AllowGameDVR /t REG_DWORD /d 0   # Game Bar off
# Edge: the Microsoft account that signs in to Windows (and Office) must not end up in the browser (decided 2026-11-17).
# BrowserSignin 0 = no sign-in to Edge, so no sync either; the second one = Edge does not sign in to Microsoft web sites
# with the Windows account by itself. Chrome needs nothing: it only knows Google accounts. Applies when Edge is restarted.
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v BrowserSignin /t REG_DWORD /d 0
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v MSAWebSiteSSOUsingThisProfileAllowed /t REG_DWORD /d 0
# Settings sync ("Remember my preferences") off as a policy (2 = off; the second value = the person cannot turn it back
# on). Windows 11 Home ignores it (2026-11-18: the switch stayed on); kept for Pro, not yet seen there.
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\SettingSync' /v DisableSettingSync /t REG_DWORD /d 2
Add-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\SettingSync' /v DisableSettingSyncUserOverride /t REG_DWORD /d 1
# No Widgets policy (Dsh\AllowNewsAndInterests): Windows 11 locks that key (access denied even as admin,
# 2026-11-13). Widgets are gone anyway: their app (MicrosoftWindows.Client.WebExperience) is removed and deprovisioned above.
Set-Policy 'Windows\CloudContent'   'DisableWindowsConsumerFeatures' # no auto-installed suggested apps (ignored on Home/Pro)

# --- Persist: copy self and re-run at every startup as SYSTEM
if ($PSCommandPath -ne $self) { Copy-Item $PSCommandPath $self -Force }
Register-ScheduledTask -TaskName RemoveBloat -Force `
    -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$self`"") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Settings ($onBattery = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) `
    -Principal (New-ScheduledTaskPrincipal -UserId SYSTEM -RunLevel Highest) | Out-Null   # default = AC power only: notebooks

# --- Status for the admin: 2 minutes after any user logs on, write this PC's $version line to the NAS as <PC name>.txt
# (file date = last logon). As the user, because only users have the NAS login (SYSTEM does not); office address first,
# then the Tailscale name. conhost --headless = no window flashes up. No NAS = nothing happens, next logon tries again.
$nas = "Tools\pc_management\status\$($env:COMPUTERNAME.ToLower()).txt"     # lowercase file name (2026-11-18); the name as it is at this boot
$find = "findstr /b /l `$version $self"
$logon = New-ScheduledTaskTrigger -AtLogOn; $logon.Delay = 'PT2M'
Register-ScheduledTask -TaskName RemoveBloatStatus -Force `
    -Action (New-ScheduledTaskAction -Execute conhost.exe -Argument "--headless cmd /c $find > \\192.168.0.171\$nas 2>nul || $find > \\jc-nas\$nas") `
    -Trigger $logon -Settings $onBattery `
    -Principal (New-ScheduledTaskPrincipal -GroupId S-1-5-32-545) | Out-Null   # S-1-5-32-545 = Users
# Someone is usually logged on before this boot run gets here; a task registered after the logon misses that logon
# (seen 2026-11-18: never ran until started by hand). So run it once now - nobody logged on yet = the trigger does it.
Start-ScheduledTask RemoveBloatStatus -ErrorAction SilentlyContinue

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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUk9rZ5h7/g6FkfJsGuu/QD6ug
# VQWgggMEMIIDADCCAeigAwIBAgIQbJgRWdpsZZhGIWivjED1ojANBgkqhkiG9w0B
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
# AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUQ4O10UbHb2IWkeRr
# qY8wFtdtob0wDQYJKoZIhvcNAQEBBQAEggEAM8GccFrZVikX+Nc0GNs8IPQ8O+e4
# ZONPHrg+aSQmMKLTl2JJhWgEVLsGzYFl1+uV6HGyOFUbvVaOt7TEgPlYHpXkt1kz
# 5EQheqB0RLM++TIykFKgpwlXilSOxtp5dhmSBzYMOV6SiHBF5Zx3uzTTVDeokezR
# l1yYIhqDJw2vimUUTHvx5yM1e/8K7wXNM3ObTc/kle6Rwk+dLUmoCf6WuC3ytlND
# ngk31G0g7TczajJwwqPHQYATBEl2S5RrlEYZgDcM+cJcCkFezaSFIS8160V0xCY1
# CdYbv1UURuwxMtZc2gNe0kPurN+4a4ss6o3/cZGwGsyg27S8gNMhgkLBPw==
# SIG # End signature block
