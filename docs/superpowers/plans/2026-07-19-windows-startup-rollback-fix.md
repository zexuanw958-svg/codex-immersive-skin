# Windows CDP Startup and Rollback Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Windows Start follow a transaction-created Codex main process across a short-lived launcher or PID handoff, and make failed-Start config rollback work under Windows PowerShell 5.1 without weakening identity, loopback, port-ownership, or CAS checks.

**Architecture:** Keep package and process verification in the existing Windows lifecycle. Replace the assumption that the PID returned by `Start-Process` is the final Codex main PID with a launch context: it records the no-main-process baseline and launch timestamp, then admits only one newly created, package-verified main process with the exact loopback/port arguments. Keep config rollback as a same-directory `File.Replace`, but provide a real unique backup path because Windows PowerShell 5.1 binds `$null` as an illegal empty path; validate both the replacement and displaced-file hashes and retry only bounded transient Windows file errors with CAS before every attempt.

**Tech Stack:** Windows PowerShell 5.1, .NET `System.IO.File.Replace`, Node.js 22+ test runner, Store/MSIX process identity helpers.

---

### Task 1: Add red regression tests for PowerShell 5.1 rollback

**Files:**
- Modify: `tests/windows-runtime.test.mjs`
- Test: `tests/windows-runtime.test.mjs`

- [ ] **Step 1: Add an AST function loader used only by isolated PowerShell tests**

Add a JavaScript helper that emits PowerShell code to parse `scripts/start-dream-skin-windows.ps1`, select named `FunctionDefinitionAst` nodes, and `Invoke-Expression` their exact source. This tests production function bodies without executing Start's top-level lifecycle.

```js
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
```

- [ ] **Step 2: Add a real PowerShell 5.1 replacement test with spaces and Unicode**

Create an isolated temporary directory, set `$script:ConfigPath`, import `Restore-ConfigSnapshot`, write distinct snapshot/current bytes, call the function with their SHA-256 values, and assert the snapshot bytes replaced the target while no `.codex-immersive-*` temporary or displaced files remain.

```js
windowsOnly("failed Start restores a config snapshot through File.Replace on PowerShell 5.1 paths", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "immersive rollback 中文 "));
  try {
    const snapshot = path.join(directory, "snapshot before start.toml");
    const config = path.join(directory, "config target.toml");
    await fs.writeFile(snapshot, "before\n", "utf8");
    await fs.writeFile(config, "during\n", "utf8");
    const command = [
      importPowerShellFunctions(start, ["Test-CodexWindowsTransientReplaceError", "Restore-ConfigSnapshot"]),
      `$script:ConfigPath = ${psQuote(config)}`,
      `$snapshot = ${psQuote(snapshot)}`,
      "$snapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash",
      "$currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:ConfigPath).Hash",
      "Restore-ConfigSnapshot -SnapshotPath $snapshot -SnapshotHash $snapshotHash -ExpectedCurrentHash $currentHash",
      "Get-ChildItem -LiteralPath (Split-Path -Parent $script:ConfigPath) -Force | Select-Object -ExpandProperty Name | ConvertTo-Json -Compress",
    ].join("\n");
    const result = runPowerShell(command);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(await fs.readFile(config, "utf8"), "before\n");
    assert.deepEqual(JSON.parse(result.stdout.trim()), ["config target.toml", "snapshot before start.toml"]);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
```

- [ ] **Step 3: Run the new test and record the expected red failure**

Run: `node --test --test-name-pattern="failed Start restores" tests/windows-runtime.test.mjs`

Expected: FAIL under Windows PowerShell 5.1 with `The path is not of a legal form` from the current three-argument `File.Replace(..., $null)` call.

### Task 2: Add red regression tests for launcher handoff and fail-closed discovery

**Files:**
- Modify: `tests/windows-runtime.test.mjs`
- Test: `tests/windows-runtime.test.mjs`

- [ ] **Step 1: Add a short-lived-launcher/PID-handoff test**

Import the launch selection and wait functions from the production Start script. Mock only the process enumeration, identity reread, endpoint result, and sleep boundary. The returned `Start-Process` handle has PID 100 and is already exited; the only eligible candidate has PID 200, starts after the launch timestamp, has the verified Store identity, and contains exactly `--remote-debugging-address=127.0.0.1` plus the selected port. Assert that wait succeeds and the launch context records PID 200.

```powershell
$launch = [pscustomobject]@{
  Process = [pscustomobject]@{ Id = 100; HasExited = $true }
  StartedAtUtc = '2026-07-19T00:00:00.0000000Z'
  ExcludedIdentityKeys = @()
  OriginalIdentity = $null
  Identity = $null
}
$candidate = New-TestIdentity -ProcessId 200 -StartTimeUtc '2026-07-19T00:00:01.0000000Z' -Arguments @(
  'C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe',
  '--remote-debugging-address=127.0.0.1',
  '--remote-debugging-port=9341'
)
$script:poll = 0
function Get-VerifiedCodexMainProcesses { $script:poll++; if ($script:poll -ge 2) { [pscustomobject]@{ Identity=$candidate } } }
function Test-VerifiedCdpEndpoint { $true }
$ok = Wait-VerifiedCdpEndpoint -Port 9341 -PackageInfo $package -LaunchContext $launch -TimeoutSeconds 1
if (-not $ok -or $launch.Identity.ProcessId -ne 200) { throw 'The final main process was not adopted.' }
```

- [ ] **Step 2: Add negative cases**

Use the same isolated mocks to assert all of the following return false or throw before endpoint acceptance:

- candidate existed in `ExcludedIdentityKeys` before launch;
- candidate starts before `StartedAtUtc`;
- candidate loses either remote-debugging argument;
- two eligible newly created main processes appear;
- the first eligible PID exits and a unique later eligible PID becomes the endpoint owner, in which case only the later identity is committed.

- [ ] **Step 3: Run the new handoff tests and record the expected red failure**

Run: `node --test --test-name-pattern="launcher handoff|transaction-created Codex" tests/windows-runtime.test.mjs`

Expected: FAIL because the current Start implementation only rereads the PID returned by `Start-Process`, breaks as soon as that handle exits, and `Wait-VerifiedCdpEndpoint` accepts only a fixed `LaunchedIdentity`.

### Task 3: Implement transaction-scoped Codex main-process rediscovery

**Files:**
- Modify: `scripts/start-dream-skin-windows.ps1`
- Test: `tests/windows-runtime.test.mjs`
- Test: `tests/windows-lifecycle.test.mjs`

- [ ] **Step 1: Add identity-key and transaction-candidate helpers**

Add `Get-CodexProcessIdentityKey` and `Get-CodexTransactionDebugProcesses`. A candidate is eligible only when all checks pass: existing Store/MSIX main identity validation, exact selected loopback and port arguments, a start time at or after the launch timestamp, and absence from the baseline identity-key set.

```powershell
function Get-CodexProcessIdentityKey {
  param($Identity)
  return ([string][int]$Identity.ProcessId + '|' + [string]$Identity.StartTimeUtc)
}

function Get-CodexTransactionDebugProcesses {
  param([int]$Port, $PackageInfo, [DateTime]$StartedAtUtc, [string[]]$ExcludedIdentityKeys)
  $excluded = @{}
  foreach ($key in @($ExcludedIdentityKeys)) { $excluded[[string]$key] = $true }
  @(
    Get-VerifiedCodexMainProcesses -PackageInfo $PackageInfo | Where-Object {
      $identity = $_.Identity
      $started = [DateTime]::Parse([string]$identity.StartTimeUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
      -not $excluded.ContainsKey((Get-CodexProcessIdentityKey -Identity $identity)) -and
        $started -ge $StartedAtUtc -and
        (Test-CodexDebugIdentityForPort -Identity $identity -Port $Port)
    }
  )
}
```

- [ ] **Step 2: Return a launch context instead of assuming the launcher PID is final**

`Start-CodexWithCdp` must fail if a verified main process still exists at its entry, record the baseline identity keys and UTC timestamp, start the exact package executable with the two existing loopback arguments, and return a context with mutable `OriginalIdentity` and `Identity` fields. It must not kill an unverified process or throw merely because the returned launcher handle exits.

- [ ] **Step 3: Rediscover a unique current identity while waiting for CDP**

Change `Wait-VerifiedCdpEndpoint` to accept `-LaunchContext`. On every bounded poll it rereads the returned handle when possible, enumerates transaction candidates, fails closed on more than one candidate, updates `LaunchContext.Identity` only after a fresh start-time/command-line/package/argument check, and returns true only after the existing port listener and renderer endpoint verification succeeds.

- [ ] **Step 4: Use the launch context for rollback cleanup**

Set `$launchedWithCdp` immediately after the executable was started. On failure, stop only distinct identities captured as the original returned process or an eligible transaction candidate, using `Stop-TransactionCodex` and the existing verified process handle routine. If any identity cannot be confirmed stopped, or another verified main remains, preserve the config snapshot and do not relaunch normal Codex.

- [ ] **Step 5: Run the launch tests**

Run: `node --test --test-name-pattern="launcher handoff|transaction-created Codex|Windows start requires" tests/windows-runtime.test.mjs tests/windows-lifecycle.test.mjs`

Expected: PASS; no test accepts an arbitrary `ChatGPT.exe`, public listener, old process, or wrong arguments.

### Task 4: Implement PowerShell 5.1-safe snapshot replacement

**Files:**
- Modify: `scripts/start-dream-skin-windows.ps1`
- Test: `tests/windows-runtime.test.mjs`
- Test: `tests/windows-lifecycle.test.mjs`

- [ ] **Step 1: Classify only bounded transient Windows replace errors**

Add `Test-CodexWindowsTransientReplaceError`. It unwraps the base exception and returns true only for `UnauthorizedAccessException` or `IOException` whose low Win32 code is access denied (5), sharing violation (32), or lock violation (33).

- [ ] **Step 2: Give `File.Replace` a real same-directory backup path**

In `Restore-ConfigSnapshot`, copy and hash-check the snapshot into a unique same-directory replacement source. For up to eight attempts, recheck `ExpectedCurrentHash`, call `File.Replace(source, config, displacedBackup)`, retry only the classified transient errors with 25/50/100/200/400 ms bounded backoff, then verify the restored config equals `SnapshotHash` and the displaced backup equals `ExpectedCurrentHash`. Delete the displaced backup only after all checks pass; preserve it if verification or cleanup fails.

- [ ] **Step 3: Update the static safety assertion**

Change the lifecycle test from merely requiring any `File.Replace` call to requiring a non-null displaced backup variable and continued snapshot/current hash checks.

- [ ] **Step 4: Run rollback tests**

Run: `node --test --test-name-pattern="failed Start restores|transient.*snapshot|Windows start requires" tests/windows-runtime.test.mjs tests/windows-lifecycle.test.mjs`

Expected: PASS on Windows PowerShell 5.1 for ASCII, spaces, and Unicode; CAS mismatch and non-transient failures leave recovery material and do not overwrite the target.

### Task 5: Verify, document, and deliver

**Files:**
- Modify: `docs/windows/README.md`
- Modify: `docs/windows/适配报告.md`
- Modify: `CHANGELOG.md`
- Create outside repository: `%USERPROFILE%\Desktop\Windows10-启动失败修复与真机复测报告.md`

- [ ] **Step 1: Run targeted and full automated verification**

Run all of the following and record exit codes plus test counts:

```powershell
node --test tests/windows-runtime.test.mjs tests/windows-lifecycle.test.mjs tests/windows-regressions.test.mjs
npm.cmd test
npm.cmd run doctor:windows
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File .\tests\run-tests-windows.ps1
git diff --check
```

Also parse every changed `.ps1` with the Windows PowerShell 5.1 AST parser and run `node --check` for every changed `.mjs`.

- [ ] **Step 2: Perform current-machine lifecycle verification from the installed copy**

Generate a neutral local gradient in a controlled temporary directory, run Install `--no-launch`, Customize, Start, Verify `--reload`, Restore, then repeat Start → Verify → Restore. Record only redacted structured evidence. Confirm final doctor reports `statePresent=false`, `cdpVerified=false`, and `live=false`, ordinary Codex has no remote-debugging arguments, and the exact controlled temporary directory is removed.

- [ ] **Step 3: Preserve the environment conclusion boundary**

This machine is Windows 11 Build 26200 with Store Codex `26.715.3651.0`; therefore its lifecycle can validate only that exact combination. Keep Windows 10 and Codex `26.715.4045.0` explicitly unverified and provide a precise audience retest unless that exact environment becomes available.

- [ ] **Step 4: Review public changes for security and privacy**

Confirm `LICENSE`, `NOTICE.md`, the README non-official/upstream/creative-reference notices, package checks, loopback checks, listener ownership, and CAS behavior are unchanged. Scan the diff for user-profile paths, tokens, secrets, screenshots, feedback text, and private images.

- [ ] **Step 5: Commit and ordinarily push only `windows-support`**

```powershell
git add scripts/start-dream-skin-windows.ps1 tests/windows-runtime.test.mjs tests/windows-lifecycle.test.mjs docs/windows/README.md docs/windows/适配报告.md CHANGELOG.md docs/superpowers/plans/2026-07-19-windows-startup-rollback-fix.md
git commit -m "fix: recover Windows Codex launch handoffs"
git push origin windows-support
```

Do not merge `main`, force-push, tag, publish a release, or modify the audience feedback system.
