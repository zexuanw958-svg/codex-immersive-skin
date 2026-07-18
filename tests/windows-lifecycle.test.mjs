import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

async function script(name) {
  return fs.readFile(path.join(root, "scripts", name), "utf8");
}

test("Windows installer is transactional and creates owned shortcuts in the known Desktop folder", async () => {
  const source = await script("install-dream-skin-windows.ps1");
  assert.match(source, /\.installing\./i);
  assert.match(source, /\.previous\./i);
  assert.match(source, /try\s*\{/i);
  assert.match(source, /catch\s*\{/i);
  assert.match(source, /GetFolderPath\(['"]DesktopDirectory['"]\)/i);
  assert.match(source, /WScript\.Shell/i);
  assert.match(source, /CreateShortcut/i);
  assert.match(source, /CodexImmersiveSkin launcher/i);
  assert.match(source, /launcherTouched/i);
  assert.match(source, /launcherWrittenHashes/i);
  assert.match(source, /\$expectedTail\s*=\s*@\(\s*if\s*\(/i,
    "PowerShell 5.1 must keep an empty shortcut argument tail as an array during reinstall validation");
  assert.match(source, /start-dream-skin-windows\.ps1/i);
  assert.doesNotMatch(source, /theme-config\.mjs.+install/is, "config changes are deferred to the authorized Start transaction");
  assert.doesNotMatch(source, /Copy-Item[^\r\n]*ConfigPath[^\r\n]*rollback/i,
    "no-launch installation must not snapshot and later overwrite config");
  assert.doesNotMatch(source, /Set-ExecutionPolicy|Stop-Process\s+-Name|taskkill|app\.asar/i);
});

test("Windows start requires restart authorization and binds CDP to loopback", async () => {
  const source = await script("start-dream-skin-windows.ps1");
  assert.match(source, /--restart-existing/i);
  assert.match(source, /--prompt-restart/i);
  assert.match(source, /remote-debugging-address=127\.0\.0\.1/i);
  assert.match(source, /remote-debugging-port/i);
  assert.match(source, /Test-VerifiedCdpEndpoint/i);
  assert.match(source, /Start-InjectorDaemon/i);
  assert.match(source, /Write-ImmersiveState/i);
  assert.match(source, /Resolve-CodexWindowsRecordedInjectorPath/i);
  assert.match(source, /Stop-TransactionCodex/i);
  assert.match(source, /Restore-ConfigSnapshot/i);
  assert.match(source, /\[IO\.File\]::Replace/i);
  assert.match(source, /Write-EmergencyInjectorState/i);
  const rollbackStart = source.lastIndexOf("$originalError = $_");
  assert.ok(rollbackStart >= 0, "missing outer Start rollback");
  const rollback = source.slice(rollbackStart);
  assert.doesNotMatch(rollback, /Stop-VerifiedCodex\s+-PackageInfo/i,
    "rollback must not scan and stop unrelated Codex processes");
  assert.match(source, /--verify/i);
  assert.doesNotMatch(source, /0\.0\.0\.0|Stop-Process\s+-Name|taskkill|app\.asar/i);
});

test("Windows verify checks endpoint identity before invoking the shared injector", async () => {
  const source = await script("verify-dream-skin-windows.ps1");
  const endpointCheck = source.search(/Test-VerifiedCdpEndpoint/i);
  const injectorCall = source.indexOf("'--verify'", endpointCheck);
  assert.ok(endpointCheck >= 0, "missing verified endpoint check");
  assert.ok(injectorCall > endpointCheck, "injector verification must follow endpoint identity checking");
  assert.match(source, /--reload/i);
  assert.match(source, /--screenshot/i);
});

test("Windows restore verifies the recorded injector before removal and configuration restore", async () => {
  const source = await script("restore-dream-skin-windows.ps1");
  const stop = source.search(/Stop-RecordedInjector/i);
  const remove = source.search(/--remove/i);
  const config = source.search(/theme-config\.mjs.+restore/is);
  assert.ok(stop >= 0, "missing recorded injector identity check");
  assert.ok(remove > stop, "live DOM removal must follow injector identity checking");
  assert.ok(config > stop, "configuration restore must follow injector identity checking");
  assert.match(source, /Start-CodexNormally/i);
  assert.match(source, /--validate-only/i);
  assert.match(source, /--keep-backup/i);
  assert.match(source, /Open-CodexWindowsOperationLock/i);
  assert.match(source, /Resolve-CodexWindowsRecordedInjectorPath/i);
  assert.match(source, /Test-CodexWindowsOwnedInstallRoot/i);
  assert.doesNotMatch(source, /Stop-Process\s+-Name|taskkill|app\.asar/i);
});

test("Windows customizer keeps image processing local and preserves partial overrides", async () => {
  const source = await script("customize-theme-windows.ps1");
  assert.match(source, /OpenFileDialog/i);
  assert.match(source, /52428800/);
  assert.match(source, /16777216/);
  assert.match(source, /normalize-image-windows\.ps1/i);
  assert.match(source, /analyze-image\.mjs/i);
  assert.match(source, /write-theme\.mjs/i);
  for (const option of ["image", "name", "accent", "secondary", "highlight", "appearance", "no-apply", "reset-demo"]) {
    assert.match(source, new RegExp(`--${option.replace("-", "\\-")}`, "i"));
  }
  assert.doesNotMatch(source, /Invoke-WebRequest|curl|Start-BitsTransfer|app\.asar/i);
});
