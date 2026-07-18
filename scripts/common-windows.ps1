#requires -Version 5.1

$script:CodexWindowsPackageName = "OpenAI.Codex"
$script:CodexWindowsPackageFamilyName = "OpenAI.Codex_2p2nqsd0c76g0"
$script:CodexWindowsPublisher = "CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B"
$script:CodexWindowsPublisherId = "2p2nqsd0c76g0"
$script:CodexWindowsMarketplaceIssuer = "Microsoft Marketplace CA"
$script:CodexWindowsStateRoot = Join-Path $env:LOCALAPPDATA "CodexImmersiveSkin"
$script:CodexWindowsStatePath = Join-Path $script:CodexWindowsStateRoot "state.json"
$script:CodexWindowsValidatedPackages = @{}
$script:CodexWindowsStrictUtf8 = New-Object Text.UTF8Encoding($false, $true)

function ConvertTo-CodexWindowsRemainingArguments {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Values
  )

  foreach ($value in @($Values)) {
    if ([string]::IsNullOrEmpty([string]$value)) { continue }
    [string]$value
  }
}

function Read-CodexWindowsUtf8Text {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "The required UTF-8 file does not exist: $(ConvertTo-CodexSafePath $Path)"
  }
  [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), $script:CodexWindowsStrictUtf8)
}

function ConvertTo-CodexSafePath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [AllowEmptyString()]
    [string]$Path
  )

  process {
    $value = $Path
    foreach ($replacement in @(
      @($env:LOCALAPPDATA, "%LOCALAPPDATA%"),
      @($env:APPDATA, "%APPDATA%"),
      @($env:USERPROFILE, "%USERPROFILE%"),
      @($env:ProgramFiles, "%ProgramFiles%")
    )) {
      if (-not [string]::IsNullOrWhiteSpace($replacement[0])) {
        $value = [regex]::Replace(
          $value,
          [regex]::Escape([string]$replacement[0]),
          [string]$replacement[1],
          [Text.RegularExpressions.RegexOptions]::IgnoreCase)
      }
    }
    $value
  }
}

function Test-CodexWindowsPathEqual {
  param(
    [Parameter(Mandatory = $true)][string]$First,
    [Parameter(Mandatory = $true)][string]$Second
  )

  try {
    $firstFull = [IO.Path]::GetFullPath($First).TrimEnd('\')
    $secondFull = [IO.Path]::GetFullPath($Second).TrimEnd('\')
    return [string]::Equals($firstFull, $secondFull, [StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Test-CodexWindowsPathWithin {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )

  try {
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $candidate.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Test-CodexWindowsPathChainNoReparse {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Boundary
  )

  try {
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    if (-not (Test-CodexWindowsPathEqual -First $candidate -Second $root) -and
        -not (Test-CodexWindowsPathWithin -Path $candidate -Root $root)) { return $false }

    $current = $candidate
    while ($true) {
      if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
      }
      if (Test-CodexWindowsPathEqual -First $current -Second $root) { return $true }
      $parent = Split-Path -Parent $current
      if ([string]::IsNullOrWhiteSpace($parent) -or
          (Test-CodexWindowsPathEqual -First $parent -Second $current)) { return $false }
      $current = $parent
    }
  } catch {
    return $false
  }
}

function Test-CodexWindowsTreeNoReparse {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)

  try {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push([IO.Path]::GetFullPath($Path))
    while ($pending.Count -gt 0) {
      $current = $pending.Pop()
      $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
      if (-not $item.PSIsContainer) { continue }
      foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        if ($child.PSIsContainer) { $pending.Push($child.FullName) }
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Resolve-CodexWindowsScopedPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("CODEX_IMMERSIVE_INSTALL_ROOT", "CODEX_IMMERSIVE_STATE_ROOT", "CODEX_IMMERSIVE_CONFIG_PATH")]
    [string]$EnvironmentName,
    [Parameter(Mandatory = $true)][string]$DefaultPath
  )

  $override = [Environment]::GetEnvironmentVariable($EnvironmentName)
  if ([string]::IsNullOrWhiteSpace($override)) {
    $resolvedDefault = [IO.Path]::GetFullPath($DefaultPath)
    $defaultBoundary = if ($EnvironmentName -eq 'CODEX_IMMERSIVE_STATE_ROOT') {
      [IO.Path]::GetFullPath($env:LOCALAPPDATA)
    } else {
      [IO.Path]::GetFullPath($env:USERPROFILE)
    }
    if (-not (Test-CodexWindowsPathChainNoReparse -Path $resolvedDefault -Boundary $defaultBoundary)) {
      throw "$EnvironmentName default path contains or traverses a reparse point."
    }
    return $resolvedDefault
  }
  if ($env:CODEX_IMMERSIVE_TEST_MODE -ne "1" -or
      [string]::IsNullOrWhiteSpace($env:CODEX_IMMERSIVE_TEST_ROOT)) {
    throw "$EnvironmentName is reserved for isolated tests."
  }

  $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
  $testRoot = [IO.Path]::GetFullPath($env:CODEX_IMMERSIVE_TEST_ROOT).TrimEnd('\')
  $testLeaf = Split-Path -Leaf $testRoot
  if (-not (Test-CodexWindowsPathWithin -Path $testRoot -Root $temporaryRoot) -or
      -not $testLeaf.StartsWith("codex-immersive-", [StringComparison]::Ordinal)) {
    throw "The isolated test root is outside the approved temporary boundary."
  }
  if (-not (Test-Path -LiteralPath $testRoot -PathType Container) -or
      -not (Test-CodexWindowsPathChainNoReparse -Path $testRoot -Boundary $temporaryRoot)) {
    throw "The isolated test root is missing or contains a reparse point."
  }

  $candidate = [IO.Path]::GetFullPath($override)
  if (-not (Test-CodexWindowsPathWithin -Path $candidate -Root $testRoot)) {
    throw "$EnvironmentName is outside the isolated test root."
  }
  if (-not (Test-CodexWindowsPathChainNoReparse -Path $candidate -Boundary $testRoot)) {
    throw "$EnvironmentName contains or traverses a reparse point."
  }
  $candidate
}

function Open-CodexWindowsOperationLock {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [ValidateRange(0, 30000)][int]$TimeoutMs = 15000
  )

  $normalized = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\').ToLowerInvariant()
  $sha256 = [Security.Cryptography.SHA256]::Create()
  try {
    $digest = ([BitConverter]::ToString(
      $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-', '')
  } finally {
    $sha256.Dispose()
  }

  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  try {
    $currentSid = $identity.User
    if ($null -eq $currentSid) { throw 'The current Windows user SID is unavailable.' }
    $currentSidValue = $currentSid.Value
  } finally {
    $identity.Dispose()
  }

  $mutexName = 'Global\CodexImmersiveSkin.' + $currentSidValue + '.' + $digest.Substring(0, 24)
  $mutexSecurity = New-Object Security.AccessControl.MutexSecurity
  $mutexSecurity.SetOwner($currentSid)
  $mutexSecurity.SetAccessRuleProtection($true, $false)
  $fullControl = [Security.AccessControl.MutexRights]::FullControl
  $allow = [Security.AccessControl.AccessControlType]::Allow
  $accessRule = New-Object Security.AccessControl.MutexAccessRule($currentSid, $fullControl, $allow)
  [void]$mutexSecurity.AddAccessRule($accessRule)

  $createdNew = $false
  $mutex = [Threading.Mutex]::new($false, $mutexName, [ref]$createdNew, $mutexSecurity)
  $acquired = $false
  try {
    $actualSecurity = $mutex.GetAccessControl()
    $actualOwner = $actualSecurity.GetOwner([Security.Principal.SecurityIdentifier])
    $actualRules = @($actualSecurity.GetAccessRules(
      $true,
      $true,
      [Security.Principal.SecurityIdentifier]))
    $hasOnlyCurrentUserFullControl = (
      $actualRules.Count -eq 1 -and
      [string]::Equals(
        [string]$actualRules[0].IdentityReference.Value,
        $currentSidValue,
        [StringComparison]::Ordinal) -and
      $actualRules[0].AccessControlType -eq $allow -and
      -not $actualRules[0].IsInherited -and
      $actualRules[0].MutexRights -eq $fullControl)
    if (-not $actualSecurity.AreAccessRulesProtected -or
        -not [string]::Equals([string]$actualOwner.Value, $currentSidValue, [StringComparison]::Ordinal) -or
        -not $hasOnlyCurrentUserFullControl) {
      throw 'The lifecycle mutex ACL is not restricted to the current Windows user.'
    }

    try { $acquired = $mutex.WaitOne($TimeoutMs) }
    catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { throw 'Another Codex Immersive Skin operation is still running; retry later.' }
    [pscustomobject]@{
      Mutex = $mutex
      Acquired = $true
      Name = $mutexName
      UserSid = $currentSidValue
    }
  } catch {
    $mutex.Dispose()
    throw
  }
}

function Close-CodexWindowsOperationLock {
  [CmdletBinding()]
  param($Lock)
  if ($null -eq $Lock) { return }
  try {
    if ([bool]$Lock.Acquired) { $Lock.Mutex.ReleaseMutex() }
  } finally {
    $Lock.Mutex.Dispose()
  }
}

function Initialize-CodexWindowsNative {
  if ("CodexImmersiveSkin.WindowsNative" -as [type]) { return }

  $source = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace CodexImmersiveSkin {
  public sealed class WindowsProcessIdentity {
    public int ProcessId { get; set; }
    public int ParentProcessId { get; set; }
    public string Path { get; set; }
    public string CommandLine { get; set; }
    public string StartTimeUtc { get; set; }
    public string PackageFullName { get; set; }
    public int PackageOrigin { get; set; }
  }

  public sealed class WindowsCloseResult {
    public bool IdentityMatched { get; set; }
    public bool CloseRequested { get; set; }
    public bool ProcessExited { get; set; }
  }

  public static class WindowsNative {
    private const uint PROCESS_TERMINATE = 0x0001;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const uint SYNCHRONIZE = 0x00100000;
    private const uint WAIT_OBJECT_0 = 0x00000000;
    private const uint WAIT_TIMEOUT = 0x00000102;
    private const uint WAIT_FAILED = 0xFFFFFFFF;
    private const uint WM_CLOSE = 0x0010;
    private const uint GW_OWNER = 4;
    private const uint SMTO_BLOCK = 0x0001;
    private const uint SMTO_ABORTIFHUNG = 0x0002;
    private const int ProcessBasicInformation = 0;
    private const int ProcessCommandLineInformation = 60;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;
    private const int APPMODEL_ERROR_NO_PACKAGE = 15700;
    private const int PACKAGE_ORIGIN_STORE = 3;

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_BASIC_INFORMATION {
      public IntPtr Reserved1;
      public IntPtr PebBaseAddress;
      public IntPtr Reserved2_0;
      public IntPtr Reserved2_1;
      public IntPtr UniqueProcessId;
      public IntPtr InheritedFromUniqueProcessId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FILETIME {
      public uint LowDateTime;
      public uint HighDateTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(IntPtr process, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr window);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(
      IntPtr window,
      uint message,
      IntPtr wParam,
      IntPtr lParam,
      uint flags,
      uint timeoutMilliseconds,
      out IntPtr result);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(
      IntPtr process,
      int flags,
      StringBuilder text,
      ref int size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(
      IntPtr process,
      out FILETIME creation,
      out FILETIME exit,
      out FILETIME kernel,
      out FILETIME user);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetPackageFullName(
      IntPtr process,
      ref uint packageFullNameLength,
      StringBuilder packageFullName);

    [DllImport("kernelbase.dll", CharSet = CharSet.Unicode)]
    private static extern int GetStagedPackageOrigin(
      string packageFullName,
      out int origin);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("ntdll.dll", EntryPoint = "NtQueryInformationProcess")]
    private static extern int NtQueryInformationProcessBasic(
      IntPtr process,
      int informationClass,
      ref PROCESS_BASIC_INFORMATION information,
      int informationLength,
      out int returnLength);

    [DllImport("ntdll.dll", EntryPoint = "NtQueryInformationProcess")]
    private static extern int NtQueryInformationProcessBuffer(
      IntPtr process,
      int informationClass,
      IntPtr information,
      int informationLength,
      out int returnLength);

    [DllImport("shell32.dll", SetLastError = true)]
    private static extern IntPtr CommandLineToArgvW(
      [MarshalAs(UnmanagedType.LPWStr)] string commandLine,
      out int argumentCount);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);

    public static WindowsProcessIdentity GetProcessIdentity(int processId) {
      IntPtr process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
      if (process == IntPtr.Zero) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not query process " + processId);
      }

      try {
        return ReadProcessIdentity(process, processId);
      } finally {
        CloseHandle(process);
      }
    }

    private static WindowsProcessIdentity ReadProcessIdentity(IntPtr process, int processId) {
        StringBuilder image = new StringBuilder(32768);
        int imageLength = image.Capacity;
        if (!QueryFullProcessImageName(process, 0, image, ref imageLength)) {
          throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not resolve process executable");
        }

        PROCESS_BASIC_INFORMATION basic = new PROCESS_BASIC_INFORMATION();
        int returned;
        int status = NtQueryInformationProcessBasic(
          process,
          ProcessBasicInformation,
          ref basic,
          Marshal.SizeOf(typeof(PROCESS_BASIC_INFORMATION)),
          out returned);
        if (status != 0) {
          throw new InvalidOperationException("Could not resolve process ancestry (NTSTATUS 0x" + status.ToString("X8") + ")");
        }

        FILETIME creation;
        FILETIME exit;
        FILETIME kernel;
        FILETIME user;
        if (!GetProcessTimes(process, out creation, out exit, out kernel, out user)) {
          throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not resolve process start time");
        }
        long creationFileTime = ((long)creation.HighDateTime << 32) | creation.LowDateTime;

        string commandLine = ReadCommandLine(process);
        string packageFullName = ReadPackageFullName(process);
        return new WindowsProcessIdentity {
          ProcessId = processId,
          ParentProcessId = basic.InheritedFromUniqueProcessId.ToInt32(),
          Path = image.ToString(),
          CommandLine = commandLine,
          StartTimeUtc = DateTime.FromFileTimeUtc(creationFileTime).ToString("o"),
          PackageFullName = packageFullName,
          PackageOrigin = GetPackageOrigin(packageFullName)
        };
    }

    private static bool IdentityMatches(
      WindowsProcessIdentity actual,
      string expectedPath,
      string expectedCommandLine,
      string expectedStartTimeUtc,
      string expectedPackageFullName,
      int expectedPackageOrigin) {
      return String.Equals(actual.Path, expectedPath, StringComparison.OrdinalIgnoreCase)
        && String.Equals(actual.CommandLine, expectedCommandLine, StringComparison.Ordinal)
        && String.Equals(actual.StartTimeUtc, expectedStartTimeUtc, StringComparison.Ordinal)
        && String.Equals(actual.PackageFullName, expectedPackageFullName, StringComparison.Ordinal)
        && actual.PackageOrigin == expectedPackageOrigin;
    }

    private static bool ProcessHandleHasExited(IntPtr process) {
      uint wait = WaitForSingleObject(process, 0);
      if (wait == WAIT_OBJECT_0) { return true; }
      if (wait == WAIT_TIMEOUT) { return false; }
      if (wait == WAIT_FAILED) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not inspect the verified process handle");
      }
      throw new InvalidOperationException("Unexpected process wait result 0x" + wait.ToString("X8"));
    }

    private static IntPtr FindMainWindow(int processId) {
      IntPtr mainWindow = IntPtr.Zero;
      IntPtr fallbackWindow = IntPtr.Zero;
      EnumWindowsCallback callback = delegate(IntPtr window, IntPtr parameter) {
        uint windowProcessId;
        GetWindowThreadProcessId(window, out windowProcessId);
        if (windowProcessId == (uint)processId
          && IsWindowVisible(window)
          && GetWindow(window, GW_OWNER) == IntPtr.Zero) {
          if (fallbackWindow == IntPtr.Zero) { fallbackWindow = window; }
          if (GetWindowTextLength(window) == 0) { return true; }
          mainWindow = window;
          return false;
        }
        return true;
      };
      EnumWindows(callback, IntPtr.Zero);
      return mainWindow == IntPtr.Zero ? fallbackWindow : mainWindow;
    }

    public static WindowsCloseResult CloseMainWindowIfIdentityMatches(
      int processId,
      string expectedPath,
      string expectedCommandLine,
      string expectedStartTimeUtc,
      string expectedPackageFullName,
      int expectedPackageOrigin) {
      IntPtr process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
        false,
        processId);
      if (process == IntPtr.Zero) {
        int error = Marshal.GetLastWin32Error();
        if (error == 87) {
          return new WindowsCloseResult {
            IdentityMatched = true,
            CloseRequested = false,
            ProcessExited = true
          };
        }
        throw new Win32Exception(error, "Could not open the verified process for gentle close");
      }

      try {
        if (ProcessHandleHasExited(process)) {
          return new WindowsCloseResult {
            IdentityMatched = true,
            CloseRequested = false,
            ProcessExited = true
          };
        }

        WindowsProcessIdentity actual = ReadProcessIdentity(process, processId);
        if (!IdentityMatches(
          actual,
          expectedPath,
          expectedCommandLine,
          expectedStartTimeUtc,
          expectedPackageFullName,
          expectedPackageOrigin)) {
          return new WindowsCloseResult {
            IdentityMatched = false,
            CloseRequested = false,
            ProcessExited = false
          };
        }

        IntPtr mainWindow = FindMainWindow(processId);
        if (mainWindow == IntPtr.Zero) {
          return new WindowsCloseResult {
            IdentityMatched = true,
            CloseRequested = false,
            ProcessExited = ProcessHandleHasExited(process)
          };
        }

        if (ProcessHandleHasExited(process)) {
          return new WindowsCloseResult {
            IdentityMatched = true,
            CloseRequested = false,
            ProcessExited = true
          };
        }

        uint windowProcessId;
        GetWindowThreadProcessId(mainWindow, out windowProcessId);
        if (windowProcessId != (uint)processId) {
          return new WindowsCloseResult {
            IdentityMatched = true,
            CloseRequested = false,
            ProcessExited = false
          };
        }
        IntPtr messageResult;
        if (SendMessageTimeout(
          mainWindow,
          WM_CLOSE,
          IntPtr.Zero,
          IntPtr.Zero,
          SMTO_BLOCK | SMTO_ABORTIFHUNG,
          2000,
          out messageResult) == IntPtr.Zero && !ProcessHandleHasExited(process)) {
          throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not request a gentle close from the verified process");
        }
        uint closeWait = WaitForSingleObject(process, 250);
        if (closeWait != WAIT_OBJECT_0 && closeWait != WAIT_TIMEOUT) {
          if (closeWait == WAIT_FAILED) {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not confirm the gentle-close request");
          }
          throw new InvalidOperationException("Unexpected gentle-close wait result 0x" + closeWait.ToString("X8"));
        }
        return new WindowsCloseResult {
          IdentityMatched = true,
          CloseRequested = true,
          ProcessExited = closeWait == WAIT_OBJECT_0
        };
      } finally {
        CloseHandle(process);
      }
    }

    public static bool TerminateProcessIfIdentityMatches(
      int processId,
      string expectedPath,
      string expectedCommandLine,
      string expectedStartTimeUtc,
      string expectedPackageFullName,
      int expectedPackageOrigin,
      uint timeoutMilliseconds) {
      IntPtr process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE,
        false,
        processId);
      if (process == IntPtr.Zero) {
        int error = Marshal.GetLastWin32Error();
        if (error == 87) { return true; }
        throw new Win32Exception(error, "Could not open the verified process for termination");
      }
      try {
        WindowsProcessIdentity actual = ReadProcessIdentity(process, processId);
        if (!IdentityMatches(
          actual,
          expectedPath,
          expectedCommandLine,
          expectedStartTimeUtc,
          expectedPackageFullName,
          expectedPackageOrigin)) {
          return false;
        }
        if (!TerminateProcess(process, 1)) {
          int error = Marshal.GetLastWin32Error();
          if (error != 5) {
            throw new Win32Exception(error, "Could not terminate the verified process");
          }
          WindowsProcessIdentity afterAccessDenied = ReadProcessIdentity(process, processId);
          if (!String.Equals(afterAccessDenied.StartTimeUtc, expectedStartTimeUtc, StringComparison.Ordinal)) {
            return true;
          }
          throw new Win32Exception(error, "Access was denied while terminating the verified process");
        }
        return WaitForSingleObject(process, timeoutMilliseconds) == WAIT_OBJECT_0;
      } finally {
        CloseHandle(process);
      }
    }

    private static string ReadPackageFullName(IntPtr process) {
      uint required = 0;
      int result = GetPackageFullName(process, ref required, null);
      if (result == APPMODEL_ERROR_NO_PACKAGE) { return String.Empty; }
      if (result != ERROR_INSUFFICIENT_BUFFER || required == 0 || required > 32768) {
        throw new Win32Exception(result, "Could not determine process package identity");
      }

      StringBuilder value = new StringBuilder((int)required);
      result = GetPackageFullName(process, ref required, value);
      if (result != 0) {
        throw new Win32Exception(result, "Could not read process package identity");
      }
      return value.ToString();
    }

    public static int GetPackageOrigin(string packageFullName) {
      if (String.IsNullOrEmpty(packageFullName)) { return 0; }
      int origin;
      int result = GetStagedPackageOrigin(packageFullName, out origin);
      if (result != 0) {
        throw new Win32Exception(result, "Could not read staged package origin");
      }
      return origin;
    }

    private static string ReadCommandLine(IntPtr process) {
      int required;
      NtQueryInformationProcessBuffer(process, ProcessCommandLineInformation, IntPtr.Zero, 0, out required);
      if (required <= 0 || required > 1024 * 1024) {
        throw new InvalidOperationException("Could not determine process command-line length");
      }

      IntPtr buffer = Marshal.AllocHGlobal(required);
      try {
        int returned;
        int status = NtQueryInformationProcessBuffer(
          process,
          ProcessCommandLineInformation,
          buffer,
          required,
          out returned);
        if (status != 0) {
          throw new InvalidOperationException("Could not read process command line (NTSTATUS 0x" + status.ToString("X8") + ")");
        }
        int byteLength = (ushort)Marshal.ReadInt16(buffer, 0);
        int pointerOffset = IntPtr.Size == 8 ? 8 : 4;
        IntPtr text = Marshal.ReadIntPtr(buffer, pointerOffset);
        return text == IntPtr.Zero ? String.Empty : Marshal.PtrToStringUni(text, byteLength / 2);
      } finally {
        Marshal.FreeHGlobal(buffer);
      }
    }

    public static string[] ParseCommandLine(string commandLine) {
      if (String.IsNullOrWhiteSpace(commandLine)) { return new string[0]; }
      int count;
      IntPtr values = CommandLineToArgvW(commandLine, out count);
      if (values == IntPtr.Zero) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not parse process command line");
      }
      try {
        string[] result = new string[count];
        for (int index = 0; index < count; index++) {
          IntPtr value = Marshal.ReadIntPtr(values, index * IntPtr.Size);
          result[index] = Marshal.PtrToStringUni(value);
        }
        return result;
      } finally {
        LocalFree(values);
      }
    }

    public static string QuoteCommandLineArgument(string value) {
      if (value == null) { throw new ArgumentNullException("value"); }
      bool needsQuotes = value.Length == 0;
      for (int index = 0; index < value.Length && !needsQuotes; index++) {
        needsQuotes = Char.IsWhiteSpace(value[index]) || value[index] == '"';
      }
      if (!needsQuotes) { return value; }

      StringBuilder quoted = new StringBuilder(value.Length + 2);
      quoted.Append('"');
      int backslashes = 0;
      foreach (char character in value) {
        if (character == '\\') {
          backslashes++;
          continue;
        }
        if (character == '"') {
          quoted.Append('\\', backslashes * 2 + 1);
          quoted.Append('"');
          backslashes = 0;
          continue;
        }
        if (backslashes > 0) {
          quoted.Append('\\', backslashes);
          backslashes = 0;
        }
        quoted.Append(character);
      }
      if (backslashes > 0) { quoted.Append('\\', backslashes * 2); }
      quoted.Append('"');
      return quoted.ToString();
    }
  }
}
'@

  Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Get-CodexWindowsProcessIdentity {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ProcessId
  )

  Initialize-CodexWindowsNative
  $value = [CodexImmersiveSkin.WindowsNative]::GetProcessIdentity($ProcessId)
  [pscustomobject]@{
    ProcessId = $value.ProcessId
    ParentProcessId = $value.ParentProcessId
    Path = $value.Path
    CommandLine = $value.CommandLine
    StartTimeUtc = $value.StartTimeUtc
    PackageFullName = $value.PackageFullName
    PackageOrigin = $value.PackageOrigin
  }
}

function Request-CodexWindowsVerifiedMainWindowClose {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Identity
  )

  Initialize-CodexWindowsNative
  $result = [CodexImmersiveSkin.WindowsNative]::CloseMainWindowIfIdentityMatches(
    [int]$Identity.ProcessId,
    [string]$Identity.Path,
    [string]$Identity.CommandLine,
    [string]$Identity.StartTimeUtc,
    [string]$Identity.PackageFullName,
    [int]$Identity.PackageOrigin)
  if (-not $result.IdentityMatched) {
    throw 'The process identity changed before gentle close; PID-only window messaging was refused.'
  }
  return [bool]$result.CloseRequested
}

function Stop-CodexWindowsVerifiedProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Identity,
    [ValidateRange(1, 30000)][int]$TimeoutMs = 6000
  )

  Initialize-CodexWindowsNative
  $stopped = [CodexImmersiveSkin.WindowsNative]::TerminateProcessIfIdentityMatches(
    [int]$Identity.ProcessId,
    [string]$Identity.Path,
    [string]$Identity.CommandLine,
    [string]$Identity.StartTimeUtc,
    [string]$Identity.PackageFullName,
    [int]$Identity.PackageOrigin,
    [uint32]$TimeoutMs)
  if (-not $stopped) {
    throw 'The process identity changed before termination, or it did not exit before timeout; PID-only termination was refused.'
  }
}

function Test-CodexWindowsBlockMapFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][xml]$BlockMap,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$RelativePath
  )

  $stream = $null
  $sha256 = $null
  try {
    $root = (Resolve-Path -LiteralPath $PackageRoot -ErrorAction Stop).Path
    $normalizedRelative = $RelativePath.Replace('/', '\').TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($normalizedRelative) -or $normalizedRelative.Contains('..')) { return $false }
    $path = Join-Path $root $normalizedRelative
    if (-not (Test-CodexWindowsPathWithin -Path $path -Root $root) -or
        -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }

    $blockMapRoot = $BlockMap.SelectSingleNode("/*[local-name()='BlockMap']")
    if ($null -eq $blockMapRoot -or
        $blockMapRoot.GetAttribute("HashMethod") -ne "http://www.w3.org/2001/04/xmlenc#sha256") { return $false }

    $fileEntry = $null
    foreach ($candidate in @($blockMapRoot.SelectNodes("*[local-name()='File']"))) {
      $candidateName = ([string]$candidate.GetAttribute("Name")).Replace('/', '\')
      if ([string]::Equals($candidateName, $normalizedRelative, [StringComparison]::OrdinalIgnoreCase)) {
        $fileEntry = $candidate
        break
      }
    }
    if ($null -eq $fileEntry) { return $false }

    [long]$expectedLength = 0
    if (-not [long]::TryParse($fileEntry.GetAttribute("Size"), [ref]$expectedLength) -or $expectedLength -lt 0) {
      return $false
    }
    $stream = New-Object IO.FileStream(
      $path,
      [IO.FileMode]::Open,
      [IO.FileAccess]::Read,
      [IO.FileShare]::Read)
    if ($stream.Length -ne $expectedLength) { return $false }

    $sha256 = [Security.Cryptography.SHA256]::Create()
    [long]$remaining = $expectedLength
    foreach ($block in @($fileEntry.SelectNodes("*[local-name()='Block']"))) {
      if ($remaining -le 0) { return $false }
      $count = [int][math]::Min(65536, $remaining)
      $buffer = New-Object byte[] $count
      $offset = 0
      while ($offset -lt $count) {
        $read = $stream.Read($buffer, $offset, $count - $offset)
        if ($read -le 0) { return $false }
        $offset += $read
      }
      $actualHash = [Convert]::ToBase64String($sha256.ComputeHash($buffer, 0, $count))
      if (-not [string]::Equals(
        $actualHash,
        [string]$block.GetAttribute("Hash"),
        [StringComparison]::Ordinal)) { return $false }
      $remaining -= $count
    }
    return $remaining -eq 0 -and $stream.Position -eq $stream.Length
  } catch {
    return $false
  } finally {
    if ($null -ne $sha256) { $sha256.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Test-CodexWindowsNoReparsePoint {
  param(
    [Parameter(Mandatory = $true)][string[]]$Path
  )

  try {
    foreach ($candidate in $Path) {
      $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    }
    return $true
  } catch {
    return $false
  }
}

function Get-CodexWindowsRuntimePathChain {
  $openAiRoot = Join-Path $env:LOCALAPPDATA "OpenAI"
  $codexRoot = Join-Path $openAiRoot "Codex"
  $runtimesRoot = Join-Path $codexRoot "runtimes"
  @(
    $env:LOCALAPPDATA,
    $openAiRoot,
    $codexRoot,
    $runtimesRoot,
    (Join-Path $runtimesRoot "cua_node")
  )
}

function Read-CodexWindowsPackageInfo {
  param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$PackageFamilyName,
    [Parameter(Mandatory = $true)][string]$PackageFullName,
    [string]$SignatureKind,
    [switch]$RegisteredPackage
  )

  $resolvedRoot = (Resolve-Path -LiteralPath $PackageRoot -ErrorAction Stop).Path
  $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
  if (-not (Test-CodexWindowsPathWithin -Path $resolvedRoot -Root $windowsApps)) {
    throw "The Codex package is outside the protected WindowsApps root."
  }
  if (-not [string]::Equals($PackageFamilyName, $script:CodexWindowsPackageFamilyName, [StringComparison]::Ordinal) -or
      -not [string]::Equals((Split-Path -Leaf $resolvedRoot), $PackageFullName, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The Codex package does not have the pinned Microsoft Store identity."
  }
  Initialize-CodexWindowsNative
  $packageOrigin = [CodexImmersiveSkin.WindowsNative]::GetPackageOrigin($PackageFullName)
  if ($SignatureKind -ne "Store" -or $packageOrigin -ne 3) {
    throw "The Codex package is not staged by Windows as a Microsoft Store package."
  }

  $cacheKey = $resolvedRoot.ToLowerInvariant()
  if ($script:CodexWindowsValidatedPackages.ContainsKey($cacheKey)) {
    return $script:CodexWindowsValidatedPackages[$cacheKey]
  }

  $manifestPath = Join-Path $resolvedRoot "AppxManifest.xml"
  $signaturePath = Join-Path $resolvedRoot "AppxSignature.p7x"
  $blockMapPath = Join-Path $resolvedRoot "AppxBlockMap.xml"
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "The Codex MSIX manifest is missing."
  }
  if (-not (Test-Path -LiteralPath $signaturePath -PathType Leaf)) {
    throw "The Codex MSIX package signature is missing."
  }
  if (-not (Test-Path -LiteralPath $blockMapPath -PathType Leaf)) {
    throw "The Codex MSIX block map is missing."
  }

  [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath -ErrorAction Stop
  $identity = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Identity']")
  $application = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Applications']/*[local-name()='Application'][@Id='App']")
  if ($null -eq $identity -or $null -eq $application) {
    throw "The Codex MSIX manifest is missing its identity or application entry."
  }
  $identityName = $identity.GetAttribute("Name")
  $identityVersion = $identity.GetAttribute("Version")
  $identityArchitecture = $identity.GetAttribute("ProcessorArchitecture")
  $identityPublisher = $identity.GetAttribute("Publisher")
  $identityResourceId = $identity.GetAttribute("ResourceId")
  $applicationId = $application.GetAttribute("Id")
  $applicationEntryPoint = $application.GetAttribute("EntryPoint")
  if ($identityName -ne $script:CodexWindowsPackageName -or
      $identityPublisher -ne $script:CodexWindowsPublisher -or
      $identityArchitecture -notin @("x64", "arm64")) {
    throw "Unexpected Codex MSIX package identity."
  }
  $manifestFullName = "{0}_{1}_{2}_{3}_{4}" -f @(
    $identityName,
    $identityVersion,
    $identityArchitecture,
    $identityResourceId,
    $script:CodexWindowsPublisherId)
  if (-not [string]::Equals($manifestFullName, $PackageFullName, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The Codex MSIX folder and manifest identities do not match."
  }
  if ($applicationEntryPoint -ne "Windows.FullTrustApplication") {
    throw "The Codex MSIX entry point is not a full-trust desktop application."
  }
  $desktopFamily = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Dependencies']/*[local-name()='TargetDeviceFamily'][@Name='Windows.Desktop']")
  $fullTrustCapability = $manifest.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Capabilities']/*[local-name()='Capability'][@Name='runFullTrust']")
  if ($null -eq $desktopFamily -or $null -eq $fullTrustCapability) {
    throw "The Codex MSIX does not declare its required desktop full-trust identity."
  }

  $entryRelative = ([string]$application.GetAttribute("Executable")).Replace('/', '\')
  if (-not [string]::Equals($entryRelative, "app\ChatGPT.exe", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unexpected Codex GUI entry point."
  }
  $appExecutable = Join-Path $resolvedRoot $entryRelative
  if (-not (Test-Path -LiteralPath $appExecutable -PathType Leaf)) {
    throw "The Codex GUI executable is missing."
  }

  $signature = Get-AuthenticodeSignature -LiteralPath $signaturePath -ErrorAction Stop
  $signatureValid = $signature.Status.ToString() -eq "Valid"
  if (-not $signatureValid -or $null -eq $signature.SignerCertificate) {
    throw "The Codex MSIX package signature is not valid."
  }
  $signatureSubject = [string]$signature.SignerCertificate.Subject
  $signatureIssuer = [string]$signature.SignerCertificate.Issuer
  if (-not [string]::Equals($signatureSubject, $script:CodexWindowsPublisher, [StringComparison]::Ordinal) -or
      $signatureIssuer.IndexOf($script:CodexWindowsMarketplaceIssuer, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "The Codex MSIX signer is not the pinned Microsoft Marketplace identity."
  }

  $packageNodeRoot = Join-Path $resolvedRoot "app\resources\cua_node"
  $packageNodePath = Join-Path $packageNodeRoot "bin\node.exe"
  $packageNodeManifestPath = Join-Path $packageNodeRoot "manifest.json"
  [xml]$blockMap = Get-Content -Raw -LiteralPath $blockMapPath -ErrorAction Stop
  foreach ($relativePath in @(
    "AppxManifest.xml",
    "app\resources\cua_node\bin\node.exe",
    "app\resources\cua_node\manifest.json"
  )) {
    if (-not (Test-CodexWindowsBlockMapFile -BlockMap $blockMap -PackageRoot $resolvedRoot -RelativePath $relativePath)) {
      throw "The Codex MSIX block map does not authenticate $relativePath."
    }
  }

  $result = [pscustomobject]@{
    Name = $identityName
    Version = $identityVersion
    Architecture = $identityArchitecture
    Publisher = $identityPublisher
    PublisherId = $script:CodexWindowsPublisherId
    PackageFullName = $PackageFullName
    PackageFamilyName = $PackageFamilyName
    AppId = $applicationId
    AppUserModelId = "{0}!{1}" -f $PackageFamilyName, $applicationId
    InstallLocation = $resolvedRoot
    ManifestPath = $manifestPath
    SignaturePath = $signaturePath
    SignatureValid = $true
    SignatureSubject = $signatureSubject
    SignatureIssuer = $signatureIssuer
    SignatureThumbprint = [string]$signature.SignerCertificate.Thumbprint
    SignatureKind = "Store"
    PackageOrigin = $packageOrigin
    BlockMapPath = $blockMapPath
    BlockMapValidated = $true
    AppExecutable = $appExecutable
    PackageNodeRoot = $packageNodeRoot
    PackageNodePath = $packageNodePath
    PackageNodeManifestPath = $packageNodeManifestPath
  }
  $script:CodexWindowsValidatedPackages[$cacheKey] = $result
  return $result
}

function Get-CodexWindowsPackage {
  [CmdletBinding()]
  param()

  $candidates = @()
  try {
    $registered = @(Get-AppxPackage -Name $script:CodexWindowsPackageName -ErrorAction Stop |
      Sort-Object Version -Descending)
    foreach ($package in $registered) {
      if (-not [string]::IsNullOrWhiteSpace([string]$package.InstallLocation)) {
        $candidates += [pscustomobject]@{
          Root = [string]$package.InstallLocation
          Family = [string]$package.PackageFamilyName
          FullName = [string]$package.PackageFullName
          Publisher = [string]$package.Publisher
          PublisherId = [string]$package.PublisherId
          SignatureKind = [string]$package.SignatureKind
          Registered = $true
        }
      }
    }
  } catch { }

  foreach ($process in @(Get-Process -Name "ChatGPT" -ErrorAction SilentlyContinue)) {
    try {
      $processIdentity = Get-CodexWindowsProcessIdentity -ProcessId $process.Id
      $executable = [string]$processIdentity.Path
      $processPackageFullName = [string]$processIdentity.PackageFullName
      if ([string]::IsNullOrWhiteSpace($executable) -or
          [string]::IsNullOrWhiteSpace($processPackageFullName) -or
          [int]$processIdentity.PackageOrigin -ne 3) { continue }
      $appRoot = Split-Path -Parent $executable
      $packageRoot = Split-Path -Parent $appRoot
      if (Test-Path -LiteralPath (Join-Path $packageRoot "AppxManifest.xml") -PathType Leaf) {
        $candidates += [pscustomobject]@{
          Root = $packageRoot
          Family = $script:CodexWindowsPackageFamilyName
          FullName = $processPackageFullName
          Publisher = $script:CodexWindowsPublisher
          PublisherId = $script:CodexWindowsPublisherId
          SignatureKind = "Store"
          Registered = $true
        }
      }
    } catch { }
  }

  $seen = @{}
  $valid = @()
  foreach ($candidate in $candidates) {
    try {
      $key = [IO.Path]::GetFullPath([string]$candidate.Root).ToLowerInvariant()
      if ($seen.ContainsKey($key)) { continue }
      $seen[$key] = $true
      if ($candidate.Registered -and (
        $candidate.Family -ne $script:CodexWindowsPackageFamilyName -or
        $candidate.Publisher -ne $script:CodexWindowsPublisher -or
        $candidate.PublisherId -ne $script:CodexWindowsPublisherId -or
        $candidate.SignatureKind -ne "Store")) { continue }
      $parameters = @{
        PackageRoot = [string]$candidate.Root
        PackageFamilyName = [string]$candidate.Family
        PackageFullName = [string]$candidate.FullName
        SignatureKind = [string]$candidate.SignatureKind
      }
      if ($candidate.Registered) { $parameters.RegisteredPackage = $true }
      $valid += Read-CodexWindowsPackageInfo @parameters
    } catch { }
  }

  if ($valid.Count -eq 0) {
    throw "Could not discover a valid Microsoft Store installation of OpenAI.Codex."
  }
  @($valid | Sort-Object { [version]$_.Version } -Descending)[0]
}

function Resolve-CodexWindowsRuntime {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$PackageInfo,
    [string]$LocalRuntimeRoot = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\runtimes\cua_node")
  )

  $packageParameters = @{
    PackageRoot = [string]$PackageInfo.InstallLocation
    PackageFamilyName = [string]$PackageInfo.PackageFamilyName
    PackageFullName = [string]$PackageInfo.PackageFullName
    SignatureKind = [string]$PackageInfo.SignatureKind
  }
  if ([string]$PackageInfo.SignatureKind -eq "Store") { $packageParameters.RegisteredPackage = $true }
  $validatedPackage = Read-CodexWindowsPackageInfo @packageParameters

  $packageNode = [string]$validatedPackage.PackageNodePath
  $packageManifestPath = [string]$validatedPackage.PackageNodeManifestPath
  if (-not (Test-Path -LiteralPath $packageNode -PathType Leaf) -or
      -not (Test-Path -LiteralPath $packageManifestPath -PathType Leaf)) {
    throw "The signed Codex package does not contain its cua_node runtime."
  }

  $packageSignature = Get-AuthenticodeSignature -LiteralPath $packageNode -ErrorAction Stop
  if ($packageSignature.Status.ToString() -ne "Valid" -or $null -eq $packageSignature.SignerCertificate) {
    throw "The package cua_node executable signature is not valid."
  }
  $packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packageNode -ErrorAction Stop).Hash
  $packageManifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packageManifestPath -ErrorAction Stop).Hash
  $packageManifest = Read-CodexWindowsUtf8Text -Path $packageManifestPath | ConvertFrom-Json
  if ($packageManifest.platform -ne "windows" -or [int]([string]$packageManifest.node_version).Split('.')[0] -lt 22) {
    throw "The package cua_node manifest is not a supported Windows Node.js runtime."
  }

  $expectedRuntimeRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\runtimes\cua_node"
  if (-not [IO.Path]::IsPathRooted($LocalRuntimeRoot) -or
      -not (Test-CodexWindowsPathEqual -First $LocalRuntimeRoot -Second $expectedRuntimeRoot)) {
    throw "Only the Codex-owned local cua_node runtime directory is allowed."
  }
  if (-not (Test-Path -LiteralPath $LocalRuntimeRoot -PathType Container)) {
    throw "The Codex local cua_node runtime directory does not exist."
  }
  $resolvedRuntimeRoot = (Resolve-Path -LiteralPath $LocalRuntimeRoot -ErrorAction Stop).Path
  if (-not (Test-CodexWindowsNoReparsePoint -Path @(Get-CodexWindowsRuntimePathChain))) {
    throw "The Codex local cua_node runtime path contains a reparse point."
  }

  $matches = @()
  foreach ($directory in @(Get-ChildItem -LiteralPath $resolvedRuntimeRoot -Directory -Force -ErrorAction Stop)) {
    try {
      $localNode = Join-Path $directory.FullName "bin\node.exe"
      $localManifestPath = Join-Path $directory.FullName "manifest.json"
      if (-not (Test-Path -LiteralPath $localNode -PathType Leaf) -or
          -not (Test-Path -LiteralPath $localManifestPath -PathType Leaf)) { continue }
      if (-not (Test-CodexWindowsPathWithin -Path $localNode -Root $resolvedRuntimeRoot) -or
          -not (Test-CodexWindowsPathWithin -Path $localManifestPath -Root $resolvedRuntimeRoot) -or
          -not (Test-CodexWindowsNoReparsePoint -Path @(
            $directory.FullName,
            (Join-Path $directory.FullName "bin"),
            $localNode,
            $localManifestPath
          ))) { continue }

      $localHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $localNode -ErrorAction Stop).Hash
      if (-not [string]::Equals($localHash, $packageHash, [StringComparison]::OrdinalIgnoreCase)) { continue }
      $localManifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $localManifestPath -ErrorAction Stop).Hash
      if (-not [string]::Equals($localManifestHash, $packageManifestHash, [StringComparison]::OrdinalIgnoreCase)) { continue }

      $localSignature = Get-AuthenticodeSignature -LiteralPath $localNode -ErrorAction Stop
      if ($localSignature.Status.ToString() -ne "Valid" -or $null -eq $localSignature.SignerCertificate) { continue }
      if (-not [string]::Equals(
        [string]$localSignature.SignerCertificate.Thumbprint,
        [string]$packageSignature.SignerCertificate.Thumbprint,
        [StringComparison]::OrdinalIgnoreCase)) { continue }

      $localManifest = Read-CodexWindowsUtf8Text -Path $localManifestPath | ConvertFrom-Json
      if ($localManifest.platform -ne "windows" -or
          $localManifest.arch -ne $packageManifest.arch -or
          $localManifest.node_version -ne $packageManifest.node_version -or
          [string]$localManifest.arch -notin @("x64", "arm64") -or
          [string]$localManifest.arch -ne [string]$validatedPackage.Architecture) { continue }

      $matches += [pscustomobject]@{
        RuntimeRoot = $directory.FullName
        NodePath = $localNode
        ManifestPath = $localManifestPath
        NodeVersion = [string]$localManifest.node_version
        Architecture = [string]$localManifest.arch
        NodeSha256 = $localHash
        PackageNodeSha256 = $packageHash
        NodeMatchesPackage = $true
        SignatureValid = $true
        SignatureSubject = [string]$localSignature.SignerCertificate.Subject
        SignatureThumbprint = [string]$localSignature.SignerCertificate.Thumbprint
        LastWriteTimeUtc = $directory.LastWriteTimeUtc
        PackageInfo = $validatedPackage
      }
    } catch { }
  }

  if ($matches.Count -eq 0) {
    throw "No local Codex cua_node runtime exactly matches the signed MSIX package."
  }
  @($matches | Sort-Object LastWriteTimeUtc -Descending)[0]
}

function Initialize-WindowsRuntime {
  [CmdletBinding()]
  param(
    $PackageInfo,
    [string]$LocalRuntimeRoot
  )

  if ($null -eq $PackageInfo) { $PackageInfo = Get-CodexWindowsPackage }
  if ($PSBoundParameters.ContainsKey("LocalRuntimeRoot")) {
    $runtime = Resolve-CodexWindowsRuntime -PackageInfo $PackageInfo -LocalRuntimeRoot $LocalRuntimeRoot
  } else {
    $runtime = Resolve-CodexWindowsRuntime -PackageInfo $PackageInfo
  }
  $runtime
}

function Get-CodexWindowsRuntimePlatform {
  param(
    [Parameter(Mandatory = $true)]$RuntimeInfo
  )

  switch ([string]$RuntimeInfo.Architecture) {
    "x64" { return "win32-x64" }
    "arm64" { return "win32-arm64" }
    default { throw "The Codex Windows runtime architecture is not supported." }
  }
}

function Open-CodexWindowsRuntimeLock {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$RuntimeInfo
  )

  $expectedRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\runtimes\cua_node"
  $runtimeRoot = [string]$RuntimeInfo.RuntimeRoot
  $nodePath = [string]$RuntimeInfo.NodePath
  $trustedPaths = @(Get-CodexWindowsRuntimePathChain) + @(
    $runtimeRoot,
    (Join-Path $runtimeRoot "bin"),
    $nodePath
  )
  if (-not (Test-CodexWindowsPathWithin -Path $runtimeRoot -Root $expectedRoot) -or
      -not (Test-CodexWindowsPathEqual -First $nodePath -Second (Join-Path $runtimeRoot "bin\node.exe")) -or
      -not [bool]$RuntimeInfo.NodeMatchesPackage -or
      -not [bool]$RuntimeInfo.SignatureValid -or
      -not (Test-CodexWindowsNoReparsePoint -Path $trustedPaths)) {
    throw "The Codex local cua_node runtime cannot be locked safely."
  }

  $stream = $null
  $sha256 = $null
  try {
    $stream = [IO.File]::Open(
      $nodePath,
      [IO.FileMode]::Open,
      [IO.FileAccess]::Read,
      [IO.FileShare]::Read)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $hash = ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace("-", "")
    if (-not [string]::Equals($hash, [string]$RuntimeInfo.NodeSha256, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($hash, [string]$RuntimeInfo.PackageNodeSha256, [StringComparison]::OrdinalIgnoreCase)) {
      throw "The locked Codex cua_node executable no longer matches the signed package."
    }
    $stream.Position = 0
    $result = $stream
    $stream = $null
    return ,$result
  } finally {
    if ($null -ne $sha256) { $sha256.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Invoke-CodexWindowsNode {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$RuntimeInfo,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [string]$StandardErrorPath,
    [switch]$StreamOutput
  )

  $runtimeLock = Open-CodexWindowsRuntimeLock -RuntimeInfo $RuntimeInfo
  $process = $null
  $errorStream = $null
  $errorWriter = $null
  try {
    Initialize-CodexWindowsNative
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = [string]$RuntimeInfo.NodePath
    $quotedArguments = @(
      foreach ($argument in $Arguments) {
        [CodexImmersiveSkin.WindowsNative]::QuoteCommandLineArgument([string]$argument)
      }
    )
    $startInfo.Arguments = [string]::Join(' ', [string[]]$quotedArguments)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $strictUtf8
    $startInfo.StandardErrorEncoding = $strictUtf8

    if (-not [string]::IsNullOrWhiteSpace($StandardErrorPath)) {
      $errorStream = New-Object IO.FileStream(
        $StandardErrorPath,
        [IO.FileMode]::Create,
        [IO.FileAccess]::Write,
        [IO.FileShare]::Read)
      $errorWriter = New-Object IO.StreamWriter($errorStream, $strictUtf8)
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'The verified Codex Node runtime could not be started.' }

    $errorTask = $process.StandardError.ReadToEndAsync()
    $output = New-Object 'Collections.Generic.List[string]'
    while ($true) {
      $line = $process.StandardOutput.ReadLineAsync().GetAwaiter().GetResult()
      if ($null -eq $line) { break }
      if ($StreamOutput) {
        [Console]::Out.WriteLine($line)
      } else {
        $output.Add($line)
      }
    }
    $process.WaitForExit()
    $errorText = $errorTask.GetAwaiter().GetResult()
    if ($null -ne $errorWriter) {
      $errorWriter.Write($errorText)
      $errorWriter.Flush()
    } elseif (-not [string]::IsNullOrEmpty($errorText)) {
      [Console]::Error.Write($errorText)
    }

    [pscustomobject]@{
      ExitCode = $process.ExitCode
      Output = [object[]]$output.ToArray()
    }
  } finally {
    if ($null -ne $errorWriter) { $errorWriter.Dispose() }
    elseif ($null -ne $errorStream) { $errorStream.Dispose() }
    if ($null -ne $process) { $process.Dispose() }
    $runtimeLock.Dispose()
  }
}

function Get-CodexWindowsTcpListener {
  [CmdletBinding()]
  param(
    [ValidateRange(1, 65535)]
    [int]$Port
  )

  $netstat = Join-Path $env:SystemRoot "System32\netstat.exe"
  if (-not (Test-Path -LiteralPath $netstat -PathType Leaf)) {
    throw "Windows netstat.exe is unavailable."
  }

  $output = & $netstat -ano -p tcp 2>$null
  if ($LASTEXITCODE -ne 0) { throw "netstat.exe could not enumerate TCP listeners." }
  foreach ($line in $output) {
    if ($line -notmatch '^\s*TCP\s+(?<local>\S+)\s+\S+\s+LISTENING\s+(?<pid>\d+)\s*$') { continue }
    $endpoint = $Matches.local
    $owningProcess = [int]$Matches.pid
    $address = $null
    $listenerPort = 0
    if ($endpoint -match '^\[(?<address>.*)\]:(?<port>\d+)$') {
      $address = $Matches.address
      $listenerPort = [int]$Matches.port
    } elseif ($endpoint -match '^(?<address>.*):(?<port>\d+)$') {
      $address = $Matches.address
      $listenerPort = [int]$Matches.port
    } else { continue }
    if ($PSBoundParameters.ContainsKey("Port") -and $listenerPort -ne $Port) { continue }
    [pscustomobject]@{
      LocalAddress = $address
      LocalPort = $listenerPort
      OwningProcess = $owningProcess
    }
  }
}

function Test-CodexWindowsPortAvailable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$Port
  )
  if (@(Get-CodexWindowsTcpListener -Port $Port).Count -ne 0) { return $false }

  $netsh = Join-Path $env:SystemRoot "System32\netsh.exe"
  if (-not (Test-Path -LiteralPath $netsh -PathType Leaf)) { return $false }
  foreach ($family in @("ipv4", "ipv6")) {
    $output = & $netsh interface $family show excludedportrange protocol=tcp 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($line in $output) {
      if ($line -match '^\s*(?<start>\d+)\s+(?<end>\d+)(?:\s+\*)?\s*$' -and
          $Port -ge [int]$Matches.start -and $Port -le [int]$Matches.end) { return $false }
    }
  }
  return $true
}

function Test-CodexWindowsProcessDescendant {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$AppExecutable
  )

  $current = $ProcessId
  $childStart = $null
  $seen = @{}
  for ($depth = 0; $depth -lt 32 -and $current -gt 0; $depth++) {
    if ($seen.ContainsKey($current)) { return $false }
    $seen[$current] = $true
    try { $identity = Get-CodexWindowsProcessIdentity -ProcessId $current } catch { return $false }
    try { $start = [datetime]::Parse([string]$identity.StartTimeUtc).ToUniversalTime() } catch { return $false }
    if ($null -ne $childStart -and $start -gt $childStart) { return $false }
    if (Test-CodexWindowsPathEqual -First $identity.Path -Second $AppExecutable) { return $true }
    if ($identity.ParentProcessId -le 0 -or $identity.ParentProcessId -eq $current) { return $false }
    $childStart = $start
    $current = $identity.ParentProcessId
  }
  return $false
}

function Test-CodexWindowsPortOwnership {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$Port,
    [Parameter(Mandatory = $true)]$PackageInfo
  )

  try { $listeners = @(Get-CodexWindowsTcpListener -Port $Port) } catch { return $false }
  if ($listeners.Count -eq 0) { return $false }
  foreach ($listener in $listeners) {
    if ($listener.LocalAddress -notin @("127.0.0.1", "::1")) { return $false }
    try { $identity = Get-CodexWindowsProcessIdentity -ProcessId $listener.OwningProcess } catch { return $false }
    if (-not (Test-CodexWindowsPathEqual -First $identity.Path -Second $PackageInfo.AppExecutable) -or
        -not [string]::Equals(
          [string]$identity.PackageFullName,
          [string]$PackageInfo.PackageFullName,
          [StringComparison]::OrdinalIgnoreCase) -or
        [int]$identity.PackageOrigin -ne 3) { return $false }
    try { $arguments = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine($identity.CommandLine)) } catch { return $false }
    if ($arguments.Count -lt 1 -or
        -not (Test-CodexWindowsPathEqual -First ([string]$arguments[0]) -Second $PackageInfo.AppExecutable)) { return $false }
    foreach ($argument in $arguments) {
      if (([string]$argument).StartsWith("--type=", [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
  }
  return $true
}

function Invoke-CodexWindowsLoopbackJson {
  param(
    [Parameter(Mandatory = $true)][uri]$Uri,
    [ValidateRange(100, 30000)][int]$TimeoutMs = 2000
  )

  if ($Uri.Scheme -ne "http" -or $Uri.Host -ne "127.0.0.1") {
    throw "Only an explicit IPv4 loopback HTTP endpoint is allowed."
  }
  $request = [Net.HttpWebRequest]::Create($Uri)
  $request.Proxy = $null
  $request.AllowAutoRedirect = $false
  $request.Timeout = $TimeoutMs
  $request.ReadWriteTimeout = $TimeoutMs
  $response = $null
  $reader = $null
  try {
    $response = $request.GetResponse()
    if ([int]$response.StatusCode -ne 200 -or
        $response.ResponseUri.Scheme -ne "http" -or
        $response.ResponseUri.Host -ne "127.0.0.1" -or
        $response.ResponseUri.Port -ne $Uri.Port) {
      throw "The loopback endpoint returned an unexpected HTTP response."
    }
    $reader = New-Object IO.StreamReader($response.GetResponseStream())
    return ($reader.ReadToEnd() | ConvertFrom-Json)
  } finally {
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $response) { $response.Dispose() }
  }
}

function Test-CodexWindowsDebuggerUrl {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][int]$Port
  )
  try { $uri = [uri]$Value } catch { return $false }
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne "ws" -or $uri.Port -ne $Port -or
      -not [string]::IsNullOrEmpty($uri.UserInfo)) { return $false }
  $hostText = ([string]$uri.Host).Trim([char[]]"[]")
  if ([string]::Equals($hostText, "localhost", [StringComparison]::OrdinalIgnoreCase)) { return $true }
  [Net.IPAddress]$address = $null
  if (-not [Net.IPAddress]::TryParse($hostText, [ref]$address)) { return $false }
  return [Net.IPAddress]::IsLoopback($address)
}

function Test-CodexWindowsCdpEndpoint {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$Port,
    [Parameter(Mandatory = $true)]$PackageInfo,
    [ValidateRange(100, 30000)][int]$TimeoutMs = 2000
  )

  if (-not (Test-CodexWindowsPortOwnership -Port $Port -PackageInfo $PackageInfo)) { return $false }
  try {
    $version = Invoke-CodexWindowsLoopbackJson -Uri ([uri]"http://127.0.0.1:$Port/json/version") -TimeoutMs $TimeoutMs
    if (-not (Test-CodexWindowsDebuggerUrl -Value ([string]$version.webSocketDebuggerUrl) -Port $Port)) { return $false }
    $targets = @(Invoke-CodexWindowsLoopbackJson -Uri ([uri]"http://127.0.0.1:$Port/json/list") -TimeoutMs $TimeoutMs)
    if (-not (Test-CodexWindowsPortOwnership -Port $Port -PackageInfo $PackageInfo)) { return $false }
    foreach ($target in $targets) {
      if ($target.type -eq "page" -and ([string]$target.url).StartsWith("app://", [StringComparison]::OrdinalIgnoreCase) -and
          (Test-CodexWindowsDebuggerUrl -Value ([string]$target.webSocketDebuggerUrl) -Port $Port)) {
        return Test-CodexWindowsPortOwnership -Port $Port -PackageInfo $PackageInfo
      }
    }
  } catch { return $false }
  return $false
}

function Read-CodexWindowsState {
  [CmdletBinding()]
  param(
    [string]$Path = $script:CodexWindowsStatePath
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { $state = Read-CodexWindowsUtf8Text -Path $Path | ConvertFrom-Json } catch {
    throw "The Windows skin state file is not valid JSON."
  }
  $properties = @($state.PSObject.Properties.Name)
  foreach ($required in @("schemaVersion", "platform", "injectorPid", "injectorStartedAt", "nodePath", "injectorPath", "port")) {
    if ($properties -notcontains $required) { throw "The Windows skin state file is missing $required." }
  }
  if ([int]$state.schemaVersion -ne 5 -or [string]$state.platform -notin @("win32-x64", "win32-arm64")) {
    throw "The Windows skin state identity is not supported."
  }
  if ([int]$state.injectorPid -le 0 -or [int]$state.port -lt 1 -or [int]$state.port -gt 65535) {
    throw "The Windows skin state contains an invalid PID or port."
  }
  $state
}

function Test-CodexWindowsOwnedInstallRoot {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Root)

  try {
    $resolved = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container) -or
        -not (Test-CodexWindowsTreeNoReparse -Path $resolved)) { return $false }
    $identityPath = Join-Path $resolved '.codex-immersive-skin-install.json'
    if (-not (Test-Path -LiteralPath $identityPath -PathType Leaf)) { return $false }
    $identity = Read-CodexWindowsUtf8Text -Path $identityPath | ConvertFrom-Json
    if ([int]$identity.schemaVersion -ne 1 -or
        [string]$identity.product -ne 'Codex Immersive Skin' -or
        -not (Test-CodexWindowsPathEqual -First ([string]$identity.installedRoot) -Second $resolved)) {
      return $false
    }
    return (Test-Path -LiteralPath (Join-Path $resolved 'VERSION') -PathType Leaf) -and
      (Test-Path -LiteralPath (Join-Path $resolved 'scripts\injector.mjs') -PathType Leaf)
  } catch {
    return $false
  }
}

function Resolve-CodexWindowsRecordedInjectorPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][string]$CurrentInjectorPath,
    [Parameter(Mandatory = $true)][string]$InstallRoot
  )

  $recorded = [string]$State.injectorPath
  if ((Test-CodexWindowsPathEqual -First $recorded -Second $CurrentInjectorPath) -and
      (Test-Path -LiteralPath $CurrentInjectorPath -PathType Leaf)) {
    return [IO.Path]::GetFullPath($CurrentInjectorPath)
  }

  $installedInjector = Join-Path ([IO.Path]::GetFullPath($InstallRoot)) 'scripts\injector.mjs'
  if ((Test-CodexWindowsPathEqual -First $recorded -Second $installedInjector) -and
      (Test-CodexWindowsOwnedInstallRoot -Root $InstallRoot)) {
    return [IO.Path]::GetFullPath($installedInjector)
  }
  throw 'The recorded injector does not belong to the current project or verified installed copy.'
}

function Test-CodexWindowsRecordedInjector {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)]$RuntimeInfo,
    [Parameter(Mandatory = $true)][string]$ExpectedInjectorPath
  )

  $runtimeLock = $null
  try {
    if ([int]$State.schemaVersion -ne 5 -or
        [string]$State.platform -ne (Get-CodexWindowsRuntimePlatform -RuntimeInfo $RuntimeInfo)) { return $false }
    $stateNodePath = [string]$State.nodePath
    $runtimeNodePath = [string]$RuntimeInfo.NodePath
    $stateInjectorPath = [string]$State.injectorPath
    if (-not (Test-CodexWindowsPathEqual -First $stateNodePath -Second $runtimeNodePath)) { return $false }
    if (-not (Test-CodexWindowsPathEqual -First $stateInjectorPath -Second $ExpectedInjectorPath)) { return $false }
    if (-not (Test-Path -LiteralPath $ExpectedInjectorPath -PathType Leaf)) { return $false }

    $runtimeLock = Open-CodexWindowsRuntimeLock -RuntimeInfo $RuntimeInfo

    $identity = Get-CodexWindowsProcessIdentity -ProcessId ([int]$State.injectorPid)
    if (-not (Test-CodexWindowsPathEqual -First $identity.Path -Second $RuntimeInfo.NodePath)) { return $false }
    $savedStart = [datetime]::Parse([string]$State.injectorStartedAt).ToUniversalTime()
    $actualStart = [datetime]::Parse([string]$identity.StartTimeUtc).ToUniversalTime()
    if ([math]::Abs(($savedStart - $actualStart).TotalMilliseconds) -gt 1) { return $false }

    $arguments = @([CodexImmersiveSkin.WindowsNative]::ParseCommandLine($identity.CommandLine))
    if ($arguments.Count -ne 7 -or
        -not [IO.Path]::IsPathRooted([string]$arguments[0]) -or
        -not [IO.Path]::IsPathRooted([string]$arguments[1]) -or
        -not (Test-CodexWindowsPathEqual -First ([string]$arguments[0]) -Second $RuntimeInfo.NodePath) -or
        -not (Test-CodexWindowsPathEqual -First ([string]$arguments[1]) -Second $ExpectedInjectorPath)) { return $false }
    if ([string]$arguments[2] -ne "--watch" -or
        [string]$arguments[3] -ne "--port" -or
        [string]$arguments[4] -ne [string]$State.port -or
        [string]$arguments[5] -ne "--theme-dir" -or
        -not [IO.Path]::IsPathRooted([string]$arguments[6])) { return $false }
    if ($State.PSObject.Properties.Name -notcontains "themeDir" -or
        -not (Test-CodexWindowsPathEqual -First ([string]$arguments[6]) -Second ([string]$State.themeDir))) {
      return $false
    }

    $identityAfter = Get-CodexWindowsProcessIdentity -ProcessId ([int]$State.injectorPid)
    return (Test-CodexWindowsPathEqual -First $identityAfter.Path -Second $identity.Path) -and
      [string]::Equals($identityAfter.StartTimeUtc, $identity.StartTimeUtc, [StringComparison]::Ordinal) -and
      [string]::Equals($identityAfter.CommandLine, $identity.CommandLine, [StringComparison]::Ordinal)
  } catch {
    return $false
  } finally {
    if ($null -ne $runtimeLock) { $runtimeLock.Dispose() }
  }
}
