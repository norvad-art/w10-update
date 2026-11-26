#requires -RunAsAdministrator

<#
.SYNOPSIS
    Elevate_as_TI.ps1 - Version 1.5
    Launches files with TrustedInstaller privileges by escalating from Administrator to SYSTEM to TI.

.DESCRIPTION
    Escalates privileges: Administrator -> SYSTEM (via winlogon) -> TrustedInstaller.
    Supports: .exe, .com, .bat, .cmd, .ps1, .vbs, .js, .wsf, .lnk.

.NOTES
    Concept: freddie-o (forums.mydigitallife.net)

    Technical Implementation: Multi-pass coding, security auditing, and final edits by Claude,
                              with feedback and review from DeepSeek, Replit and Grok.

    This script was developed and optimized through collaborative AI teamwork.
    Please keep this credit block intact when sharing or modifying.

.CHANGELOG
    1.5 – Fixes: (1) CreateEnvironmentBlock failure now aborts with a clear error instead
              of silently falling back to the caller's Administrator environment.
              (2) SeDebugPrivilege / SeImpersonatePrivilege enables on the caller token
              are now verified; the script aborts if either fails. Restore-phase
              DisablePrivilege failures are surfaced as warnings rather than silently
              discarded. (3) Shell metacharacters in -Arguments now cause an immediate
              abort for .bat/.cmd targets (a non-blocking warning was insufficient for
              arguments placed inside a cmd.exe /c call). (4) TrustedInstaller PID
              polling replaced Get-CimInstance with Get-Process for lower overhead.

    1.4 – Privacy: Added -NoLog switch. When passed, Write-Log skips all disk I/O
              (no file is created or appended to). Console/verbose output is unaffected.
              C:\Windows\Logs is still used when logging is active because its ACLs
              prevent symlink attacks that a world-writable path (e.g. $env:TEMP) would not.

    1.3 – Fix and UX Improvement: $FilePath is now optional — when right-clicking the script, 
	          a file picker dialog opens instead of a raw console prompt. Paths dragged 
			  from Explorer no longer trigger "Illegal characters in path."

    1.2 – Fix: handles and privileges could leak on early-return paths; impersonation 
	          setup and launch are now merged into one block. EnablePrivilege/DisablePrivilege 
			  also now verify the result of AdjustTokenPrivileges so failures are caught 
			  rather than silently ignored.

    1.1 - Fix: .bat/.cmd and default command-line builder left a trailing space inside the
              outer CMD quote pair when $Arguments was empty, causing CMD to misparse the
              argument string. Now uses the same IsNullOrEmpty conditional as .exe/.com.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$FilePath = "",
    [Parameter(Mandatory=$false)][string]$Arguments = "",
    [Parameter(Mandatory=$false)][switch]$Hidden,
    [Parameter(Mandatory=$false)][string]$WorkingDirectory = "",
    [Parameter(Mandatory=$false)][switch]$Wait,
    [Parameter(Mandatory=$false)][switch]$PassThru,
    # Opt-in flag to log full arguments (off by default to avoid secrets in logs)
    [Parameter(Mandatory=$false)][switch]$LogArguments,
    # Opt-out flag to disable all file logging for privacy
    [Parameter(Mandatory=$false)][switch]$NoLog
)

$ScriptVersion        = '1.5'

# $env:SystemRoot\Logs is ACL'd to Administrators/SYSTEM only (prevents symlink attacks).
# Pass -NoLog to disable all file logging for privacy (console output is unaffected).
$LogFile             = Join-Path "$env:SystemRoot\Logs" "Elevate_as_TI.log"
$MaxLogSize          = 1MB
$ServiceStartTimeout = 30
$AllowedExtensions   = @('.exe', '.com', '.bat', '.cmd', '.ps1', '.vbs', '.js', '.wsf')

if ($PSVersionTable.PSVersion.Major -lt 5 -or
    ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Error "PowerShell 5.1 or higher is required."
    exit 1
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error')][string]$Level = 'Info'
    )
    # When -NoLog is active, only emit to the console -- nothing touches disk.
    if (-not $script:NoLog) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "$timestamp [$Level]: $Message"
        if (Test-Path $LogFile -PathType Leaf) {
            if ((Get-Item $LogFile).Length -gt $MaxLogSize) {
                Move-Item $LogFile "$LogFile.old" -Force -ErrorAction SilentlyContinue
            }
        }
        $line | Out-File -FilePath $LogFile -Append -ErrorAction SilentlyContinue
    }
    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error   $Message }
        default   { Write-Verbose $Message -Verbose }
    }
}

function Release-FileHandle {
    if ($script:fileHandle) {
        $script:fileHandle.Close()
        $script:fileHandle = $null
        Write-Log "Read lock released on: $script:lockTarget"
    }
}

Write-Log "=== Script started (v$ScriptVersion) ==="

# ---------------------------------------------------------------------------
# Strip surrounding quotes that Explorer/drag-and-drop adds around paths with
# spaces, then fall back to a GUI file picker when no path was supplied at all.
# ---------------------------------------------------------------------------
$FilePath = $FilePath.Trim('"').Trim("'")

if ([string]::IsNullOrEmpty($FilePath)) {
    Write-Log "No FilePath supplied -- opening file picker dialog."
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = "Select file to run as TrustedInstaller"
    $dlg.Filter = "Supported Files|*.exe;*.com;*.bat;*.cmd;*.ps1;*.vbs;*.js;*.wsf;*.lnk|All Files|*.*"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Log "File picker cancelled by user. Exiting."
        exit 0
    }
    $FilePath = $dlg.FileName
    Write-Log "File picker selection: $FilePath"
}

if ($PassThru -and -not $Wait) {
    Write-Log "-PassThru has no effect without -Wait. Exit code will not be captured." -Level Warning
}

try {
    $FilePath = [System.IO.Path]::GetFullPath($FilePath)
} catch {
    Write-Log "Invalid file path: $FilePath -- $_" -Level Error
    exit 1
}

if (-not (Test-Path -LiteralPath $FilePath)) {
    Write-Log "File not found: $FilePath" -Level Error
    exit 1
}

$extension  = [System.IO.Path]::GetExtension($FilePath).ToLower()
$lnkWorkDir = ""

if ($extension -eq ".lnk") {
    $shell    = New-Object -ComObject WScript.Shell
    try {
        $shortcut  = $shell.CreateShortcut($FilePath)
        $lnkTarget = $shortcut.TargetPath
        $lnkArgs   = $shortcut.Arguments
        $lnkWorkDir = $shortcut.WorkingDirectory
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }

    if (-not $lnkTarget) {
        Write-Log "Could not resolve shortcut target: $FilePath" -Level Error
        exit 1
    }
    Write-Log "Shortcut resolved to: $lnkTarget"
    if (-not (Test-Path -LiteralPath $lnkTarget)) {
        Write-Log "Resolved shortcut target does not exist: $lnkTarget" -Level Error
        exit 1
    }
    $resolvedExt = [System.IO.Path]::GetExtension($lnkTarget).ToLower()
    if ($resolvedExt -notin $AllowedExtensions) {
        Write-Log "Shortcut target extension [$resolvedExt] is not in AllowedExtensions. Update the list if intentional." -Level Error
        exit 1
    }
    $FilePath  = $lnkTarget
    if ([string]::IsNullOrEmpty($Arguments) -and -not [string]::IsNullOrEmpty($lnkArgs)) {
        $Arguments = $lnkArgs
    }
    $extension = $resolvedExt
}

if ($Arguments -match '[&|><;("`)]') {
    if ($extension -in '.bat', '.cmd') {
        Write-Log "Arguments contain shell metacharacters (&, |, >, <, etc.) which cannot be safely quoted inside a cmd.exe /c call. Aborting." -Level Error
        exit 1
    }
    Write-Log "Arguments contains shell metacharacters. Ensure the string is from a trusted source." -Level Warning
}

switch ($extension) {
    { $_ -in '.exe', '.com' } {
        $commandLine = if ([string]::IsNullOrEmpty($Arguments)) {
            "`"$FilePath`""
        } else {
            "`"$FilePath`" $Arguments"
        }
        $targetExe = $FilePath
    }
    { $_ -in '.bat', '.cmd' } {
        $targetExe   = "$env:SystemRoot\System32\cmd.exe"
        $inner       = if ([string]::IsNullOrEmpty($Arguments)) {
                           "`"$FilePath`""
                       } else {
                           "`"$FilePath`" $Arguments"
                       }
        $commandLine = "`"$targetExe`" /c `"$inner`""
    }
    '.ps1' {
        # Use current process path to support both Windows PowerShell and PowerShell Core
        $targetExe   = (Get-Process -Id $PID).Path
        $commandLine = "`"$targetExe`" -ExecutionPolicy Bypass -File `"$FilePath`" $Arguments".Trim()
    }
    { $_ -in '.vbs', '.js', '.wsf' } {
        $targetExe   = "$env:SystemRoot\System32\wscript.exe"
        $commandLine = "`"$targetExe`" `"$FilePath`" $Arguments".Trim()
    }
    default {
        $targetExe   = "$env:SystemRoot\System32\cmd.exe"
        $inner       = if ([string]::IsNullOrEmpty($Arguments)) {
                           "`"$FilePath`""
                       } else {
                           "`"$FilePath`" $Arguments"
                       }
        $commandLine = "`"$targetExe`" /c `"$inner`""
    }
}

# Verify host executable before handing off to C# to avoid a cryptic Win32 failure
if (-not (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
    Write-Log "Host executable not found: $targetExe" -Level Error
    exit 1
}

# Redact arguments from log by default. Use -LogArguments to log the full command line.
if ($LogArguments) {
    Write-Log "Command line: $commandLine"
} else {
    $argNote = if ([string]::IsNullOrEmpty($Arguments)) { "" } else { " [arguments redacted -- use -LogArguments to enable]" }
    Write-Log "Command line: `"$targetExe`" `"$FilePath`"$argNote"
}

# Open a shared read lock on the target file immediately after validation and hold it
# until just before launch. This prevents the file from being replaced or deleted in
# the window between our existence check and CreateProcessWithTokenW.
# Note: applies to direct targets (.exe/.com/.ps1 etc.), not script host wrappers.
$script:fileHandle = $null
$script:lockTarget = $FilePath  # always the resolved final target path
try {
    $script:fileHandle = [System.IO.File]::Open(
        $script:lockTarget,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read   # allow concurrent reads; block delete/replace
    )
    Write-Log "Read lock acquired on: $script:lockTarget"
}
catch {
    Write-Log "Could not acquire read lock on target file: $script:lockTarget -- $_" -Level Error
    exit 1
}

$csharp = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.ComponentModel;

public static class TILauncher
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb;
        public IntPtr lpReserved;
        public string lpDesktop;
        public IntPtr lpTitle;
        public int dwX, dwY, dwXSize, dwYSize;
        public int dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION
    {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    struct LUID_AND_ATTR { public LUID Luid; public uint Attributes; }

    [StructLayout(LayoutKind.Sequential)]
    struct TOKEN_PRIVILEGES
    {
        public uint PrivilegeCount;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 1)]
        public LUID_AND_ATTR[] Privileges;
    }

    const uint PROCESS_QUERY_INFO        = 0x0400;
    const uint PROCESS_QUERY_LIMITED     = 0x1000;
    const uint TOKEN_DUPLICATE           = 0x0002;
    const uint TOKEN_QUERY               = 0x0008;
    const uint TOKEN_ASSIGN_PRIMARY      = 0x0001;
    const uint TOKEN_ADJUST_SESSIONID    = 0x0100;
    const uint TOKEN_ADJUST_PRIVILEGES   = 0x0020;
    const uint TOKEN_ALL_ACCESS          = 0xF01FF;
    const int  SecurityImpersonation     = 2;
    const int  TokenPrimary              = 1;
    const int  TokenImpersonation        = 2;
    const int  TokenSessionId            = 12;
    const uint SE_PRIVILEGE_ENABLED      = 0x00000002;
    const uint CREATE_NEW_CONSOLE        = 0x00000010;
    const uint CREATE_NO_WINDOW          = 0x08000000;
    const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    const uint STARTF_USESHOWWINDOW      = 0x00000001;
    const short SW_HIDE                  = 0;
    const uint WAIT_OBJECT_0             = 0x00000000;
    const uint WTS_INVALID_SESSION       = 0xFFFFFFFF;
    const int  ERROR_NOT_ALL_ASSIGNED    = 1300;

    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint a, bool b, int c);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr a);
    [DllImport("kernel32.dll")] static extern uint WTSGetActiveConsoleSessionId();
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr handle, out uint exitCode);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool DuplicateTokenEx(IntPtr existing, uint access, IntPtr attrs, int impLevel, int type, out IntPtr newToken);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool SetTokenInformation(IntPtr token, int cls, ref uint info, uint len);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool ImpersonateLoggedOnUser(IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool RevertToSelf();
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool LookupPrivilegeValue(string host, string name, out LUID luid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disable, ref TOKEN_PRIVILEGES newState, uint bufLen, IntPtr prev, IntPtr retLen);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessWithTokenW(IntPtr token, uint logonFlags, string app, string cmdLine, uint creation, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [DllImport("userenv.dll", SetLastError = true)]
    static extern bool CreateEnvironmentBlock(out IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

    [DllImport("userenv.dll", SetLastError = true)]
    static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool GetTokenInformation(IntPtr hToken, int tokenInfoClass,
        IntPtr tokenInfo, uint tokenInfoLength, out uint returnLength);

    static readonly string[] AllPrivileges = {
        "SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege",
        "SeBackupPrivilege",             "SeChangeNotifyPrivilege",
        "SeCreateGlobalPrivilege",       "SeCreatePagefilePrivilege",
        "SeCreatePermanentPrivilege",    "SeCreateSymbolicLinkPrivilege",
        "SeCreateTokenPrivilege",        "SeDebugPrivilege",
        "SeDelegateSessionUserImpersonatePrivilege",
        "SeImpersonatePrivilege",        "SeIncreaseBasePriorityPrivilege",
        "SeIncreaseQuotaPrivilege",      "SeIncreaseWorkingSetPrivilege",
        "SeLoadDriverPrivilege",         "SeLockMemoryPrivilege",
        "SeManageVolumePrivilege",       "SeProfileSingleProcessPrivilege",
        "SeRelabelPrivilege",            "SeRemoteShutdownPrivilege",
        "SeRestorePrivilege",            "SeSecurityPrivilege",
        "SeShutdownPrivilege",           "SeSystemEnvironmentPrivilege",
        "SeSystemProfilePrivilege",      "SeSystemtimePrivilege",
        "SeTakeOwnershipPrivilege",      "SeTcbPrivilege",
        "SeTimeZonePrivilege",           "SeUndockPrivilege"
    };

    static string GetWin32Error(string context, int lastError)
    {
        return string.Format("{0}: {1} (error {2})", context, new Win32Exception(lastError).Message, lastError);
    }

    // ERROR_NOT_ALL_ASSIGNED (1300) indicates the privilege wasn't on the token at all.
    // AdjustTokenPrivileges returning FALSE is also treated as a failure.
    static bool EnablePrivilege(IntPtr hToken, string name)
    {
        LUID luid;
        if (!LookupPrivilegeValue(null, name, out luid)) return false;
        var tp = new TOKEN_PRIVILEGES
        {
            PrivilegeCount = 1,
            Privileges = new LUID_AND_ATTR[] { new LUID_AND_ATTR { Luid = luid, Attributes = SE_PRIVILEGE_ENABLED } }
        };
        bool ok = AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int err = Marshal.GetLastWin32Error();
        return ok && err != ERROR_NOT_ALL_ASSIGNED;
    }

    // Disables a privilege (Attributes = 0) -- used to restore privileges to their
    // original state after use.
    static bool DisablePrivilege(IntPtr hToken, string name)
    {
        LUID luid;
        if (!LookupPrivilegeValue(null, name, out luid)) return false;
        var tp = new TOKEN_PRIVILEGES
        {
            PrivilegeCount = 1,
            Privileges = new LUID_AND_ATTR[] { new LUID_AND_ATTR { Luid = luid, Attributes = 0 } }
        };
        bool ok = AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int err = Marshal.GetLastWin32Error();
        return ok && err != ERROR_NOT_ALL_ASSIGNED;
    }

    // Checks whether a privilege is currently enabled on a token,
    // so it can be restored to its original state rather than always disabled.
    static bool IsPrivilegeEnabled(IntPtr hToken, string name)
    {
        LUID luid;
        if (!LookupPrivilegeValue(null, name, out luid)) return false;

        uint returnLength = 0;
        GetTokenInformation(hToken, 3 /*TokenPrivileges*/, IntPtr.Zero, 0, out returnLength);
        if (returnLength == 0) return false;

        IntPtr buffer = Marshal.AllocHGlobal((int)returnLength);
        try
        {
            if (!GetTokenInformation(hToken, 3, buffer, returnLength, out returnLength))
                return false;

            uint count = (uint)Marshal.ReadInt32(buffer);
            int offset = sizeof(uint); // skip PrivilegeCount field
            for (uint i = 0; i < count; i++)
            {
                uint low  = (uint)Marshal.ReadInt32(buffer, offset);
                int  high =       Marshal.ReadInt32(buffer, offset + 4);
                uint attr = (uint)Marshal.ReadInt32(buffer, offset + 8);
                offset += 12; // sizeof(LUID_AND_ATTR)

                if (low == luid.LowPart && high == luid.HighPart)
                    return (attr & SE_PRIVILEGE_ENABLED) != 0;
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
        return false;
    }

    static IntPtr TryOpenProcess(int pid)
    {
        IntPtr h = OpenProcess(PROCESS_QUERY_INFO, false, pid);
        if (h == IntPtr.Zero) h = OpenProcess(PROCESS_QUERY_LIMITED, false, pid);
        return h;
    }

    // Exposes CloseHandle publicly so PowerShell can release the child process handle
    public static void CloseProcessHandle(IntPtr handle)
    {
        if (handle != IntPtr.Zero) CloseHandle(handle);
    }

    // timeoutMs = 0xFFFFFFFF means INFINITE
    public static bool WaitForProcess(IntPtr hProcess, uint timeoutMs)
    {
        return WaitForSingleObject(hProcess, timeoutMs) == WAIT_OBJECT_0;
    }

    // Returns -1 if the call fails; STILL_ACTIVE (259) means process has not exited yet
    public static int GetProcessExitCode(IntPtr hProcess)
    {
        uint code;
        if (!GetExitCodeProcess(hProcess, out code)) return -1;
        return (int)code;
    }

    public static string Launch(int winlogonPid, int tiPid, string commandLine, string workDir, bool hidden, out IntPtr hProcess, out int childPid, out string launchWarnings)
    {
        hProcess = IntPtr.Zero;
        childPid = 0;
        launchWarnings = null;
        var warnList = new System.Collections.Generic.List<string>();
        int lastError;

        // Step 1: Enable SeDebugPrivilege and SeImpersonatePrivilege on our own token.
        // Record the original enabled state of both so they can be restored afterward.
        IntPtr selfToken = IntPtr.Zero;
        bool debugWasAlreadyEnabled       = false;
        bool impersonateWasAlreadyEnabled = false;

        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out selfToken))
            return GetWin32Error("OpenProcessToken(self)", Marshal.GetLastWin32Error());
        try
        {
            debugWasAlreadyEnabled       = IsPrivilegeEnabled(selfToken, "SeDebugPrivilege");
            impersonateWasAlreadyEnabled = IsPrivilegeEnabled(selfToken, "SeImpersonatePrivilege");
            if (!EnablePrivilege(selfToken, "SeDebugPrivilege"))
                return "EnablePrivilege(SeDebugPrivilege) failed on caller token; cannot impersonate.";
            if (!EnablePrivilege(selfToken, "SeImpersonatePrivilege"))
                return "EnablePrivilege(SeImpersonatePrivilege) failed on caller token; cannot impersonate.";
        }
        finally
        {
            CloseHandle(selfToken);
        }

        // Single outer try/finally wraps both impersonation setup AND launch so that
        // every cleanup action (handle closes, RevertToSelf, privilege restore) runs on
        // every code path, including early returns from inside the impersonation step.
        IntPtr hSystemImpersonation = IntPtr.Zero;
        IntPtr hTI      = IntPtr.Zero;
        IntPtr hTITok   = IntPtr.Zero;
        IntPtr hPrimary = IntPtr.Zero;
        try
        {
            // ---- Step 2 + 3: open winlogon, duplicate SYSTEM token, impersonate ----
            IntPtr hWinlogon = TryOpenProcess(winlogonPid);
            if (hWinlogon == IntPtr.Zero)
                return GetWin32Error("OpenProcess(winlogon)", Marshal.GetLastWin32Error());

            IntPtr hWinlogonToken = IntPtr.Zero;
            try
            {
                if (!OpenProcessToken(hWinlogon, TOKEN_DUPLICATE | TOKEN_QUERY, out hWinlogonToken))
                {
                    lastError = Marshal.GetLastWin32Error();
                    return GetWin32Error("OpenProcessToken(winlogon)", lastError);
                }
                if (!DuplicateTokenEx(hWinlogonToken, TOKEN_ALL_ACCESS, IntPtr.Zero,
                        SecurityImpersonation, TokenImpersonation, out hSystemImpersonation))
                {
                    lastError = Marshal.GetLastWin32Error();
                    return GetWin32Error("DuplicateTokenEx(winlogon->impersonation)", lastError);
                }
                if (!ImpersonateLoggedOnUser(hSystemImpersonation))
                {
                    lastError = Marshal.GetLastWin32Error();
                    return GetWin32Error("ImpersonateLoggedOnUser(SYSTEM)", lastError);
                }
            }
            finally
            {
                if (hWinlogonToken != IntPtr.Zero) CloseHandle(hWinlogonToken);
                CloseHandle(hWinlogon);
                // hSystemImpersonation is closed by the outer finally
            }

            // ---- Step 4: Open TrustedInstaller process ----
            hTI = TryOpenProcess(tiPid);
            if (hTI == IntPtr.Zero)
            {
                lastError = Marshal.GetLastWin32Error();
                return GetWin32Error("OpenProcess(TrustedInstaller)", lastError);
            }
            if (!OpenProcessToken(hTI,
                    TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_SESSIONID,
                    out hTITok))
            {
                lastError = Marshal.GetLastWin32Error();
                return GetWin32Error("OpenProcessToken(TrustedInstaller)", lastError);
            }

            // ---- Step 5: Duplicate as primary token for CreateProcessWithTokenW ----
            if (!DuplicateTokenEx(hTITok, TOKEN_ALL_ACCESS, IntPtr.Zero,
                    SecurityImpersonation, TokenPrimary, out hPrimary))
            {
                lastError = Marshal.GetLastWin32Error();
                return GetWin32Error("DuplicateTokenEx(TrustedInstaller->primary)", lastError);
            }

            // Step 5b: Enable all available privileges on the TI token.
            // Some privileges may not be present on this token; silently skip any that cannot be enabled.
            foreach (string priv in AllPrivileges)
                EnablePrivilege(hPrimary, priv);

            // ---- Step 6: Retarget token to active interactive desktop session ----
            uint sessionId = WTSGetActiveConsoleSessionId();
            if (sessionId == WTS_INVALID_SESSION)
            {
                using (var self = Process.GetCurrentProcess())
                {
                    sessionId = (uint)self.SessionId;
                }
            }
            if (!SetTokenInformation(hPrimary, TokenSessionId, ref sessionId, sizeof(uint)))
            {
                lastError = Marshal.GetLastWin32Error();
                return GetWin32Error("SetTokenInformation", lastError);
            }

            // ---- Step 7: Revert impersonation BEFORE launching ----
            // CreateProcessWithTokenW checks SeImpersonatePrivilege on the caller's
            // effective token. We want that to be our process token (Administrator),
            // not the SYSTEM impersonation token.
            RevertToSelf();

            // ---- Step 8: Build STARTUPINFO and launch ----
            var si = new STARTUPINFO();
            si.cb        = Marshal.SizeOf(si);
            si.lpDesktop = "winsta0\\default";

            uint creationFlags;
            if (hidden)
            {
                creationFlags  = CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT;
                si.dwFlags     = (int)STARTF_USESHOWWINDOW;
                si.wShowWindow = SW_HIDE;
            }
            else
            {
                creationFlags = CREATE_NEW_CONSOLE | CREATE_UNICODE_ENVIRONMENT;
            }

            // Build a correct environment block keyed to the TrustedInstaller token.
            // Without this the child would inherit the caller's Administrator environment
            // (wrong USERNAME, USERPROFILE, TEMP, etc.).
            // Failure is fatal: proceeding with a null block would silently pass the wrong
            // environment to the TI process, which is worse than a clean abort.
            IntPtr hEnvBlock = IntPtr.Zero;
            if (!CreateEnvironmentBlock(out hEnvBlock, hPrimary, false))
            {
                lastError = Marshal.GetLastWin32Error();
                return GetWin32Error("CreateEnvironmentBlock", lastError);
            }

            // Wrap the launch in a dedicated try/finally so DestroyEnvironmentBlock
            // runs even if CreateProcessWithTokenW raises an unmanaged exception.
            // P/Invoke bool returns shouldn't throw in practice, but structural cleanup
            // beats relying on that assumption.
            PROCESS_INFORMATION pi;
            bool launched;
            try
            {
                launched = CreateProcessWithTokenW(hPrimary, 0, null, commandLine,
                        creationFlags,
                        hEnvBlock,
                        string.IsNullOrEmpty(workDir) ? null : workDir,
                        ref si, out pi);
            }
            finally
            {
                if (hEnvBlock != IntPtr.Zero) DestroyEnvironmentBlock(hEnvBlock);
            }

            if (!launched)
            {
                lastError = Marshal.GetLastWin32Error();
                return GetWin32Error("CreateProcessWithTokenW", lastError);
            }
            hProcess = pi.hProcess;
            childPid = pi.dwProcessId;
            CloseHandle(pi.hThread);
            return null;
        }
        finally
        {
            // Handle cleanup
            if (hPrimary != IntPtr.Zero) CloseHandle(hPrimary);
            if (hTITok   != IntPtr.Zero) CloseHandle(hTITok);
            if (hTI      != IntPtr.Zero) CloseHandle(hTI);

            // Safety net: always revert impersonation (harmless if already reverted).
            // The explicit RevertToSelf() in Step 7 is the "real" one used by the success
            // path; this catches early-return paths where Step 7 was never reached.
            RevertToSelf();

            if (hSystemImpersonation != IntPtr.Zero) CloseHandle(hSystemImpersonation);

            // Privilege restore must run AFTER CreateProcessWithTokenW on every code path.
            // Restoring before the launch would break the call when the caller did not
            // already have SeImpersonatePrivilege enabled. This also runs on early-return
            // failures (e.g. ImpersonateLoggedOnUser failed); DisablePrivilege on a
            // privilege we just enabled in Step 1 is safe.
            IntPtr selfTokenRestore = IntPtr.Zero;
            if (OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out selfTokenRestore))
            {
                try
                {
                    if (!debugWasAlreadyEnabled)
                    {
                        if (!DisablePrivilege(selfTokenRestore, "SeDebugPrivilege"))
                            warnList.Add("DisablePrivilege(SeDebugPrivilege) failed; SeDebugPrivilege may remain enabled on this session's token.");
                    }
                    if (!impersonateWasAlreadyEnabled)
                    {
                        if (!DisablePrivilege(selfTokenRestore, "SeImpersonatePrivilege"))
                            warnList.Add("DisablePrivilege(SeImpersonatePrivilege) failed; SeImpersonatePrivilege may remain enabled on this session's token.");
                    }
                }
                finally { CloseHandle(selfTokenRestore); }
            }
            launchWarnings = warnList.Count > 0 ? string.Join(" | ", warnList) : null;
        }
    }
}
"@

# Guard against re-running in the same session. Add-Type would otherwise throw
# "type already exists" on the second invocation.
if (-not ('TILauncher' -as [type])) {
    try {
        Add-Type -TypeDefinition $csharp -Language CSharp -ErrorAction Stop
        Write-Log "WinAPI layer compiled successfully."
    }
    catch {
        Write-Log "Failed to compile C# code: $_" -Level Error
        Release-FileHandle
        exit 1
    }
}
else {
    Write-Log "WinAPI layer already loaded in this session; skipping Add-Type."
}

try {
    $svc = Get-Service -Name TrustedInstaller -ErrorAction Stop
    if ($svc.Status -ne "Running") {
        Write-Log "Starting TrustedInstaller service..."
        Start-Service -Name TrustedInstaller -ErrorAction Stop
        try {
            $svc.WaitForStatus("Running", (New-TimeSpan -Seconds $ServiceStartTimeout))
        }
        catch {
            $svc.Refresh()
            $msg = "TrustedInstaller did not reach Running state within {0}s. State: {1}." -f $ServiceStartTimeout, $svc.Status
            Write-Log $msg -Level Error
            Release-FileHandle
            exit 1
        }
    }
    Write-Log "TrustedInstaller service is running."
}
catch {
    Write-Log "Error managing TrustedInstaller service: $_" -Level Error
    Release-FileHandle
    exit 1
}

$tiPid = $null
for ($i = 0; $i -lt 10; $i++) {
    $tiProc = Get-Process -Name TrustedInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tiProc -and $tiProc.Id -ne 0) { $tiPid = $tiProc.Id; break }
    Start-Sleep -Milliseconds 300
}
if (-not $tiPid -or $tiPid -eq 0) {
    Write-Log "Could not retrieve TrustedInstaller PID after retries." -Level Error
    Release-FileHandle
    exit 1
}
Write-Log "TrustedInstaller PID: $tiPid"

# Prefer winlogon in our session; fall back to first found
$currentSessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
$winlogon = Get-Process -Name winlogon -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $currentSessionId } |
            Select-Object -First 1
if (-not $winlogon) {
    Write-Log "No winlogon.exe in session $currentSessionId; using first available." -Level Warning
    $winlogon = Get-Process -Name winlogon -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $winlogon) {
    Write-Log "Could not find any winlogon.exe process." -Level Error
    Release-FileHandle
    exit 1
}
$winlogonPid = $winlogon.Id
Write-Log "winlogon PID: $winlogonPid (Session $($winlogon.SessionId))"

# Priority: .lnk shortcut > -WorkingDirectory param > target file's directory (Explorer default)
if ($lnkWorkDir -and $WorkingDirectory -and $lnkWorkDir -ne $WorkingDirectory) {
    Write-Log "-WorkingDirectory '$WorkingDirectory' ignored; using shortcut's working directory '$lnkWorkDir' instead." -Level Warning
}
$workDir = if ($lnkWorkDir) { $lnkWorkDir } elseif ($WorkingDirectory) { $WorkingDirectory } else { [System.IO.Path]::GetDirectoryName($FilePath) }

$hProcess       = [IntPtr]::Zero
$childPid       = 0
$hProcessClosed = $false

# Release the read lock immediately before handing off to CreateProcessWithTokenW.
# The lock has served its purpose -- it prevented any swap during the setup phase.
Release-FileHandle

$launchWarnings = $null
$err = [TILauncher]::Launch(
    [int]$winlogonPid,
    [int]$tiPid,
    $commandLine,
    $workDir,
    $Hidden.IsPresent,
    [ref]$hProcess,
    [ref]$childPid,
    [ref]$launchWarnings
)
if ($launchWarnings) {
    Write-Log "Launch warnings: $launchWarnings" -Level Warning
}
if ($err) {
    Write-Log "Launch failed: $err" -Level Error
    exit 1
}
Write-Log "SUCCESS -- process launched as TrustedInstaller (PID: $childPid)"

# Uses Win32 hProcess handle from Launch() -- GetProcessById() cannot read ExitCode
# cross-privilege (TrustedInstaller -> Administrator), but this handle has full access.
if ($Wait -and $hProcess -ne [IntPtr]::Zero) {
    Write-Log "Waiting for process PID $childPid to exit..."
    $exited = [TILauncher]::WaitForProcess($hProcess, [uint32]::MaxValue)
    if ($exited) {
        $exitCode = [TILauncher]::GetProcessExitCode($hProcess)
        Write-Log "Process exited with code $exitCode"
        if ($PassThru) {
            [TILauncher]::CloseProcessHandle($hProcess)
            $hProcessClosed = $true
            Write-Log "=== Done (exit code: $exitCode). Log: $LogFile ==="
            exit $exitCode
        }
    } else {
        Write-Log "WaitForProcess returned unexpectedly (timeout or error)." -Level Warning
    }
}

if (-not $hProcessClosed -and $hProcess -ne [IntPtr]::Zero) {
    [TILauncher]::CloseProcessHandle($hProcess)
}

Write-Log "=== Done. Log: $LogFile ==="
