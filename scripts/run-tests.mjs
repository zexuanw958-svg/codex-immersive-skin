import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const windows = process.platform === "win32";
const runner = windows
  ? path.join(root, "tests", "run-tests-windows.ps1")
  : path.join(root, "tests", "run-tests.sh");
const command = windows && process.env.SystemRoot
  ? path.join(process.env.SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
  : windows ? "powershell.exe" : "/bin/bash";
const arguments_ = windows
  ? [
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "RemoteSigned",
      "-File",
      runner,
    ]
  : [runner];
const environment = { ...process.env };

// The Windows runner replaces this bootstrap executable with Codex's verified
// bundled runtime as soon as common-windows.ps1 is available.
if (windows) environment.CODEX_IMMERSIVE_TEST_BOOTSTRAP_NODE = process.execPath;

const result = spawnSync(command, arguments_, {
  cwd: root,
  env: environment,
  stdio: "inherit",
  windowsHide: true,
});

if (result.error) {
  console.error(`Could not start the ${windows ? "Windows" : "macOS"} test runner: ${result.error.message}`);
  process.exitCode = 1;
} else if (result.signal) {
  console.error(`The test runner was terminated by ${result.signal}.`);
  process.exitCode = 1;
} else {
  process.exitCode = result.status ?? 1;
}
