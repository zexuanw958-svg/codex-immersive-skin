import test from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const common = path.join(root, "scripts", "common-windows.ps1");
const doctor = path.join(root, "scripts", "doctor-windows.ps1");
const start = path.join(root, "scripts", "start-dream-skin-windows.ps1");
const restore = path.join(root, "scripts", "restore-dream-skin-windows.ps1");

const windowsOnly = process.platform === "win32" ? test : test.skip;

function psQuote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runPowerShell(command) {
  return spawnSync("powershell.exe", [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "RemoteSigned",
    "-Command", command,
  ], { encoding: "utf8" });
}

function importPowerShellFunctions(file, names) {
  const requested = names.map(psQuote).join(", ");
  return [
    "$tokens = $null; $errors = $null",
    `$ast = [Management.Automation.Language.Parser]::ParseFile(${psQuote(file)}, [ref]$tokens, [ref]$errors)`,
    "if ($errors.Count -ne 0) { throw ($errors | Out-String) }",
    `$requested = @(${requested})`,
    "foreach ($name in $requested) {",
    "  $matches = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))",
    "  if ($matches.Count -ne 1) { throw ('Expected one function named ' + $name) }",
    "  Invoke-Expression $matches[0].Extent.Text",
    "}",
  ].join("\n");
}

test("Windows runtime scripts expose the required fail-closed primitives", async () => {
  const [commonSource, doctorSource, startSource, restoreSource] = await Promise.all([
    fs.readFile(common, "utf8"),
    fs.readFile(doctor, "utf8"),
    fs.readFile(start, "utf8"),
    fs.readFile(restore, "utf8"),
  ]);

  for (const name of [
    "Get-CodexWindowsPackage",
    "Resolve-CodexWindowsRuntime",
    "Initialize-WindowsRuntime",
    "Test-CodexWindowsBlockMapFile",
    "Open-CodexWindowsRuntimeLock",
    "Get-CodexWindowsProcessIdentity",
    "Stop-CodexWindowsVerifiedProcess",
    "Request-CodexWindowsVerifiedMainWindowClose",
    "Get-CodexWindowsTcpListener",
    "Test-CodexWindowsPortAvailable",
    "Test-CodexWindowsProcessDescendant",
    "Test-CodexWindowsPortOwnership",
    "Test-CodexWindowsCdpEndpoint",
    "Read-CodexWindowsState",
    "Test-CodexWindowsRecordedInjector",
    "ConvertTo-CodexSafePath",
  ]) {
    assert.match(commonSource, new RegExp(`function\\s+${name}\\b`));
  }

  assert.match(commonSource, /OpenAI\.Codex/);
  assert.match(commonSource, /AppxManifest\.xml/);
  assert.match(commonSource, /AppxSignature\.p7x/);
  assert.match(commonSource, /AppxBlockMap\.xml/);
  assert.match(commonSource, /OpenAI\.Codex_2p2nqsd0c76g0/);
  assert.match(commonSource, /CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B/);
  assert.match(commonSource, /Microsoft Marketplace CA/);
  assert.match(commonSource, /SignatureKind/);
  assert.match(commonSource, /Get-AuthenticodeSignature/);
  assert.match(commonSource, /OpenAI[\\/]+Codex[\\/]+runtimes[\\/]+cua_node/);
  assert.match(commonSource, /Get-FileHash/);
  assert.match(commonSource, /NodeSha256/);
  assert.match(commonSource, /netstat\.exe/);
  assert.match(commonSource, /127\.0\.0\.1/);
  assert.match(commonSource, /::1/);
  assert.match(commonSource, /--watch/);
  assert.match(commonSource, /StartTimeUtc/);
  assert.match(commonSource, /Global\\CodexImmersiveSkin\./);
  assert.match(commonSource, /WindowsIdentity/);
  assert.match(commonSource, /MutexSecurity/);
  assert.match(commonSource, /StandardOutputEncoding/);
  assert.match(commonSource, /StandardErrorEncoding/);
  assert.match(commonSource, /CloseMainWindowIfIdentityMatches/);
  assert.match(commonSource, /SendMessageTimeout/);
  assert.match(doctorSource, /Open-CodexWindowsRuntimeLock/);
  for (const lifecycleSource of [startSource, restoreSource]) {
    assert.match(lifecycleSource, /Request-CodexWindowsVerifiedMainWindowClose/);
    assert.doesNotMatch(lifecycleSource, /\.CloseMainWindow\s*\(/);
  }

  const forbiddenMutation = /\b(?:Start-Process|Stop-Process|taskkill|Remove-Item|Set-Content|Add-Content|Out-File|New-Item|Copy-Item|Move-Item)\b/i;
  assert.doesNotMatch(commonSource, forbiddenMutation);
  assert.doesNotMatch(doctorSource, forbiddenMutation);
  assert.doesNotMatch(`${commonSource}\n${doctorSource}`, /(?:write|rename|copy|remove).*app\.asar/i);
});

windowsOnly("remaining argument normalization drops PowerShell empty sentinels", () => {
  const command = [
    `. ${psQuote(common)}`,
    "$values = @(ConvertTo-CodexWindowsRemainingArguments -Values @($null, '', '--reload', '9341'))",
    "[pscustomobject]@{ count = $values.Count; values = $values } | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {
    count: 2,
    values: ["--reload", "9341"],
  });
});

windowsOnly("failed Start restores a config snapshot through File.Replace on PowerShell 5.1 paths", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive rollback 中文 "));
  try {
    const snapshot = path.join(directory, "snapshot before start.toml");
    const config = path.join(directory, "config target.toml");
    await fs.writeFile(snapshot, "before\n", "utf8");
    await fs.writeFile(config, "during\n", "utf8");
    const command = [
      importPowerShellFunctions(start, [
        "Test-CodexWindowsTransientReplaceError",
        "Get-CodexWindowsFileHashWithRetry",
        "Invoke-CodexWindowsFileReplace",
        "Restore-ConfigSnapshot",
      ]),
      `$script:ConfigPath = ${psQuote(config)}`,
      `$snapshot = ${psQuote(snapshot)}`,
      "$snapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash",
      "$currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash",
      "Restore-ConfigSnapshot -SnapshotPath $snapshot -SnapshotHash $snapshotHash -ExpectedCurrentHash $currentHash",
      "@(Get-ChildItem -LiteralPath (Split-Path -Parent $script:ConfigPath) -Force | Sort-Object Name | Select-Object -ExpandProperty Name) | ConvertTo-Json -Compress",
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await fs.readFile(config, "utf8"), "before\n");
    assert.deepEqual(JSON.parse(result.stdout.trim()), [
      "config target.toml",
      "snapshot before start.toml",
    ]);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

windowsOnly("config snapshot replacement retries a transient sharing violation with CAS intact", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-replace-retry-"));
  const holderReady = path.join(directory, "holder-ready");
  const snapshot = path.join(directory, "snapshot.toml");
  const config = path.join(directory, "config.toml");
  let holder;
  try {
    await fs.writeFile(snapshot, "before\n", "utf8");
    await fs.writeFile(config, "during\n", "utf8");
    const holderCommand = [
      `$stream = [IO.File]::Open(${psQuote(config)}, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)`,
      `[IO.File]::WriteAllText(${psQuote(holderReady)}, 'ready')`,
      "try { Start-Sleep -Milliseconds 1200 } finally { $stream.Dispose() }",
    ].join("\n");
    holder = spawn("powershell.exe", [
      "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", holderCommand,
    ], { windowsHide: true, stdio: "ignore" });
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      try {
        await fs.access(holderReady);
        break;
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
    }
    await fs.access(holderReady);

    const command = [
      importPowerShellFunctions(start, [
        "Test-CodexWindowsTransientReplaceError",
        "Get-CodexWindowsFileHashWithRetry",
        "Invoke-CodexWindowsFileReplace",
        "Restore-ConfigSnapshot",
      ]),
      `$script:ConfigPath = ${psQuote(config)}`,
      `$snapshot = ${psQuote(snapshot)}`,
      "$snapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash",
      "$currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash",
      "$script:replaceAttempts = 0",
      "function Invoke-CodexWindowsFileReplace {",
      "  param([string]$SourcePath, [string]$DestinationPath, [string]$BackupPath)",
      "  $script:replaceAttempts++",
      "  [IO.File]::Replace($SourcePath, $DestinationPath, $BackupPath)",
      "}",
      "Restore-ConfigSnapshot -SnapshotPath $snapshot -SnapshotHash $snapshotHash -ExpectedCurrentHash $currentHash",
      "$script:replaceAttempts",
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.ok(Number.parseInt(result.stdout.trim(), 10) >= 2,
      `expected File.Replace itself to retry, got: ${result.stdout}`);
    assert.equal(await fs.readFile(config, "utf8"), "before\n");
  } finally {
    if (holder && holder.exitCode === null) holder.kill();
    await fs.rm(directory, { recursive: true, force: true });
  }
});

windowsOnly("config snapshot replacement does not retry a non-transient replace failure", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-replace-hard-failure-"));
  try {
    const snapshot = path.join(directory, "snapshot.toml");
    const config = path.join(directory, "config.toml");
    await fs.writeFile(snapshot, "before\n", "utf8");
    await fs.writeFile(config, "during\n", "utf8");
    const command = [
      importPowerShellFunctions(start, [
        "Test-CodexWindowsTransientReplaceError",
        "Get-CodexWindowsFileHashWithRetry",
        "Invoke-CodexWindowsFileReplace",
        "Restore-ConfigSnapshot",
      ]),
      `$script:ConfigPath = ${psQuote(config)}`,
      `$snapshot = ${psQuote(snapshot)}`,
      "$snapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash",
      "$currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash",
      "$script:replaceAttempts = 0",
      "function Invoke-CodexWindowsFileReplace {",
      "  param([string]$SourcePath, [string]$DestinationPath, [string]$BackupPath)",
      "  $script:replaceAttempts++",
      "  throw [ArgumentException]::new('simulated non-transient replace failure')",
      "}",
      "$failedClosed = $false",
      "try { Restore-ConfigSnapshot -SnapshotPath $snapshot -SnapshotHash $snapshotHash -ExpectedCurrentHash $currentHash } catch { $failedClosed = $true }",
      "[pscustomobject]@{ failedClosed=$failedClosed; replaceAttempts=$script:replaceAttempts; names=@(Get-ChildItem -LiteralPath (Split-Path -Parent $script:ConfigPath) -Force | Sort-Object Name | Select-Object -ExpandProperty Name) } | ConvertTo-Json -Compress",
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.deepEqual(JSON.parse(result.stdout.trim()), {
      failedClosed: true,
      replaceAttempts: 1,
      names: ["config.toml", "snapshot.toml"],
    });
    assert.equal(await fs.readFile(config, "utf8"), "during\n");
    assert.equal(await fs.readFile(snapshot, "utf8"), "before\n");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

windowsOnly("config snapshot replacement retries a transient CAS hash read denial", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-hash-retry-"));
  try {
    const snapshot = path.join(directory, "snapshot.toml");
    const config = path.join(directory, "config.toml");
    await fs.writeFile(snapshot, "before\n", "utf8");
    await fs.writeFile(config, "during\n", "utf8");
    const command = [
      importPowerShellFunctions(start, [
        "Test-CodexWindowsTransientReplaceError",
        "Get-CodexWindowsFileHashWithRetry",
        "Invoke-CodexWindowsFileReplace",
        "Restore-ConfigSnapshot",
      ]),
      `$script:ConfigPath = ${psQuote(config)}`,
      `$snapshot = ${psQuote(snapshot)}`,
      "$snapshotHash = (Microsoft.PowerShell.Utility\\Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash",
      "$currentHash = (Microsoft.PowerShell.Utility\\Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash",
      "$script:hashAttempts = 0",
      "function Get-FileHash {",
      "  param([string]$Algorithm, [string]$LiteralPath)",
      "  if ($LiteralPath -eq $script:ConfigPath) {",
      "    $script:hashAttempts++",
      "    if ($script:hashAttempts -eq 1) { throw [UnauthorizedAccessException]::new('simulated transient hash denial') }",
      "  }",
      "  Microsoft.PowerShell.Utility\\Get-FileHash -Algorithm $Algorithm -LiteralPath $LiteralPath",
      "}",
      "Restore-ConfigSnapshot -SnapshotPath $snapshot -SnapshotHash $snapshotHash -ExpectedCurrentHash $currentHash",
      "[pscustomobject]@{ hashAttempts=$script:hashAttempts; content=[IO.File]::ReadAllText($script:ConfigPath) } | ConvertTo-Json -Compress",
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const value = JSON.parse(result.stdout.trim());
    assert.ok(value.hashAttempts >= 2);
    assert.equal(value.content, "before\n");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

windowsOnly("config snapshot replacement refuses a changed expected hash and preserves recovery bytes", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive-replace-cas-"));
  try {
    const snapshot = path.join(directory, "snapshot.toml");
    const config = path.join(directory, "config.toml");
    await fs.writeFile(snapshot, "before\n", "utf8");
    await fs.writeFile(config, "concurrent\n", "utf8");
    const command = [
      importPowerShellFunctions(start, [
        "Test-CodexWindowsTransientReplaceError",
        "Get-CodexWindowsFileHashWithRetry",
        "Invoke-CodexWindowsFileReplace",
        "Restore-ConfigSnapshot",
      ]),
      `$script:ConfigPath = ${psQuote(config)}`,
      `$snapshot = ${psQuote(snapshot)}`,
      "$snapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash",
      "$wrongExpectedHash = ('0' * 64)",
      "$failedClosed = $false",
      "try { Restore-ConfigSnapshot -SnapshotPath $snapshot -SnapshotHash $snapshotHash -ExpectedCurrentHash $wrongExpectedHash } catch { $failedClosed = $true }",
      "[pscustomobject]@{ failedClosed=$failedClosed; configHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash; snapshotHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash } | ConvertTo-Json -Compress",
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const value = JSON.parse(result.stdout.trim());
    assert.equal(value.failedClosed, true);
    assert.equal(value.snapshotHash.length, 64);
    assert.notEqual(value.configHash, value.snapshotHash);
    assert.equal(await fs.readFile(config, "utf8"), "concurrent\n");
    assert.equal(await fs.readFile(snapshot, "utf8"), "before\n");
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

windowsOnly("a short-lived launcher hands CDP identity to the transaction-created Codex main process", () => {
  const command = [
    importPowerShellFunctions(start, [
      "Get-CodexProcessIdentityKey",
      "Add-CodexLaunchObservedIdentity",
      "Get-CodexTransactionDebugProcesses",
      "Add-CodexLaunchObservedTransactionProcesses",
      "Wait-VerifiedCdpEndpoint",
    ]),
    "$package = [pscustomobject]@{ AppExecutable = 'verified-chatgpt.exe' }",
    "$launch = [pscustomobject]@{",
    "  Process = [pscustomobject]@{ Id = 100; HasExited = $true }",
    "  StartedAtUtc = '2026-07-19T00:00:00.0000000Z'",
    "  ExcludedIdentityKeys = @()",
    "  LaunchToken = 'launch-token'",
      "  OriginalIdentity = $null",
      "  Identity = $null",
      "  ObservedIdentities = @()",
      "}",
    "function New-TestIdentity([int]$ProcessId, [string]$StartedAt, [bool]$DebugArguments) {",
    "  [pscustomobject]@{",
    "    ProcessId = $ProcessId",
    "    StartTimeUtc = $StartedAt",
    "    CommandLine = ('pid-' + $ProcessId)",
    "    Verified = $true",
    "    DebugArguments = $DebugArguments",
    "    LaunchToken = 'launch-token'",
    "  }",
    "}",
    "$first = New-TestIdentity 200 '2026-07-19T00:00:01.0000000Z' $true",
    "$final = New-TestIdentity 300 '2026-07-19T00:00:02.0000000Z' $true",
    "$script:poll = 0",
    "function Get-VerifiedCodexMainProcesses {",
    "  $script:poll++",
    "  $identity = if ($script:poll -eq 1) { $first } else { $final }",
    "  return @([pscustomobject]@{ Process = [pscustomobject]@{ Id = $identity.ProcessId }; Identity = $identity })",
    "}",
    "function Get-CodexWindowsProcessIdentity([int]$ProcessId) {",
    "  if ($ProcessId -eq 200) { return $first }",
    "  if ($ProcessId -eq 300) { return $final }",
    "  throw 'process exited'",
    "}",
    "function Test-VerifiedCodexMainIdentity($Identity, $PackageInfo) { return [bool]$Identity.Verified }",
    "function Test-CodexDebugIdentityForPort($Identity, [int]$Port, [string]$LaunchToken) { return [bool]$Identity.DebugArguments -and $Port -eq 9341 -and $Identity.LaunchToken -eq $LaunchToken }",
    "function Test-VerifiedCdpEndpoint([int]$Port, $PackageInfo) { return $script:launch.Identity.ProcessId -eq 300 }",
    "function Start-Sleep { param([int]$Milliseconds) }",
    "$ok = Wait-VerifiedCdpEndpoint -Port 9341 -PackageInfo $package -LaunchContext $launch -TimeoutSeconds 1",
    "[pscustomobject]@{ ok = $ok; processId = $launch.Identity.ProcessId; polls = $script:poll } | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {
    ok: true,
    processId: 300,
    polls: 2,
  });
});

windowsOnly("Start builds a real handoff context with exact transaction arguments", () => {
  const command = [
    `. ${psQuote(common)}`,
    "Initialize-CodexWindowsNative",
    importPowerShellFunctions(start, [
      "Test-CodexDebugIdentityForPort",
      "Get-CodexProcessIdentityKey",
      "Add-CodexLaunchObservedIdentity",
      "Get-CodexTransactionDebugProcesses",
      "New-CodexLaunchContext",
      "Start-CodexWithCdp",
      "Add-CodexLaunchObservedTransactionProcesses",
      "Wait-VerifiedCdpEndpoint",
    ]),
    "$package = [pscustomobject]@{ AppExecutable = 'C:\\Program Files\\WindowsApps\\OpenAI.Codex\\app\\ChatGPT.exe' }",
    "$script:started = $false",
    "$script:capturedArguments = @()",
    "function Get-VerifiedCodexMainProcesses {",
    "  if (-not $script:started -or $null -eq $script:candidate) { return @() }",
    "  return @([pscustomobject]@{ Process=[pscustomobject]@{ Id=$script:candidate.ProcessId }; Identity=$script:candidate })",
    "}",
    "function Start-Process {",
    "  param([string]$FilePath, [string[]]$ArgumentList, [switch]$PassThru)",
    "  $script:capturedFile = $FilePath",
    "  $script:capturedArguments = @($ArgumentList)",
    "  $script:started = $true",
    "  return [pscustomobject]@{ Id=100; HasExited=$true }",
    "}",
    "$launch = New-CodexLaunchContext",
    "$null = Start-CodexWithCdp -Port 9341 -PackageInfo $package -LaunchContext $launch",
    "$candidateStart = ([DateTime]::Parse($launch.StartedAtUtc).ToUniversalTime().AddMilliseconds(1)).ToString('o')",
    "$candidateLine = ('\"' + $script:capturedFile + '\" ' + ($script:capturedArguments -join ' '))",
    "$script:candidate = [pscustomobject]@{ ProcessId=200; StartTimeUtc=$candidateStart; CommandLine=$candidateLine; Verified=$true }",
    "function Get-CodexWindowsProcessIdentity([int]$ProcessId) { if ($ProcessId -eq 200) { return $script:candidate }; throw 'launcher exited' }",
    "function Test-VerifiedCodexMainIdentity($Identity, $PackageInfo) { return [bool]$Identity.Verified }",
    "function Test-VerifiedCdpEndpoint([int]$Port, $PackageInfo) { return $true }",
    "$ok = Wait-VerifiedCdpEndpoint -Port 9341 -PackageInfo $package -LaunchContext $launch -TimeoutSeconds 1",
    "[pscustomobject]@{ ok=$ok; started=$launch.Started; processId=$launch.Identity.ProcessId; observed=@($launch.ObservedIdentities).Count; file=$script:capturedFile; arguments=$script:capturedArguments; token=$launch.LaunchToken } | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const value = JSON.parse(result.stdout.trim());
  assert.equal(value.ok, true);
  assert.equal(value.started, true);
  assert.equal(value.processId, 200);
  assert.equal(value.observed, 1);
  assert.equal(value.file, "C:\\Program Files\\WindowsApps\\OpenAI.Codex\\app\\ChatGPT.exe");
  assert.deepEqual(value.arguments.slice(0, 2), [
    "--remote-debugging-address=127.0.0.1",
    "--remote-debugging-port=9341",
  ]);
  assert.equal(value.arguments.length, 3);
  assert.match(value.arguments[2], /^--codex-immersive-launch-token=[0-9a-f]{32}$/);
  assert.equal(value.arguments[2], `--codex-immersive-launch-token=${value.token}`);
});

windowsOnly("transaction Codex discovery rejects baseline, pre-launch, and argument-losing processes", () => {
  const command = [
    importPowerShellFunctions(start, [
      "Get-CodexProcessIdentityKey",
      "Get-CodexTransactionDebugProcesses",
    ]),
    "function New-TestIdentity([int]$ProcessId, [string]$StartedAt, [bool]$DebugArguments) {",
    "  [pscustomobject]@{ ProcessId=$ProcessId; StartTimeUtc=$StartedAt; CommandLine=('pid-' + $ProcessId); DebugArguments=$DebugArguments; LaunchToken='launch-token' }",
    "}",
    "$baseline = New-TestIdentity 10 '2026-07-19T00:00:01.0000000Z' $true",
    "$preLaunch = New-TestIdentity 20 '2026-07-18T23:59:59.0000000Z' $true",
    "$lostArguments = New-TestIdentity 30 '2026-07-19T00:00:02.0000000Z' $false",
    "$eligible = New-TestIdentity 40 '2026-07-19T00:00:03.0000000Z' $true",
    "$script:entries = @($baseline, $preLaunch, $lostArguments, $eligible)",
    "function Get-VerifiedCodexMainProcesses { return @($script:entries | ForEach-Object { [pscustomobject]@{ Process=[pscustomobject]@{ Id=$_.ProcessId }; Identity=$_ } }) }",
    "function Test-CodexDebugIdentityForPort($Identity, [int]$Port, [string]$LaunchToken) { return [bool]$Identity.DebugArguments -and $Port -eq 9341 -and $Identity.LaunchToken -eq $LaunchToken }",
    "$excluded = @(Get-CodexProcessIdentityKey -Identity $baseline)",
    "$found = @(Get-CodexTransactionDebugProcesses -Port 9341 -PackageInfo ([pscustomobject]@{}) -StartedAtUtc ([DateTime]'2026-07-19T00:00:00Z') -ExcludedIdentityKeys $excluded -LaunchToken 'launch-token')",
    "[pscustomobject]@{ count=$found.Count; processId=$found[0].Identity.ProcessId } | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(JSON.parse(result.stdout.trim()), { count: 1, processId: 40 });
});

windowsOnly("transaction Codex discovery fails closed when more than one new debug main appears", () => {
  const command = [
    importPowerShellFunctions(start, [
      "Get-CodexProcessIdentityKey",
      "Add-CodexLaunchObservedIdentity",
      "Get-CodexTransactionDebugProcesses",
      "Add-CodexLaunchObservedTransactionProcesses",
      "Wait-VerifiedCdpEndpoint",
      "Stop-CodexLaunchContextProcesses",
    ]),
    "$launch = [pscustomobject]@{ Process=[pscustomobject]@{ Id=100; HasExited=$true }; Started=$true; StartedAtUtc='2026-07-19T00:00:00.0000000Z'; ExcludedIdentityKeys=@(); LaunchToken='launch-token'; OriginalIdentity=$null; Identity=$null; ObservedIdentities=@() }",
    "$one = [pscustomobject]@{ ProcessId=200; StartTimeUtc='2026-07-19T00:00:01.0000000Z'; CommandLine='one'; DebugArguments=$true; LaunchToken='launch-token' }",
    "$two = [pscustomobject]@{ ProcessId=300; StartTimeUtc='2026-07-19T00:00:02.0000000Z'; CommandLine='two'; DebugArguments=$true; LaunchToken='launch-token' }",
    "function Get-VerifiedCodexMainProcesses { return @([pscustomobject]@{Identity=$one}, [pscustomobject]@{Identity=$two}) }",
    "function Get-CodexWindowsProcessIdentity([int]$ProcessId) { if ($ProcessId -eq 200) { return $one }; if ($ProcessId -eq 300) { return $two }; throw 'missing' }",
    "function Test-VerifiedCodexMainIdentity($Identity, $PackageInfo) { return $true }",
    "function Test-CodexDebugIdentityForPort($Identity, [int]$Port, [string]$LaunchToken) { return [bool]$Identity.DebugArguments -and $Identity.LaunchToken -eq $LaunchToken }",
    "$failedClosed = $false",
    "try { $null = Wait-VerifiedCdpEndpoint -Port 9341 -PackageInfo ([pscustomobject]@{}) -LaunchContext $launch -TimeoutSeconds 1 } catch { $failedClosed = $_.Exception.Message -match '多个' }",
    "$script:stopped = @()",
    "function Stop-TransactionCodex($Identity, $PackageInfo) { $script:stopped += [int]$Identity.ProcessId; return $true }",
    "$cleanupOk = Stop-CodexLaunchContextProcesses -LaunchContext $launch -PackageInfo ([pscustomobject]@{})",
    "[pscustomobject]@{ failedClosed=$failedClosed; observed=@($launch.ObservedIdentities | ForEach-Object ProcessId); cleanupOk=$cleanupOk; stopped=@($script:stopped) } | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {
    failedClosed: true,
    observed: [200, 300],
    cleanupOk: true,
    stopped: [200, 300],
  });
});

windowsOnly("a post-wait transaction main is captured before outer uniqueness rejection", () => {
  const command = [
    importPowerShellFunctions(start, [
      "Get-CodexProcessIdentityKey",
      "Add-CodexLaunchObservedIdentity",
      "Get-CodexTransactionDebugProcesses",
      "Add-CodexLaunchObservedTransactionProcesses",
      "Wait-VerifiedCdpEndpoint",
      "Stop-CodexLaunchContextProcesses",
    ]),
    "$package = [pscustomobject]@{}",
    "$launch = [pscustomobject]@{ Process=[pscustomobject]@{ Id=100; HasExited=$true }; Started=$true; StartedAtUtc='2026-07-19T00:00:00.0000000Z'; ExcludedIdentityKeys=@(); LaunchToken='launch-token'; OriginalIdentity=$null; Identity=$null; ObservedIdentities=@() }",
    "$one = [pscustomobject]@{ ProcessId=200; StartTimeUtc='2026-07-19T00:00:01.0000000Z'; CommandLine='one'; DebugArguments=$true; LaunchToken='launch-token' }",
    "$two = [pscustomobject]@{ ProcessId=300; StartTimeUtc='2026-07-19T00:00:02.0000000Z'; CommandLine='two'; DebugArguments=$true; LaunchToken='launch-token' }",
    "$script:phase = 'wait'",
    "function Get-VerifiedCodexMainProcesses { $identity = if ($script:phase -eq 'wait') { $one } else { $two }; return @([pscustomobject]@{Identity=$identity}) }",
    "function Get-CodexWindowsProcessIdentity([int]$ProcessId) { if ($ProcessId -eq 200) { return $one }; if ($ProcessId -eq 300) { return $two }; throw 'missing' }",
    "function Test-VerifiedCodexMainIdentity($Identity, $PackageInfo) { return $true }",
    "function Test-CodexDebugIdentityForPort($Identity, [int]$Port, [string]$LaunchToken) { return [bool]$Identity.DebugArguments -and $Identity.LaunchToken -eq $LaunchToken }",
    "function Test-VerifiedCdpEndpoint([int]$Port, $PackageInfo) { return $true }",
    "$ok = Wait-VerifiedCdpEndpoint -Port 9341 -PackageInfo $package -LaunchContext $launch -TimeoutSeconds 1",
    "$script:phase = 'after'",
    "$unexpected = @(Get-VerifiedCodexMainProcesses -PackageInfo $package)",
    "$captured = @(Add-CodexLaunchObservedTransactionProcesses -Entries $unexpected -Port 9341 -PackageInfo $package -LaunchContext $launch)",
    "$script:stopped = @()",
    "function Stop-TransactionCodex($Identity, $PackageInfo) { $script:stopped += [int]$Identity.ProcessId; return $true }",
    "$cleanupOk = Stop-CodexLaunchContextProcesses -LaunchContext $launch -PackageInfo $package",
    "[pscustomobject]@{ ok=$ok; captured=@($captured | ForEach-Object ProcessId); observed=@($launch.ObservedIdentities | ForEach-Object ProcessId); cleanupOk=$cleanupOk; stopped=@($script:stopped) } | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {
    ok: true,
    captured: [300],
    observed: [200, 300],
    cleanupOk: true,
    stopped: [200, 300],
  });
});

windowsOnly("transaction debug identity requires one exact loopback, port, and launch-token argument", () => {
  const command = [
    `. ${psQuote(common)}`,
    "Initialize-CodexWindowsNative",
    importPowerShellFunctions(start, ["Test-CodexDebugIdentityForPort"]),
    "$exe = 'C:\\Program Files\\WindowsApps\\OpenAI.Codex\\app\\ChatGPT.exe'",
    "$token = '7d50bbfb91c64c56a619589938777233'",
    "function Test-Command([string[]]$Arguments) {",
    "  $line = ('\"' + $exe + '\" ' + ($Arguments -join ' '))",
    "  $identity = [pscustomobject]@{ CommandLine = $line }",
    "  return Test-CodexDebugIdentityForPort -Identity $identity -Port 9341 -LaunchToken $token",
    "}",
    "$base = @('--remote-debugging-address=127.0.0.1', '--remote-debugging-port=9341', ('--codex-immersive-launch-token=' + $token))",
    "[pscustomobject]@{",
    "  exact = Test-Command $base",
    "  duplicatePort = Test-Command @($base + '--remote-debugging-port=9441')",
    "  duplicateAddress = Test-Command @($base + '--remote-debugging-address=0.0.0.0')",
    "  wrongToken = Test-Command @($base[0..1] + '--codex-immersive-launch-token=wrong')",
    "} | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {
    exact: true,
    duplicatePort: false,
    duplicateAddress: false,
    wrongToken: false,
  });
});

windowsOnly("package and local cua_node discovery validate the current MSIX installation", () => {
  const command = [
    `. ${psQuote(common)}`,
    "$runtime = Initialize-WindowsRuntime",
    "$package = $runtime.PackageInfo",
    "$runtimeLock = Open-CodexWindowsRuntimeLock -RuntimeInfo $runtime",
    "try { $lockReadable = $runtimeLock.CanRead } finally { $runtimeLock.Dispose() }",
    "[pscustomobject]@{",
    "  packageName = $package.Name",
    "  packageFamilyName = $package.PackageFamilyName",
    "  packageSignatureValid = $package.SignatureValid",
    "  packageSignatureKind = $package.SignatureKind",
    "  packageOrigin = $package.PackageOrigin",
    "  packageSignatureIssuer = $package.SignatureIssuer",
    "  blockMapValidated = $package.BlockMapValidated",
    "  appEntry = [IO.Path]::GetFileName($package.AppExecutable)",
    "  nodeVersion = $runtime.NodeVersion",
    "  nodeMatchesPackage = $runtime.NodeMatchesPackage",
    "  nodeSignatureValid = $runtime.SignatureValid",
    "  lockReadable = $lockReadable",
    "  safeNodePath = ConvertTo-CodexSafePath $runtime.NodePath",
    "} | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const value = JSON.parse(result.stdout.trim());
  assert.equal(value.packageName, "OpenAI.Codex");
  assert.equal(value.packageFamilyName, "OpenAI.Codex_2p2nqsd0c76g0");
  assert.equal(value.packageSignatureValid, true);
  assert.equal(value.packageSignatureKind, "Store");
  assert.equal(value.packageOrigin, 3);
  assert.match(value.packageSignatureIssuer, /Microsoft Marketplace CA/i);
  assert.equal(value.blockMapValidated, true);
  assert.equal(value.appEntry.toLowerCase(), "chatgpt.exe");
  assert.equal(value.nodeMatchesPackage, true);
  assert.equal(value.nodeSignatureValid, true);
  assert.equal(value.lockReadable, true);
  assert.match(value.nodeVersion, /^v?\d+\.\d+\.\d+$/);
  assert.match(value.safeNodePath, /^%LOCALAPPDATA%\\/i);
  assert.doesNotMatch(value.safeNodePath, /Users\\[^%]+/i);
});

windowsOnly("runtime discovery rejects caller-selected roots", () => {
  const command = [
    `. ${psQuote(common)}`,
    "$package = Get-CodexWindowsPackage",
    "$accepted = $true",
    "try { $null = Resolve-CodexWindowsRuntime -PackageInfo $package -LocalRuntimeRoot $package.InstallLocation } catch { $accepted = $false }",
    "$accepted",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(result.stdout.trim().toLowerCase(), "false");
});

windowsOnly("process identity is readable and recorded injector validation fails closed", () => {
  const injector = path.join(root, "scripts", "injector.mjs");
  const command = [
    `. ${psQuote(common)}`,
    "$package = Get-CodexWindowsPackage",
    "$runtime = Resolve-CodexWindowsRuntime -PackageInfo $package",
    "$identity = Get-CodexWindowsProcessIdentity -ProcessId $PID",
    `$expectedInjector = ${psQuote(injector)}`,
    "$fakeState = [pscustomobject]@{",
    "  schemaVersion = 5",
    "  platform = 'win32-x64'",
    "  injectorPid = $PID",
    "  injectorStartedAt = $identity.StartTimeUtc",
    "  nodePath = $runtime.NodePath",
    "  injectorPath = $expectedInjector",
    "  port = 9341",
    "}",
    "$accepted = Test-CodexWindowsRecordedInjector -State $fakeState -RuntimeInfo $runtime -ExpectedInjectorPath $expectedInjector",
    "[pscustomobject]@{",
    "  processPath = ConvertTo-CodexSafePath $identity.Path",
    "  parentPid = $identity.ParentProcessId",
    "  hasCommandLine = -not [string]::IsNullOrWhiteSpace($identity.CommandLine)",
    "  accepted = $accepted",
    "} | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const value = JSON.parse(result.stdout.trim());
  assert.match(value.processPath, /powershell\.exe$/i);
  assert.ok(value.parentPid > 0);
  assert.equal(value.hasCommandLine, true);
  assert.equal(value.accepted, false);
});

windowsOnly("verified process termination rejects a changed identity and stops the captured process handle", async () => {
  const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], {
    stdio: "ignore",
    windowsHide: true,
  });
  try {
    await new Promise((resolve) => setTimeout(resolve, 250));
    const reject = runPowerShell([
      `. ${psQuote(common)}`,
      `$identity = Get-CodexWindowsProcessIdentity -ProcessId ${child.pid}`,
      "$identity.StartTimeUtc = '2000-01-01T00:00:00.0000000Z'",
      "Stop-CodexWindowsVerifiedProcess -Identity $identity -TimeoutMs 2000",
    ].join("; "));
    assert.notEqual(reject.status, 0, "a mismatched start time must fail closed");
    assert.equal(child.exitCode, null, "the mismatched identity must not stop the process");

    const stop = runPowerShell([
      `. ${psQuote(common)}`,
      `$identity = Get-CodexWindowsProcessIdentity -ProcessId ${child.pid}`,
      "Stop-CodexWindowsVerifiedProcess -Identity $identity -TimeoutMs 4000",
    ].join("; "));
    assert.equal(stop.status, 0, stop.stderr);
    if (child.exitCode === null) {
      await new Promise((resolve, rejectWait) => {
        const timeout = setTimeout(() => rejectWait(new Error("verified process did not exit")), 5000);
        child.once("exit", () => { clearTimeout(timeout); resolve(); });
      });
    }
  } finally {
    if (child.exitCode === null) child.kill();
  }
});

windowsOnly("verified gentle close rejects a changed identity and requests close on the captured GUI process", async () => {
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "codex-immersive-close-"));
  const fixturePath = path.join(fixtureRoot, "verified-close-fixture.exe");
  const fixtureSource = `
using System;
using System.Drawing;
using System.Windows.Forms;
public static class VerifiedCloseFixture {
  [STAThread]
  public static void Main() {
    Application.EnableVisualStyles();
    using (Form form = new Form()) {
      form.Text = "Codex verified close fixture";
      form.StartPosition = FormStartPosition.Manual;
      form.Location = new Point(-32000, -32000);
      form.ShowInTaskbar = true;
      Application.Run(form);
    }
  }
}`;
  const compile = runPowerShell([
    `Add-Type -TypeDefinition ${psQuote(fixtureSource)}`,
    `  -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.Drawing.dll')`,
    `  -OutputAssembly ${psQuote(fixturePath)} -OutputType WindowsApplication`,
  ].join(" "));
  assert.equal(compile.status, 0, compile.stderr || compile.stdout);

  const child = spawn(fixturePath, [], { windowsHide: false, stdio: "ignore" });
  try {
    await new Promise((resolve) => setTimeout(resolve, 500));
    assert.equal(child.exitCode, null, "GUI fixture must still be running");

    const reject = runPowerShell([
      `. ${psQuote(common)}`,
      `$deadline = [DateTime]::UtcNow.AddSeconds(5)`,
      `do { $process = [Diagnostics.Process]::GetProcessById(${child.pid}); $process.Refresh(); if ($process.MainWindowHandle -ne [IntPtr]::Zero) { break }; Start-Sleep -Milliseconds 50 } while ([DateTime]::UtcNow -lt $deadline)`,
      `if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'GUI fixture did not create a main window.' }`,
      `if ($process.MainWindowTitle -ne 'Codex verified close fixture') { throw ('Unexpected GUI fixture window: ' + $process.MainWindowTitle) }`,
      `$identity = Get-CodexWindowsProcessIdentity -ProcessId ${child.pid}`,
      "$identity.StartTimeUtc = '2000-01-01T00:00:00.0000000Z'",
      "Request-CodexWindowsVerifiedMainWindowClose -Identity $identity",
    ].join("; "));
    assert.notEqual(reject.status, 0, "a mismatched start time must fail closed");
    assert.equal(child.exitCode, null, "the mismatched identity must not close the process");

    const close = runPowerShell([
      `. ${psQuote(common)}`,
      `$identity = Get-CodexWindowsProcessIdentity -ProcessId ${child.pid}`,
      "Request-CodexWindowsVerifiedMainWindowClose -Identity $identity",
    ].join("; "));
    assert.equal(close.status, 0, close.stderr || close.stdout);
    assert.equal(close.stdout.trim().toLowerCase(), "true");
  } finally {
    if (child.exitCode === null) {
      child.kill();
      await new Promise((resolve) => child.once("exit", resolve));
    }
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});

windowsOnly("the lifecycle mutex is global, current-user-only, and reentrant", () => {
  const stateRoot = path.join(os.tmpdir(), `codex-immersive-lock-acl-${process.pid}`);
  const command = [
    `. ${psQuote(common)}`,
    "$first = $null",
    "$second = $null",
    "try {",
    `  $first = Open-CodexWindowsOperationLock -StateRoot ${psQuote(stateRoot)} -TimeoutMs 1000`,
    `  $second = Open-CodexWindowsOperationLock -StateRoot ${psQuote(stateRoot)} -TimeoutMs 0`,
    "  $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User",
    "  $security = $first.Mutex.GetAccessControl()",
    "  $owner = $security.GetOwner([Security.Principal.SecurityIdentifier])",
    "  $rules = @($security.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))",
    "  $currentFull = @($rules | Where-Object {",
    "    $_.IdentityReference.Value -eq $currentSid.Value -and",
    "    $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and",
    "    -not $_.IsInherited -and",
    "    (($_.MutexRights -band [Security.AccessControl.MutexRights]::FullControl) -eq [Security.AccessControl.MutexRights]::FullControl)",
    "  }).Count -eq 1",
    "  [pscustomobject]@{",
    "    name = $first.Name",
    "    owner = $owner.Value",
    "    currentSid = $currentSid.Value",
    "    protected = $security.AreAccessRulesProtected",
    "    ruleCount = $rules.Count",
    "    currentFull = $currentFull",
    "    reentrant = $true",
    "  } | ConvertTo-Json -Compress",
    "} finally {",
    "  if ($null -ne $second) { Close-CodexWindowsOperationLock -Lock $second }",
    "  if ($null -ne $first) { Close-CodexWindowsOperationLock -Lock $first }",
    "}",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const value = JSON.parse(result.stdout.trim());
  assert.match(value.name, /^Global\\CodexImmersiveSkin\.S-1-/);
  assert.equal(value.owner, value.currentSid);
  assert.equal(value.protected, true);
  assert.equal(value.ruleCount, 1);
  assert.equal(value.currentFull, true);
  assert.equal(value.reentrant, true);
});

windowsOnly("Node output and redirected errors are decoded as strict UTF-8 independent of the console code page", async () => {
  const stderrPath = path.join(os.tmpdir(), `codex-immersive-node-stderr-${process.pid}-${Date.now()}.txt`);
  const javascript = 'process.stdout.write(JSON.stringify({ text: "晨雾" }) + "\\n"); process.stderr.write("警告\\n");';
  try {
    const command = [
      `. ${psQuote(common)}`,
      "$runtime = Initialize-WindowsRuntime",
      `$javascript = ${psQuote(javascript)}`,
      `$errorPath = ${psQuote(stderrPath)}`,
      "$originalOutputEncoding = [Console]::OutputEncoding",
      "try {",
      "  [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(936)",
      "  $result = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments @('-e', $javascript) -StandardErrorPath $errorPath",
      "} finally {",
      "  [Console]::OutputEncoding = $originalOutputEncoding",
      "}",
      "$strictUtf8 = New-Object Text.UTF8Encoding($false, $true)",
      "$errorText = [IO.File]::ReadAllText($errorPath, $strictUtf8)",
      "[pscustomobject]@{ exitCode = $result.ExitCode; output = @($result.Output); errorText = $errorText } | ConvertTo-Json -Compress",
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const value = JSON.parse(result.stdout.trim());
    assert.equal(value.exitCode, 0);
    assert.deepEqual(value.output, ['{"text":"晨雾"}']);
    assert.equal(value.errorText, "警告\n");
  } finally {
    await fs.rm(stderrPath, { force: true });
  }
});

windowsOnly("Node streaming writes decoded stdout while returning only the exit result", () => {
  const javascript = 'process.stdout.write("first\\n"); setTimeout(() => process.stdout.write("second\\n"), 25);';
  const command = [
    `. ${psQuote(common)}`,
    "$runtime = Initialize-WindowsRuntime",
    `$javascript = ${psQuote(javascript)}`,
    "$result = Invoke-CodexWindowsNode -RuntimeInfo $runtime -Arguments @('-e', $javascript) -StreamOutput",
    "Write-Output ('RESULT:' + $result.ExitCode + ':' + @($result.Output).Count)",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /^first\r?\nsecond\r?\nRESULT:0:0\r?\n?$/);
});

windowsOnly("the per-state-root operation lock excludes a concurrent lifecycle process", async () => {
  const stateRoot = path.join(os.tmpdir(), `codex-immersive-lock-${process.pid}`);
  const holder = spawn("powershell.exe", [
    "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-Command",
    [
      `. ${psQuote(common)}`,
      `$lock = Open-CodexWindowsOperationLock -StateRoot ${psQuote(stateRoot)} -TimeoutMs 1000`,
      "Write-Output 'LOCKED'",
      "Start-Sleep -Seconds 2",
      "Close-CodexWindowsOperationLock -Lock $lock",
    ].join("; "),
  ], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  try {
    await new Promise((resolve, rejectReady) => {
      let stdout = "";
      const timeout = setTimeout(() => rejectReady(new Error("lock holder did not become ready")), 5000);
      holder.stdout.on("data", (chunk) => {
        stdout += chunk.toString("utf8");
        if (stdout.includes("LOCKED")) { clearTimeout(timeout); resolve(); }
      });
      holder.once("exit", (code) => {
        if (!stdout.includes("LOCKED")) {
          clearTimeout(timeout);
          rejectReady(new Error(`lock holder exited early (${code})`));
        }
      });
    });
    const contender = runPowerShell([
      `. ${psQuote(common)}`,
      `$lock = Open-CodexWindowsOperationLock -StateRoot ${psQuote(stateRoot)} -TimeoutMs 100`,
      "Close-CodexWindowsOperationLock -Lock $lock",
    ].join("; "));
    assert.notEqual(contender.status, 0, "the concurrent lifecycle operation must be refused");
  } finally {
    if (holder.exitCode === null) holder.kill();
  }
});

windowsOnly("injector identity rejects a Node process that only mentions the expected arguments", async () => {
  const injector = path.join(root, "scripts", "injector.mjs");
  const child = spawn(process.execPath, [
    "--input-type=module",
    "--eval", "setInterval(() => {}, 1000)",
    injector,
    "--watch",
    "--port", "9341",
  ], { stdio: "ignore" });
  try {
    await new Promise((resolve) => setTimeout(resolve, 250));
    assert.equal(child.exitCode, null, "adversarial Node fixture must still be running");
    const command = [
      `. ${psQuote(common)}`,
      "$runtime = Initialize-WindowsRuntime",
      `$identity = Get-CodexWindowsProcessIdentity -ProcessId ${child.pid}`,
      "$platform = if ($runtime.Architecture -eq 'arm64') { 'win32-arm64' } else { 'win32-x64' }",
      "$state = [pscustomobject]@{",
      "  schemaVersion = 5",
      "  platform = $platform",
      `  injectorPid = ${child.pid}`,
      "  injectorStartedAt = $identity.StartTimeUtc",
      "  nodePath = $runtime.NodePath",
      `  injectorPath = ${psQuote(injector)}`,
      "  port = 9341",
      "}",
      `Test-CodexWindowsRecordedInjector -State $state -RuntimeInfo $runtime -ExpectedInjectorPath ${psQuote(injector)}`,
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(result.stdout.trim().toLowerCase(), "false");
  } finally {
    child.kill();
    await new Promise((resolve) => child.once("exit", resolve));
  }
});

windowsOnly("loopback debugger URL validation supports IPv4 and IPv6 only", () => {
  const command = [
    `. ${psQuote(common)}`,
    "[pscustomobject]@{",
    "  ipv4 = Test-CodexWindowsDebuggerUrl -Value 'ws://127.0.0.1:9341/devtools/page/a' -Port 9341",
    "  ipv6 = Test-CodexWindowsDebuggerUrl -Value 'ws://[::1]:9341/devtools/page/a' -Port 9341",
    "  publicHost = Test-CodexWindowsDebuggerUrl -Value 'ws://192.0.2.1:9341/devtools/page/a' -Port 9341",
    "} | ConvertTo-Json -Compress",
  ].join("\n");
  const result = runPowerShell(command);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {
    ipv4: true,
    ipv6: true,
    publicHost: false,
  });
});

windowsOnly("a non-GUI descendant cannot claim the Codex CDP port", async () => {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    const { port } = server.address();
    const command = [
      `. ${psQuote(common)}`,
      "$package = Get-CodexWindowsPackage",
      `Test-CodexWindowsPortOwnership -Port ${port} -PackageInfo $package`,
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(result.stdout.trim().toLowerCase(), "false");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

windowsOnly("Windows doctor is read-only and reports verified package/runtime facts", () => {
  const result = runPowerShell(`& ${psQuote(doctor)}`);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const value = JSON.parse(result.stdout.trim());
  assert.equal(value.pass, true);
  assert.equal(value.product, "Codex Immersive Skin");
  assert.match(value.platform, /^win32-/);
  assert.equal(value.package.name, "OpenAI.Codex");
  assert.equal(value.package.signatureValid, true);
  assert.equal(value.runtime.nodeMatchesPackage, true);
  assert.equal(value.runtime.signatureValid, true);
  assert.equal(value.modifiesAppAsar, false);
  assert.equal(typeof value.live, "boolean");
  assert.doesNotMatch(JSON.stringify(value), /Users\\[^%]+/i);
});
