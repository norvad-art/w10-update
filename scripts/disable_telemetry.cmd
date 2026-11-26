@echo off
rem ========================================================================================================================
rem == Version: disable_telemetry_10.05.2026 (Custom LTSC / Schneegans Edition) ==
rem == Base Author: freddie-o ==
rem == Base Source: https://forums.mydigitallife.net/threads/repo-windows-10-telemetry-repository.63874/page-66#post-1686849 ==
rem == Customized: Preserves Defender AV, Firewall, Windows Update Engine (for Schneegans PauseWindowsUpdate), ==
rem ==             Local Search (Delayed Start), WebView2, OOBE/Client.CBS, DusmSvc, and Debian/OpenDNS NCSI. ==
rem ========================================================================================================================

setlocal EnableExtensions

rem == Ensuring Administrator privileges needed to transition from SYSTEM to TrustedInstaller ==
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem == Elevate to TrustedInstaller ==
whoami /groups | find "S-1-5-80-956008885" >nul 2>&1
if %errorlevel% neq 0 (
    powershell -ExecutionPolicy Bypass -File "%~dp0Elevate_as_TI.ps1" -FilePath "%~f0" -WorkingDirectory "%~dp0."
    exit /b
)

cd /d "%~dp0"

rem == create mount and temp folders ==
mkdir mount
mkdir temp

rem == mount install.wim ==
dism /mount-image /imagefile:install.wim /index:1 /mountdir:mount

rem == offline verification scan to check component store for file corruption ==
dism /scratchdir:temp /Image:mount /Cleanup-Image /ScanHealth

rem == load registry hives to disable telemetry ==
reg load HKLM\SOFTHIVE mount\Windows\System32\config\SOFTWARE

rem == Disable Windows telemetry, diagnostics, and feedback ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "DisableEnterpriseAuthProxy" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "DoNotShowFeedbackNotifications" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "DisableOneSettingsDownloads" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "AllowCommercialDataPipeline" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "AllowDesktopAnalyticsProcessing" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "AllowDeviceNameInTelemetry" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "LimitDiagnosticLogCollection" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DataCollection" /v "LimitEnhancedDiagnosticDataWindowsAnalytics" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" /v "AllowDiagnosticSubmission" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" /v "DownloadSettings" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Feedback" /v "AllowFeedback" /t REG_DWORD /d "0" /f

rem == Disable Copilot (if present) ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\WindowsCopilot" /v "AllowWindowsCopilot" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /t REG_DWORD /d "1" /f

rem == Keep Windows Defender AV enabled, disable cloud telemetry, sample submission & MRT reporting ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows Defender\Reporting" /v "WppTracingLevel" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows Defender\Reporting" /v "DisableGenericRePorts" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows Defender\Spynet" /v "LocalSettingOverrideSpynetReporting" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows Defender\Spynet" /v "SubmitSamplesConsent" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows Defender\Spynet" /v "SpynetReporting" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows Defender\Spynet" /v "DisableBlockAtFirstSeen" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Windows Defender/Operational" /v "Enabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\MRT" /v "DontReportInfectionInformation" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\MRT" /v "DontOfferThroughWUAU" /t REG_DWORD /d "1" /f

rem == Disable SmartScreen ==
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\Explorer" /v "SmartScreenEnabled" /t REG_SZ /d "Off" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "EnableSmartScreen" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Edge" /v "SmartScreenEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\WindowsStore" /v "SmartScreenEnabled" /t REG_DWORD /d "0" /f

rem == Disable Edge WebView2 & Edge Update telemetry ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Edge" /v "MetricsReportingEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Edge" /v "DiagnosticData" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Edge" /v "PersonalizationReportingEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Edge" /v "SendSiteInfoToImproveServices" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Edge" /v "UserFeedbackAllowed" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Edge" /v "EdgeAssetDeliveryServiceEnabled" /t REG_DWORD /d "0" /f

rem == Keep Windows Update engine unlocked for Schneegans PauseWindowsUpdate; disable P2P Delivery Optimization & Reserved Storage ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DeliveryOptimization" /v "DODownloadMode" /t REG_DWORD /d "99" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v "DODownloadMode" /t REG_DWORD /d "99" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\ReserveManager" /v "ShippedWithReserves" /t REG_DWORD /d "0" /f

rem == Disable TPM-backed telemetry (Device Health Attestation) ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\DeviceHealthAttestationService" /v "EnableDeviceHealthAttestationService" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DeviceHealthAttestation" /v "AllowDeviceHealthAttestation" /t REG_DWORD /d "0" /f

rem == Restrict internet communication & Settings online tips (NCSI Active Probe kept enabled) ==
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoInternetOpenWith" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "AllowOnlineTips" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\EventViewer" /v "MicrosoftEventVwrDisableLinks" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Device Metadata" /v "PreventDeviceMetadataFromNetwork" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\DriverSearching" /v "DontSearchWindowsUpdate" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\SQMClient\Windows" /v "CEIPEnable" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\WMDRM" /v "DisableOnline" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Feeds" /v "EnableFeeds" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\OneDrive" /v "DisableFileSyncNGSC" /t REG_DWORD /d "1" /f

rem == Prevent computer from sending data to Microsoft regarding its activation state ==
reg add "HKLM\SOFTHIVE\Classes\AppID\slui.exe" /v "NoGenTicket" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform" /v "NoGenTicket" /t REG_DWORD /d "1" /f

rem == Disable error reporting ==
reg add "HKLM\SOFTHIVE\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Error Reporting" /v "DontSendAdditionalData" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Error Reporting" /v "LoggingDisabled" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d "1" /f

rem == Delete telemetry scheduled tasks (preserving WindowsUpdate, UpdateOrchestrator, WaaSMedic & CloudExperienceHost) ==
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\AppID" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Application Experience" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\AppxDeploymentClient" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Autochk" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Customer Experience Improvement Program" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Device Information" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Diagnosis" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\DiskDiagnostic" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\DiskFootprint" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Feedback" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Flighting" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\InstallService" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Location" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Maintenance\WinSAT" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Maps" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\NetTrace" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\PI\Sqm-Tasks" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\PushToInstall" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\SettingSync" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Shell\FamilySafetyMonitor" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Shell\FamilySafetyRefreshTask" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\TPM" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Windows Defender" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Windows Error Reporting" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Windows Filtering Platform" /f
reg delete "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\XblGameSave" /f

rem == Disable Cortana & web/cloud search permissions (keep local search enabled) ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Search" /v "AllowCloudSearch" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Search" /v "DisableWebSearch" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Search" /v "AllowSearchToUseLocation" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Search" /v "ConnectedSearchUseWeb" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Windows Search" /v "DeviceHistoryEnabled" /t REG_DWORD /d "0" /f

rem == Disable typing insights, handwriting personalization, clipboard sync & speech recognition ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\InputPersonalization" /v "AllowInputPersonalization" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\InputPersonalization" /v "PreventHandwritingDataSharing" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\Policies\TextInput" /v "AllowLinguisticDataCollection" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Control Panel\International" /v "TurnOffAutocorrectMisspelledWords" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Control Panel\International" /v "TurnOffHighlightMisspelledWords" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Control Panel\International" /v "TurnOffInsertSpace" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Control Panel\International" /v "TurnOffOfferTextPredictions" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Clipboard" /v "EnableClipboardHistory" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Clipboard" /v "EnableCloudClipboard" /t REG_DWORD /d "0" /f

rem == Disable Explorer telemetry, advertising info, recent documents and app tracking ==
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\RunOnce" /v "HttpAcceptLanguageOptOut" /t REG_SZ /d "reg add \"HKCU\Control Panel\International\User Profile\" /v \"HttpAcceptLanguageOptOut\" /t REG_DWORD /d \"1\" /f" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CDP" /v "AllowCDP" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "EnableCdp" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Explorer" /v "Start_TrackProgs" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Explorer" /v "NoCEIP" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Explorer" /v "NoRecentDocsHistory" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Explorer" /v "NoResolveTrack" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Explorer" /v "NoInstrumentation" /t REG_DWORD /d "1" /f

rem == Block executables that collect and transmit telemetry using IFEO redirect ==
rem == (SecurityHealthSystray.exe, SIHClient.exe, WaaSMedicAgent.exe & UsoClient.exe preserved) ==
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AggregatorHost.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\aitstatic.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\CompatTelRunner.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\DeviceCensus.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GameBarPresenceWriter.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\mobsync.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\sdiagnhost.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\smartscreen.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\wsqmcons.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\WerFault.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\WerFaultSecure.exe" /v "Debugger" /t REG_SZ /d "%SystemRoot%\System32\cmd.exe /c exit" /f

rem == Disable Windows Spotlight & cloud content ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsSpotlightFeatures" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableCloudOptimizedContent" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsSpotlightOnActionCenter" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsSpotlightOnSettings" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableThirdPartySuggestions" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableSoftLanding" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableConsumerAccountStateContent" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableConsumerFeatures" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d "1" /f

rem == Disable application compatibility telemetry ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppCompat" /v "AITEnable" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppCompat" /v "DisableInventory" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppCompat" /v "DisablePCA" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppCompat" /v "DisableUAR" /t REG_DWORD /d "1" /f

rem == Disable activity feed ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "EnableActivityFeed" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "PublishUserActivities" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "UploadUserActivities" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "AllowClipboardHistory" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "AllowCrossDeviceClipboard" /t REG_DWORD /d "0" /f

rem == Disable location and sensors ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\LocationAndSensors" /v "DisableLocation" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\LocationAndSensors" /v "DisableLocationScripting" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\LocationAndSensors" /v "DisableSensors" /t REG_DWORD /d "1" /f

rem == Block applications from polling/connecting to Windows Push Notification Service (WNS) ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" /v "NoCloudApplicationNotification" /t REG_DWORD /d "1" /f

rem == Disable all app permissions, sensor access, and cloud-based services ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessAdvertisingId" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsGetDiagnosticInfo" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsRunInBackground" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessTrustedDevices" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessTasks" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsSyncWithDevices" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessRadios" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessPhone" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessNotifications" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessMotion" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessMicrophone" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessMessaging" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessLocation" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessEmail" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessContacts" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessCamera" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessCallHistory" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessCalendar" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessAccountInfo" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsActivateWithVoice" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsActivateWithVoiceAboveLock" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessBackgroundSpatialPerception" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\AppPrivacy" /v "LetAppsAccessGraphicsCaptureProgrammatic" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\Messaging" /v "AllowMessageSync" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\broadFileSystemAccess" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\cellularData" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\documentsLibrary" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\graphicsCaptureProgrammatic" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\picturesLibrary" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\videosLibrary" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam" /v "Value" /t REG_SZ /d "Deny" /f
reg add "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\wifiData" /v "Value" /t REG_SZ /d "Deny" /f

rem == Disable Find My Device ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\FindMyDevice" /v "AllowFindMyDevice" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Microsoft\FindMyDevice" /v "Enabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Microsoft\Settings\FindMyDevice" /v "LocationSyncEnabled" /t REG_DWORD /d "0" /f

rem == Disable storage health telemetry ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\StorageHealth" /v "AllowDiskHealthModelUpdates" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\StorageHealth" /v "DisableStorageHealthTelemetry" /t REG_DWORD /d "1" /f

rem == Prevent syncing settings to and from this PC ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableApplicationSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableAppSyncSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableWebBrowserSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableDesktopThemeSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableWindowsSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableCredentialsSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisablePersonalizationSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableStartLayoutSettingSync" /t REG_DWORD /d "2" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\SettingSync" /v "DisableSettingSyncUserOverride" /t REG_DWORD /d "1" /f

rem == Disable Teredo ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\TCPIP\v6Transition" /v "Teredo_State" /t REG_SZ /d "Disabled" /f

rem == Turn off Apps for Websites ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\System" /v "EnableAppUriHandlers" /t REG_DWORD /d "0" /f

rem == Prevent SmartScreen SystemApp from deploying (CloudExperienceHost, Search, SecHealthUI & Client.CBS preserved) ==
for %%i in (
    Microsoft.Windows.AppRep.ChxApp
) do (
    for /f "tokens=*" %%a in ('reg query "HKLM\SOFTHIVE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications" /f %%i /k ^| findstr /i "InboxApplications"') do (
        if not errorlevel 1 (
            reg delete "%%a" /f
        )
    )
)

rem == Block SmartScreen SystemApp from running via Software Restriction Policies (SRP) ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers" /v "authenticodeenabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers" /v "DefaultLevel" /t REG_DWORD /d "262144" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers" /v "TransparentEnabled" /t REG_DWORD /d "1" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers" /v "PolicyScope" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers" /v "ExecutableTypes" /t REG_MULTI_SZ /d "ADE\ADP\BAS\BAT\CHM\CMD\COM\CPL\CRT\EXE\HLP\HTA\INF\INS\ISP\LNK\MDB\MDE\MSC\MSI\MSP\MST\OCX\PCD\PIF\REG\SCR\SHS\URL\VB\WSC" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\0\Paths\{838cd950-c381-4726-b109-45257ba7f8e3}" /v "Description" /t REG_SZ /d "" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\0\Paths\{838cd950-c381-4726-b109-45257ba7f8e3}" /v "SaferFlags" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\0\Paths\{838cd950-c381-4726-b109-45257ba7f8e3}" /v "ItemData" /t REG_SZ /d "C:\Windows\SystemApps\Microsoft.Windows.AppRep.ChxApp_cw5n1h2txyewy" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\262144\Paths\{191cd7fa-f240-4a17-8986-94d480a6c8ca}" /v "Description" /t REG_SZ /d "" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\262144\Paths\{191cd7fa-f240-4a17-8986-94d480a6c8ca}" /v "SaferFlags" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\262144\Paths\{191cd7fa-f240-4a17-8986-94d480a6c8ca}" /v "ItemData" /t REG_EXPAND_SZ /d "%%SystemRoot%%" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\262144\Paths\{d2c34ab2-529a-46b2-b293-fc853fce72ea}" /v "Description" /t REG_SZ /d "" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\262144\Paths\{d2c34ab2-529a-46b2-b293-fc853fce72ea}" /v "SaferFlags" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\safer\codeidentifiers\262144\Paths\{d2c34ab2-529a-46b2-b293-fc853fce72ea}" /v "ItemData" /t REG_EXPAND_SZ /d "%%ProgramFiles%%" /f

rem == Hide Microsoft Edge from Apps & Features (keep Microsoft Edge Update entry) ==
reg delete "HKLM\SOFTHIVE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f

rem == Disable GameDVR, game capture, and Xbox Game Bar ==
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\GameDVR" /v "AllowGameDVR" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTHIVE\Policies\Microsoft\Windows\GameDVR" /v "AllowGameBar" /t REG_DWORD /d "0" /f

reg unload HKLM\SOFTHIVE
reg load HKLM\SYSHIVE mount\Windows\System32\config\SYSTEM

rem == Configure NCSI to use Debian HTTP probe & OpenDNS DNS probe, and disable passive polling ==
reg add "HKLM\SYSHIVE\ControlSet001\Services\NlaSvc\Parameters\Internet" /v "ActiveWebProbeHost" /t REG_SZ /d "network-test.debian.org" /f
reg add "HKLM\SYSHIVE\ControlSet001\Services\NlaSvc\Parameters\Internet" /v "ActiveWebProbePath" /t REG_SZ /d "nm" /f
reg add "HKLM\SYSHIVE\ControlSet001\Services\NlaSvc\Parameters\Internet" /v "ActiveWebProbeContent" /t REG_SZ /d "NetworkManager is online" /f
reg add "HKLM\SYSHIVE\ControlSet001\Services\NlaSvc\Parameters\Internet" /v "ActiveDnsProbeHost" /t REG_SZ /d "opendns.com" /f
reg add "HKLM\SYSHIVE\ControlSet001\Services\NlaSvc\Parameters\Internet" /v "ActiveDnsProbeContent" /t REG_SZ /d "208.67.222.222" /f
reg add "HKLM\SYSHIVE\ControlSet001\Services\NlaSvc\Parameters\Internet" /v "DisablePassivePolling" /t REG_DWORD /d "1" /f

rem == Switch NTP time server off time.windows.com ==
reg add "HKLM\SYSHIVE\ControlSet001\Services\W32Time\Parameters" /v "NtpServer" /t REG_SZ /d "pool.ntp.org,0x9" /f

rem == Configure WSearch (Windows Search) for Automatic (Delayed Start) ==
reg add "HKLM\SYSHIVE\ControlSet001\Services\WSearch" /v "Start" /t REG_DWORD /d "2" /f
reg add "HKLM\SYSHIVE\ControlSet001\Services\WSearch" /v "DelayedAutostart" /t REG_DWORD /d "1" /f

rem == Delete telemetry & unneeded services ==
rem == (Preserving DusmSvc, WSearch, edgeupdate/edgeupdatem, Windows Update services & Core Defender services) ==
rem == connected devices platform / nearby sharing ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\CDPSvc" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\CDPUserSvc" /f
rem == error reporting ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\wercplsupport" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\WerSvc" /f
rem == inventory, retail demo & wallet ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\InventorySvc" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\RetailDemo" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\WalletService" /f
rem == location ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\lfsvc" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\MapsBroker" /f
rem == logging and tracing ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\diagnosticshub.standardcollector.service" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\dmwappushservice" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\pla" /f
rem == publishing machine name ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\PNRPAutoReg" /f
rem == recording ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\BcastDVRUserService" /f
rem == access to user data such as calendars, contact information, messages and other content ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\OneSyncSvc" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\UnistoreSvc" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\UserDataSvc" /f
rem == windows defender enterprise cloud EDR only (core Defender AV preserved) ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\Sense" /f
rem == windows diagnostics ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\diagsvc" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\DiagTrack" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\DPS" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\WdiServiceHost" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\WdiSystemHost" /f
rem == windows insider ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\wisvc" /f
rem == xbox ==
reg delete "HKLM\SYSHIVE\ControlSet001\Services\XblAuthManager" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\XblGameSave" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\xboxgip" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\XboxGipSvc" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Services\XboxNetApiSvc" /f

rem == Delete autologger telemetry ==
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\AITEventLog" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\CloudExperienceHostOobe" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\DefenderApiLogger" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\DefenderAuditLogger" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\Diagtrack-Listener" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\LwtNetLog" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\SQMLogger" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\WdiContextLog" /f
reg delete "HKLM\SYSHIVE\ControlSet001\Control\WMI\Autologger\WFP-IPsec Trace" /f

reg unload HKLM\SYSHIVE
reg load HKLM\NTUSER mount\Users\Default\NTUSER.DAT

rem == Disable Copilot (if present) ==
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v "AllowWindowsCopilot" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /t REG_DWORD /d "1" /f

rem == Disable OneDrive default user autorun ==
reg delete "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f

rem == Disable typing insights, handwriting personalization, clipboard sync & speech recognition ==
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Input\Settings" /v "InsightsEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Input\Settings" /v "EnableHwkbTextPrediction" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Input\Settings" /v "EnableHwkbAutocorrection2" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\TabletTip\1.7" /v "EnableAutocorrection" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\TabletTip\1.7" /v "EnableSpellchecking" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\TabletTip\1.7" /v "EnableTextPrediction" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\TabletTip\1.7" /v "EnablePredictionSpaceInsertion" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\TabletTip\1.7" /v "EnableDoubleTapSpace" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Input\TIPC" /v "Enabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" /v "HarvestContacts" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Personalization\Settings" /v "AcceptedPrivacyPolicy" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" /v "HasAccepted" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Control Panel\International" /v "TurnOffAutocorrectMisspelledWords" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Control Panel\International" /v "TurnOffHighlightMisspelledWords" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Control Panel\International" /v "TurnOffInsertSpace" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Control Panel\International" /v "TurnOffOfferTextPredictions" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Clipboard" /v "EnableClipboardHistory" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Clipboard" /v "EnableCloudClipboard" /t REG_DWORD /d "0" /f

rem == Disable Explorer telemetry, advertising info, recent documents and app tracking (Indexing Options kept visible) ==
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Id" /t REG_SZ /d "00000000-0000-0000-0000-000000000000" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Start_TrackProgs" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoRecentDocsHistory" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoResolveTrack" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoInstrumentation" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoCEIP" /t REG_DWORD /d "1" /f

rem == Disable Windows telemetry, diagnostics, and feedback ==
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableTailoredExperiencesWithDiagnosticData" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" /v "AllowTelemetry" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Siuf\Rules" /v "NumberOfSIUFInPeriod" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Siuf\Rules" /v "PeriodInNanoSeconds" /t REG_DWORD /d "0" /f

rem == Disable Cortana & web/cloud search permissions ==
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" /v "SafeSearchMode" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" /v "IsMSACloudSearchEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" /v "IsAADCloudSearchEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" /v "IsDeviceSearchHistoryEnabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "DisableWebSearch" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "ConnectedSearchUseWeb" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "ConnectedSearchUseWebOverMeteredConnections" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "EnableAllowedToUseEverywhere" /t REG_DWORD /d "0" /f

rem == Disable Windows Spotlight & cloud content ==
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsSpotlightFeatures" /t REG_DWORD /d "1" /f
reg add "HKLM\NTUSER\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableCloudOptimizedContent" /t REG_DWORD /d "1" /f

rem == Disable GameDVR, game capture, and Xbox Game Bar ==
reg add "HKLM\NTUSER\SYSTEM\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\GameBar" /v "ShowStartupPanel" /t REG_DWORD /d "0" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\GameBar" /v "GamePanelStartupTipIndex" /t REG_DWORD /d "3" /f
reg add "HKLM\NTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d "0" /f

reg unload HKLM\NTUSER
rem == done disabling telemetry ==

rem == Delete Edge browser only (preserve EdgeCore, EdgeWebView & EdgeUpdate) ==
if exist "mount\Program Files (x86)\Microsoft\Edge" (
    rmdir /q /s "mount\Program Files (x86)\Microsoft\Edge"
)

rem == Disable Windows features with telemetry (SearchEngine-Client-Package & Windows-Defender-Default-Definitions preserved) ==
dism /scratchdir:temp /image:mount /disable-feature /featurename:Internet-Explorer-Optional-amd64
dism /scratchdir:temp /image:mount /disable-feature /featurename:MediaPlayback
dism /scratchdir:temp /image:mount /disable-feature /featurename:WindowsMediaPlayer

rem == Remove capabilities with telemetry ==
dism /scratchdir:temp /image:mount /Remove-Capability /CapabilityName:Browser.InternetExplorer~~~~0.0.11.0
dism /scratchdir:temp /image:mount /Remove-Capability /CapabilityName:Media.WindowsMediaPlayer~~~~0.0.12.0

rem == Offline verification scan to check component store for file corruption ==
dism /scratchdir:temp /Image:mount /Cleanup-Image /ScanHealth

rem == Commit changes and unmount install.wim ==
dism /unmount-image /mountdir:mount /commit

rem == Rebuild install.wim ==
dism /Export-Image /SourceImageFile:install.wim /SourceIndex:1 /DestinationImageFile:install2.wim /checkintegrity
del /f /q install.wim
ren install2.wim install.wim

rem == Delete mount and temp folders ==
rd /s /q mount
rd /s /q temp

exit
