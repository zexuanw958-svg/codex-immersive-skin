import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const [mode, ...args] = process.argv.slice(2);

function valueFor(name, fallback = "") {
  const index = args.indexOf(`--${name}`);
  if (index < 0) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`Missing value for --${name}`);
  return value;
}

function validateHex(value, name) {
  if (!/^#[0-9a-f]{6}$/i.test(value)) throw new Error(`${name} must be a six-digit hex color.`);
  return value.toLowerCase();
}

function hexToRgba(hex, alpha) {
  const value = Number.parseInt(hex.slice(1), 16);
  return `rgba(${value >> 16}, ${(value >> 8) & 255}, ${value & 255}, ${alpha})`;
}

async function atomicWrite(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.tmp`;
  try {
    await fs.writeFile(temporary, value, { mode: 0o600 });
    await fs.rename(temporary, file);
    await fs.chmod(file, 0o600);
  } finally {
    await fs.rm(temporary, { force: true }).catch(() => {});
  }
}

const outputDir = path.resolve(valueFor("output-dir", path.join(root, "assets")));
const themePath = path.join(outputDir, "theme.json");
const identityPath = path.join(outputDir, ".codex-immersive-theme.json");
const themeIdentity = {
  schemaVersion: 1,
  product: "Codex Immersive Skin theme",
};

async function canonicalPath(file) {
  try {
    return await fs.realpath(file);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    return path.resolve(file);
  }
}

function pathIdentity(file) {
  const normalized = path.normalize(file);
  return process.platform === "win32" ? normalized.toLowerCase() : normalized;
}

function pathWithin(file, boundary) {
  const relative = path.relative(boundary, file);
  return relative !== "" && relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

async function isAllowedResetDirectory(resolvedOutput) {
  const expected = process.platform === "win32"
    ? process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, "CodexImmersiveSkin", "theme")
    : process.platform === "darwin"
      ? path.join(os.homedir(), "Library", "Application Support", "CodexImmersiveSkin", "theme")
      : "";
  if (expected && pathIdentity(outputDir) === pathIdentity(path.resolve(expected))) {
    return pathIdentity(resolvedOutput) === pathIdentity(path.resolve(expected)) ? "production" : "";
  }

  if (process.env.CODEX_IMMERSIVE_TEST_MODE !== "1" || !process.env.CODEX_IMMERSIVE_TEST_ROOT) return "";
  const [resolvedTestRoot, resolvedTemporaryRoot] = await Promise.all([
    canonicalPath(process.env.CODEX_IMMERSIVE_TEST_ROOT),
    canonicalPath(os.tmpdir()),
  ]);
  const testLeaf = path.basename(path.resolve(process.env.CODEX_IMMERSIVE_TEST_ROOT));
  return testLeaf.startsWith("codex-immersive-") &&
    pathWithin(resolvedTestRoot, resolvedTemporaryRoot) &&
    path.basename(outputDir) === "theme" &&
    pathWithin(resolvedOutput, resolvedTestRoot) ? "test" : "";
}

if (mode === "reset-demo") {
  const [resolvedOutput, resolvedAssets] = await Promise.all([
    canonicalPath(outputDir),
    canonicalPath(path.join(root, "assets")),
  ]);
  if (pathIdentity(resolvedOutput) === pathIdentity(resolvedAssets)) {
    throw new Error("Refusing to delete the bundled demo assets; pass a user --output-dir.");
  }
  const resetScope = await isAllowedResetDirectory(resolvedOutput);
  if (!resetScope) {
    throw new Error("Refusing to delete a directory outside the managed theme location.");
  }
  let identity = null;
  let theme;
  try {
    theme = JSON.parse(await fs.readFile(themePath, "utf8"));
    identity = await fs.readFile(identityPath, "utf8").then(JSON.parse).catch((error) => {
      if (error.code === "ENOENT" && resetScope === "production") return null;
      throw error;
    });
  } catch {
    throw new Error("Refusing to delete a theme directory without valid ownership metadata.");
  }
  if ((identity && (identity.schemaVersion !== themeIdentity.schemaVersion ||
      identity.product !== themeIdentity.product)) ||
      (!identity && resetScope !== "production") ||
      theme?.schemaVersion !== 1 || theme?.brandSubtitle !== "CODEX IMMERSIVE SKIN") {
    throw new Error("Refusing to delete a theme directory with mismatched ownership metadata.");
  }
  await fs.rm(outputDir, { recursive: true, force: true });
  console.log("Restored the bundled neutral demo preset.");
  process.exit(0);
}

if (mode !== "custom") {
  throw new Error("Usage: write-theme.mjs custom [options] | reset-demo --output-dir <dir>");
}

const image = path.basename(valueFor("image", "background.jpg"));
if (!/\.(?:png|jpe?g|webp)$/i.test(image)) throw new Error("image must be a PNG, JPEG, or WebP filename.");
const imagePath = path.join(outputDir, image);
const imageStat = await fs.stat(imagePath);
if (!imageStat.isFile() || imageStat.size < 1 || imageStat.size > 16 * 1024 * 1024) {
  throw new Error("The prepared theme image must be non-empty and no larger than 16 MB.");
}

const name = valueFor("name", "我的 Codex 主题").trim().slice(0, 80);
const tagline = valueFor("tagline", "把喜欢的画面变成可交互的 Codex 工作台。").trim().slice(0, 160);
const quote = valueFor("quote", "MAKE SOMETHING WONDERFUL").trim().slice(0, 80);
const appearance = valueFor("appearance", "dark").trim().toLowerCase();
if (!["light", "dark"].includes(appearance)) {
  throw new Error("appearance must be light or dark.");
}
const accent = validateHex(valueFor("accent", "#7cff46"), "accent");
const secondary = validateHex(valueFor("secondary", "#36d7e8"), "secondary");
const highlight = validateHex(valueFor("highlight", "#642a8c"), "highlight");
const base = appearance === "light" ? {
  background: "#e7f0f1",
  panel: "#f8fbfb",
  panelAlt: "#edf4f4",
  text: "#17343a",
  muted: "#597176",
} : {
  background: "#071116",
  panel: "#0b1a20",
  panelAlt: "#10272c",
  text: "#f2fff7",
  muted: "#a7c2ba",
};

const custom = {
  schemaVersion: 1,
  id: `custom-${Date.now()}`,
  name: name || "我的 Codex 主题",
  appearance,
  brandSubtitle: "CODEX IMMERSIVE SKIN",
  tagline: tagline || "把喜欢的画面变成可交互的 Codex 工作台。",
  projectPrefix: "选择项目 · ",
  projectLabel: "◉  选择项目",
  statusText: "IMMERSIVE MODE",
  quote: quote || "MAKE SOMETHING WONDERFUL",
  image,
  colors: {
    ...base,
    accent,
    accentAlt: accent,
    secondary,
    highlight,
    line: hexToRgba(accent, 0.32),
  },
};

await atomicWrite(themePath, `${JSON.stringify(custom, null, 2)}\n`);
await atomicWrite(identityPath, `${JSON.stringify(themeIdentity, null, 2)}\n`);
console.log(`Saved custom theme “${custom.name}”.`);
