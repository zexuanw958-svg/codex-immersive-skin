import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { DEFAULT_STYLE } from "../scripts/analyze-image.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const analyzer = path.join(root, "scripts", "analyze-image.mjs");
const normalizer = path.join(root, "scripts", "normalize-image-windows.ps1");
const windowsOnly = { skip: process.platform !== "win32" };

function powershellPath() {
  const systemRoot = process.env.SystemRoot ?? process.env.WINDIR;
  assert.ok(systemRoot, "Windows must provide SystemRoot or WINDIR");
  return path.join(
    systemRoot,
    "System32",
    "WindowsPowerShell",
    "v1.0",
    "powershell.exe",
  );
}

function createSolid24BitBmp(width, height, { red, green, blue }) {
  const rowStride = Math.ceil((width * 3) / 4) * 4;
  const pixelOffset = 54;
  const buffer = Buffer.alloc(pixelOffset + rowStride * height);
  buffer.write("BM", 0, "ascii");
  buffer.writeUInt32LE(buffer.length, 2);
  buffer.writeUInt32LE(pixelOffset, 10);
  buffer.writeUInt32LE(40, 14);
  buffer.writeInt32LE(width, 18);
  buffer.writeInt32LE(height, 22);
  buffer.writeUInt16LE(1, 26);
  buffer.writeUInt16LE(24, 28);
  buffer.writeUInt32LE(rowStride * height, 34);
  for (let row = 0; row < height; row += 1) {
    const rowOffset = pixelOffset + row * rowStride;
    for (let column = 0; column < width; column += 1) {
      const offset = rowOffset + column * 3;
      buffer[offset] = blue;
      buffer[offset + 1] = green;
      buffer[offset + 2] = red;
    }
  }
  return buffer;
}

function runNormalizer(input, output, extraArguments = []) {
  return spawnSync(powershellPath(), [
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "RemoteSigned",
    "-File", normalizer,
    "-InputPath", input,
    "-OutputPath", output,
    "-MaxDimension", "64",
    ...extraArguments,
  ], { encoding: "utf8", windowsHide: true });
}

function runAnalyzer(image, extraArguments = []) {
  return spawnSync(process.execPath, [
    analyzer,
    "--image", image,
    ...extraArguments,
    "--format", "json",
  ], { encoding: "utf8", windowsHide: true });
}

test("Windows System.Drawing normalizer and analyzer CLI process a real BMP", windowsOnly, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-windows-image-"));
  try {
    const input = path.join(directory, "light source.bmp");
    const normalized = path.join(directory, "normalized output.bmp");
    await fs.writeFile(input, createSolid24BitBmp(128, 64, {
      red: 244,
      green: 241,
      blue: 234,
    }));

    const normalizedResult = runNormalizer(input, normalized);
    assert.equal(normalizedResult.status, 0, normalizedResult.stderr || normalizedResult.error?.message);
    const normalizedBmp = await fs.readFile(normalized);
    assert.equal(normalizedBmp.toString("ascii", 0, 2), "BM");
    assert.equal(normalizedBmp.readInt32LE(18), 64);
    assert.equal(Math.abs(normalizedBmp.readInt32LE(22)), 32);
    assert.ok([24, 32].includes(normalizedBmp.readUInt16LE(28)));

    const result = runAnalyzer(input);
    assert.equal(result.status, 0, result.stderr || result.error?.message);
    assert.equal(result.stderr, "");
    const style = JSON.parse(result.stdout);
    assert.equal(style.appearance, "light");
    assert.equal(style.fallback, false);
    for (const name of ["accent", "secondary", "highlight"]) {
      assert.match(style[name], /^#[0-9a-f]{6}$/);
    }
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("Windows normalizer prepares a JPEG without retaining a source-file lock", windowsOnly, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-windows-jpeg-"));
  try {
    const input = path.join(directory, "source.bmp");
    const output = path.join(directory, "prepared.jpg");
    await fs.writeFile(input, createSolid24BitBmp(80, 40, {
      red: 20,
      green: 80,
      blue: 140,
    }));

    const result = runNormalizer(input, output, ["-Format", "Jpeg", "-Quality", "84"]);
    assert.equal(result.status, 0, result.stderr || result.error?.message);
    const jpeg = await fs.readFile(output);
    assert.deepEqual([...jpeg.subarray(0, 2)], [0xff, 0xd8]);
    await fs.rm(input);
    await fs.rm(output);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("Windows analyzer CLI keeps per-field overrides and fallback semantics", windowsOnly, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-windows-overrides-"));
  try {
    const input = path.join(directory, "source.bmp");
    await fs.writeFile(input, createSolid24BitBmp(16, 8, {
      red: 157,
      green: 112,
      blue: 79,
    }));

    const baselineResult = runAnalyzer(input);
    assert.equal(baselineResult.status, 0, baselineResult.stderr || baselineResult.error?.message);
    const baseline = JSON.parse(baselineResult.stdout);
    assert.equal(baseline.fallback, false);

    for (const [flag, field] of [
      ["--accent", "accent"],
      ["--secondary", "secondary"],
      ["--highlight", "highlight"],
    ]) {
      const result = runAnalyzer(input, [flag, "#ABCDEF"]);
      assert.equal(result.status, 0, result.stderr || result.error?.message);
      const style = JSON.parse(result.stdout);
      assert.equal(style[field], "#abcdef");
      assert.equal(style.fallback, false);
      assert.equal(style.appearance, baseline.appearance);
      for (const other of ["accent", "secondary", "highlight"]) {
        if (other !== field) assert.equal(style[other], baseline[other]);
      }
    }

    const malformed = path.join(directory, "malformed.bmp");
    await fs.writeFile(malformed, "not a bitmap");
    const fallbackResult = runAnalyzer(malformed, ["--appearance", "light", "--accent", "#ABCDEF"]);
    assert.equal(fallbackResult.status, 0, fallbackResult.stderr || fallbackResult.error?.message);
    assert.equal(
      fallbackResult.stderr.split("无法从图片自动取色，已使用默认配色。").length - 1,
      1,
    );
    assert.deepEqual(JSON.parse(fallbackResult.stdout), {
      appearance: "light",
      accent: "#abcdef",
      secondary: DEFAULT_STYLE.secondary,
      highlight: DEFAULT_STYLE.highlight,
      fallback: true,
    });
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
