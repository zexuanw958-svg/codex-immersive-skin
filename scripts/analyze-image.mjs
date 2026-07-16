import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const execFile = promisify(execFileCallback);

export const DEFAULT_STYLE = Object.freeze({
  appearance: "dark",
  accent: "#7cff46",
  secondary: "#36d7e8",
  highlight: "#642a8c",
});

export const SURFACES = Object.freeze({
  light: Object.freeze({
    background: "#e7f0f1",
    panel: "#f8fbfb",
    panelAlt: "#edf4f4",
  }),
  dark: Object.freeze({
    background: "#071116",
    panel: "#0b1a20",
    panelAlt: "#10272c",
  }),
});

const COLOR_NAMES = ["accent", "secondary", "highlight"];
const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;
const FALLBACK_WARNING = "无法从图片自动取色，已使用默认配色。";
const FINAL_COLOR_DISTANCE = 24;
const SIPS_MASKS = Object.freeze({
  red: 0x00ff0000,
  green: 0x0000ff00,
  blue: 0x000000ff,
  alpha: 0xff000000,
});

function normalizeExplicit(explicit) {
  const normalized = {};
  if (explicit.appearance !== undefined) {
    if (explicit.appearance !== "light" && explicit.appearance !== "dark") {
      throw new TypeError("appearance must be light or dark");
    }
    normalized.appearance = explicit.appearance;
  }
  for (const name of COLOR_NAMES) {
    if (explicit[name] === undefined) continue;
    if (typeof explicit[name] !== "string" || !HEX_COLOR.test(explicit[name])) {
      throw new TypeError(`${name} must be a six-digit hex color`);
    }
    normalized[name] = explicit[name].toLowerCase();
  }
  return normalized;
}

function hasCompleteExplicitStyle(explicit) {
  return explicit.appearance !== undefined
    && COLOR_NAMES.every((name) => explicit[name] !== undefined);
}

function fallbackStyle(explicit) {
  process.stderr.write(`${FALLBACK_WARNING}\n`);
  return { ...DEFAULT_STYLE, ...explicit, fallback: true };
}

function hexToRgb(hex) {
  return {
    red: Number.parseInt(hex.slice(1, 3), 16),
    green: Number.parseInt(hex.slice(3, 5), 16),
    blue: Number.parseInt(hex.slice(5, 7), 16),
  };
}

function channelLuminance(channel) {
  const value = channel / 255;
  return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}

function relativeLuminance({ red, green, blue }) {
  return 0.2126 * channelLuminance(red)
    + 0.7152 * channelLuminance(green)
    + 0.0722 * channelLuminance(blue);
}

export function contrastRatio(firstHex, secondHex) {
  const first = relativeLuminance(hexToRgb(firstHex));
  const second = relativeLuminance(hexToRgb(secondHex));
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

function rgbToHsl({ red, green, blue }) {
  const r = red / 255;
  const g = green / 255;
  const b = blue / 255;
  const maximum = Math.max(r, g, b);
  const minimum = Math.min(r, g, b);
  const delta = maximum - minimum;
  const lightness = (maximum + minimum) / 2;
  let hue = 0;
  let saturation = 0;

  if (delta !== 0) {
    saturation = delta / (1 - Math.abs(2 * lightness - 1));
    if (maximum === r) hue = 60 * (((g - b) / delta) % 6);
    else if (maximum === g) hue = 60 * ((b - r) / delta + 2);
    else hue = 60 * ((r - g) / delta + 4);
  }
  if (hue < 0) hue += 360;
  return { hue, saturation, lightness };
}

function hslToRgb({ hue, saturation, lightness }) {
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const segment = hue / 60;
  const secondary = chroma * (1 - Math.abs((segment % 2) - 1));
  let channels;
  if (segment < 1) channels = [chroma, secondary, 0];
  else if (segment < 2) channels = [secondary, chroma, 0];
  else if (segment < 3) channels = [0, chroma, secondary];
  else if (segment < 4) channels = [0, secondary, chroma];
  else if (segment < 5) channels = [secondary, 0, chroma];
  else channels = [chroma, 0, secondary];
  const match = lightness - chroma / 2;
  return {
    red: Math.round((channels[0] + match) * 255),
    green: Math.round((channels[1] + match) * 255),
    blue: Math.round((channels[2] + match) * 255),
  };
}

function rgbToHex({ red, green, blue }) {
  return `#${[red, green, blue]
    .map((channel) => Math.max(0, Math.min(255, Math.round(channel))).toString(16).padStart(2, "0"))
    .join("")}`;
}

function distance(first, second) {
  return Math.hypot(
    first.red - second.red,
    first.green - second.green,
    first.blue - second.blue,
  );
}

function paletteCandidates(pixels) {
  const buckets = new Map();
  for (const pixel of pixels) {
    if ((pixel.alpha ?? 255) < 128) continue;
    const key = [pixel.red, pixel.green, pixel.blue]
      .map((channel) => Math.min(15, Math.floor(channel / 16)))
      .join(":");
    const bucket = buckets.get(key) ?? {
      key,
      count: 0,
      redSum: 0,
      greenSum: 0,
      blueSum: 0,
      luminanceSum: 0,
    };
    bucket.count += 1;
    bucket.redSum += pixel.red;
    bucket.greenSum += pixel.green;
    bucket.blueSum += pixel.blue;
    bucket.luminanceSum += relativeLuminance(pixel);
    buckets.set(key, bucket);
  }

  const ranked = [...buckets.values()].map((bucket) => {
    const color = {
      red: bucket.redSum / bucket.count,
      green: bucket.greenSum / bucket.count,
      blue: bucket.blueSum / bucket.count,
    };
    const { saturation } = rgbToHsl(color);
    return {
      ...bucket,
      ...color,
      saturation,
      luminance: bucket.luminanceSum / bucket.count,
      score: bucket.count * (0.35 + 0.65 * saturation),
    };
  }).sort((first, second) => (
    second.score - first.score
    || second.count - first.count
    || second.saturation - first.saturation
    || first.key.localeCompare(second.key)
  ));

  const selected = [];
  for (const candidate of ranked) {
    if (selected.every((chosen) => distance(candidate, chosen) >= 48)) {
      selected.push(candidate);
      if (selected.length === 3) break;
    }
  }
  return { ranked, selected };
}

function hasRequiredContrast(hex, appearance) {
  return Object.values(SURFACES[appearance])
    .every((surface) => contrastRatio(hex, surface) >= 4.5);
}

function ensureContrast(color, appearance) {
  const originalHex = rgbToHex(color);
  if (hasRequiredContrast(originalHex, appearance)) return originalHex;

  const hsl = rgbToHsl(color);
  let lower;
  let upper;
  let best;
  if (appearance === "light") {
    lower = 0;
    upper = hsl.lightness;
    best = rgbToHex(hslToRgb({ ...hsl, lightness: lower }));
    for (let iteration = 0; iteration < 32; iteration += 1) {
      const midpoint = (lower + upper) / 2;
      const candidate = rgbToHex(hslToRgb({ ...hsl, lightness: midpoint }));
      if (hasRequiredContrast(candidate, appearance)) {
        best = candidate;
        lower = midpoint;
      } else {
        upper = midpoint;
      }
    }
  } else {
    lower = hsl.lightness;
    upper = 1;
    best = rgbToHex(hslToRgb({ ...hsl, lightness: upper }));
    for (let iteration = 0; iteration < 32; iteration += 1) {
      const midpoint = (lower + upper) / 2;
      const candidate = rgbToHex(hslToRgb({ ...hsl, lightness: midpoint }));
      if (hasRequiredContrast(candidate, appearance)) {
        best = candidate;
        upper = midpoint;
      } else {
        lower = midpoint;
      }
    }
  }
  return best;
}

function automaticPalette(selected, best, appearance) {
  const result = [];
  const addIfUsable = (hex) => {
    const color = hexToRgb(hex);
    if (hasRequiredContrast(hex, appearance)
      && result.every((chosen) => distance(color, hexToRgb(chosen)) >= FINAL_COLOR_DISTANCE)) {
      result.push(hex);
    }
  };

  addIfUsable(ensureContrast(best, appearance));
  for (const candidate of selected.slice(1)) {
    addIfUsable(ensureContrast(candidate, appearance));
  }
  if (result.length === 3) return result;

  const base = rgbToHsl(hexToRgb(result[0]));
  const safeDirection = appearance === "light" ? -1 : 1;
  const addAlongDirection = (direction) => {
    const available = direction < 0 ? base.lightness : 1 - base.lightness;
    for (let step = 1; step <= 512 && result.length < 3; step += 1) {
      const lightness = base.lightness + direction * available * step / 512;
      addIfUsable(rgbToHex(hslToRgb({ ...base, lightness })));
    }
  };

  addAlongDirection(safeDirection);
  if (result.length < 3) addAlongDirection(-safeDirection);
  return result;
}

export function resolveStyleFromPixels(pixels, explicit = {}) {
  const normalized = normalizeExplicit(explicit);
  if (hasCompleteExplicitStyle(normalized)) {
    return { ...normalized, fallback: false };
  }
  const visible = pixels.filter((pixel) => (pixel.alpha ?? 255) >= 128);
  if (visible.length === 0) {
    return fallbackStyle(normalized);
  }

  const meanLuminance = visible.reduce(
    (sum, pixel) => sum + relativeLuminance(pixel),
    0,
  ) / visible.length;
  const appearance = normalized.appearance ?? (meanLuminance >= 0.45 ? "light" : "dark");
  const { ranked, selected } = paletteCandidates(visible);
  const palette = automaticPalette(selected, ranked[0], appearance);
  const result = { appearance, fallback: false };
  COLOR_NAMES.forEach((name, index) => {
    result[name] = normalized[name] ?? palette[index];
  });
  return result;
}

export function parseBmp(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 54) {
    throw new Error("invalid BMP: header is truncated");
  }
  if (buffer.toString("ascii", 0, 2) !== "BM") {
    throw new Error("invalid BMP: signature is missing");
  }

  const pixelOffset = buffer.readUInt32LE(10);
  const dibSize = buffer.readUInt32LE(14);
  if (dibSize < 40 || 14 + dibSize > buffer.length) {
    throw new Error("invalid BMP: unsupported DIB header");
  }

  const width = buffer.readInt32LE(18);
  const signedHeight = buffer.readInt32LE(22);
  const height = Math.abs(signedHeight);
  const planes = buffer.readUInt16LE(26);
  const bitsPerPixel = buffer.readUInt16LE(28);
  const compression = buffer.readUInt32LE(30);
  if (width <= 0 || signedHeight === 0 || planes !== 1) {
    throw new Error("invalid BMP: dimensions or planes are invalid");
  }
  if (bitsPerPixel !== 24 && bitsPerPixel !== 32) {
    throw new Error("invalid BMP: only 24-bit and 32-bit pixels are supported");
  }
  if ((bitsPerPixel === 24 && compression !== 0)
    || (bitsPerPixel === 32 && compression !== 0 && compression !== 3)) {
    throw new Error("invalid BMP: unsupported compression");
  }
  if (pixelOffset < 14 + dibSize || pixelOffset > buffer.length) {
    throw new Error("invalid BMP: pixel offset is out of bounds");
  }

  let bitfieldsHaveAlpha = false;
  if (bitsPerPixel === 32 && compression === 3) {
    const maskOffset = dibSize >= 52 ? 14 + 40 : 14 + dibSize;
    const masksEnd = maskOffset + 12;
    if (masksEnd > buffer.length || (dibSize < 52 && masksEnd > pixelOffset)) {
      throw new Error("invalid BMP: bitfield masks are truncated");
    }
    const masks = {
      red: buffer.readUInt32LE(maskOffset),
      green: buffer.readUInt32LE(maskOffset + 4),
      blue: buffer.readUInt32LE(maskOffset + 8),
      alpha: dibSize >= 56 ? buffer.readUInt32LE(maskOffset + 12) : 0,
    };
    const channels = [masks.red, masks.green, masks.blue, masks.alpha].filter(Boolean);
    for (let first = 0; first < channels.length; first += 1) {
      for (let second = first + 1; second < channels.length; second += 1) {
        if ((channels[first] & channels[second]) !== 0) {
          throw new Error("invalid BMP: bitfield masks overlap");
        }
      }
    }
    if (masks.red !== SIPS_MASKS.red
      || masks.green !== SIPS_MASKS.green
      || masks.blue !== SIPS_MASKS.blue
      || (masks.alpha !== 0 && masks.alpha !== SIPS_MASKS.alpha)) {
      throw new Error("invalid BMP: unsupported bitfield masks");
    }
    bitfieldsHaveAlpha = masks.alpha === SIPS_MASKS.alpha;
  }

  const bytesPerPixel = bitsPerPixel / 8;
  const rowStride = Math.ceil((width * bytesPerPixel) / 4) * 4;
  const pixelBytes = rowStride * height;
  if (!Number.isSafeInteger(rowStride)
    || !Number.isSafeInteger(pixelBytes)
    || pixelOffset + pixelBytes > buffer.length) {
    throw new Error("invalid BMP: pixel data is truncated");
  }

  const topDown = signedHeight < 0;
  const pixels = [];
  for (let row = 0; row < height; row += 1) {
    const fileRow = topDown ? row : height - 1 - row;
    const rowOffset = pixelOffset + fileRow * rowStride;
    for (let column = 0; column < width; column += 1) {
      const offset = rowOffset + column * bytesPerPixel;
      pixels.push({
        red: buffer[offset + 2],
        green: buffer[offset + 1],
        blue: buffer[offset],
        alpha: bitfieldsHaveAlpha ? buffer[offset + 3] : 255,
      });
    }
  }
  return pixels;
}

export async function resolveImageStyle(imagePath, explicit = {}) {
  const normalized = normalizeExplicit(explicit);
  if (hasCompleteExplicitStyle(normalized)) {
    return { ...normalized, fallback: false };
  }

  let temporaryDirectory;
  try {
    temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), "codex-dream-skin-palette-"));
    const normalizedBmp = path.join(temporaryDirectory, "normalized.bmp");
    await execFile("/usr/bin/sips", [
      "-s", "format", "bmp", "-Z", "64", imagePath, "--out", normalizedBmp,
    ], { encoding: "utf8" });
    const pixels = parseBmp(await fs.readFile(normalizedBmp));
    return resolveStyleFromPixels(pixels, normalized);
  } catch {
    return fallbackStyle(normalized);
  } finally {
    if (temporaryDirectory !== undefined) {
      await fs.rm(temporaryDirectory, { recursive: true, force: true });
    }
  }
}

function parseCli(arguments_) {
  const options = { explicit: {}, format: "json" };
  const valueOptions = new Set([
    "--image", "--appearance", "--accent", "--secondary", "--highlight", "--format",
  ]);
  for (let index = 0; index < arguments_.length; index += 1) {
    const flag = arguments_[index];
    if (!valueOptions.has(flag)) throw new Error(`unknown option: ${flag}`);
    const value = arguments_[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`missing value for ${flag}`);
    }
    index += 1;
    if (flag === "--image") options.image = value;
    else if (flag === "--format") options.format = value;
    else options.explicit[flag.slice(2)] = value;
  }
  if (options.image === undefined) throw new Error("--image is required");
  if (options.format !== "json" && options.format !== "tsv") {
    throw new Error("format must be json or tsv");
  }
  options.explicit = normalizeExplicit(options.explicit);
  return options;
}

async function runCli() {
  const options = parseCli(process.argv.slice(2));
  const style = await resolveImageStyle(options.image, options.explicit);
  if (options.format === "tsv") {
    process.stdout.write(`${style.appearance}\t${style.accent}\t${style.secondary}\t${style.highlight}\n`);
  } else {
    process.stdout.write(`${JSON.stringify(style)}\n`);
  }
}

const isMain = process.argv[1] !== undefined
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    await runCli();
  } catch (error) {
    process.stderr.write(`Error: ${error.message}\n`);
    process.exitCode = 1;
  }
}
