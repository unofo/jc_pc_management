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
$version = 2026111801        # raise for every release: PCs only take a higher number (so no downgrade either)
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
        'Microsoft.MSPaint'                         # Paint 3D (NOT Paint: that is Microsoft.Paint, which stays)
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
    if ($k) {
        foreach ($name in $folders) {
            $v = ([string]$k.GetValue($name, '', 'DoNotExpandEnvironmentNames')) -replace '%USERPROFILE%', $prof.Replace('$', '$$')
            if ($v.StartsWith("$prof\OneDrive", [StringComparison]::OrdinalIgnoreCase)) { $keepOneDrive = $true; Write-Warning "Still inside OneDrive: $v" }
        }
        $k.Close()
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
# No Widgets policy (Dsh\AllowNewsAndInterests): Windows 11 locks that key (access denied even as admin,
# 2026-11-13). Widgets are gone anyway: their app (MicrosoftWindows.Client.WebExperience) is removed and deprovisioned above.
Set-Policy 'Windows\CloudContent'   'DisableWindowsConsumerFeatures' # no auto-installed suggested apps (ignored on Home/Pro)

# --- Persist: copy self and re-run at every startup as SYSTEM
if ($PSCommandPath -ne $self) { Copy-Item $PSCommandPath $self -Force }
Register-ScheduledTask -TaskName RemoveBloat -Force `
    -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$self`"") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Principal (New-ScheduledTaskPrincipal -UserId SYSTEM -RunLevel Highest) | Out-Null

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
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUNfNyb+0+V/+Z/eNQq94G21By
# +SGgggMEMIIDADCCAeigAwIBAgIQbJgRWdpsZZhGIWivjED1ojANBgkqhkiG9w0B
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
# AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUQrZn79xZ3PkeiCWM
# i0wWXN0m+IwwDQYJKoZIhvcNAQEBBQAEggEAVbW7p4ZdqBf0yy9Y1/YtA+5VEewQ
# jIrw6GrrWAHa4J/RQxabEdlMN+uXmzqOifkfL9+FohwJ57v/IDzhj9+C7X5Od1hW
# qN3S0pGnkPXUyDlVLeay0B0GG8WYnqagXMWmVegvnkV0UD0FQ9Tg6cSZjh6RnWM6
# zj10kw3n179uMN04ui88IeMOC3zoqh0zp1t6Zp+ZnmBaNz8g7nXGtxrH7CWloPHO
# GYCgw+oM4st8Eg7K3T4MwI3a8EfNKgRo0y2WDYJfer+fn8A/nBpIMlntbIv/njml
# kl8utNNBcWCIK1n4V4MWXAqFkrsAwYQeciN5TboMEwrRmfk8OCulyZBqaQ==
# SIG # End signature block
