import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  DEFAULT_STYLE,
  SURFACES,
  contrastRatio,
  parseBmp,
  resolveStyleFromPixels,
} from "../scripts/analyze-image.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const analyzer = path.join(root, "scripts", "analyze-image.mjs");
const analyzerUrl = pathToFileURL(analyzer).href;

function solidPixels(hex, count = 64) {
  const red = Number.parseInt(hex.slice(1, 3), 16);
  const green = Number.parseInt(hex.slice(3, 5), 16);
  const blue = Number.parseInt(hex.slice(5, 7), 16);
  return Array.from({ length: count }, () => ({ red, green, blue, alpha: 255 }));
}

function runAnalyzer(arguments_) {
  return spawnSync(process.execPath, [analyzer, ...arguments_], { encoding: "utf8" });
}

function warningCount(stderr) {
  return stderr.split("无法从图片自动取色，已使用默认配色。").length - 1;
}

function create24BitBmp(rows) {
  const height = rows.length;
  const width = rows[0].length;
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
  buffer.writeUInt32LE(0, 30);
  buffer.writeUInt32LE(rowStride * height, 34);

  for (let fileRow = 0; fileRow < height; fileRow += 1) {
    const sourceRow = rows[height - 1 - fileRow];
    for (let column = 0; column < width; column += 1) {
      const offset = pixelOffset + fileRow * rowStride + column * 3;
      const { red, green, blue } = sourceRow[column];
      buffer[offset] = blue;
      buffer[offset + 1] = green;
      buffer[offset + 2] = red;
    }
  }
  return buffer;
}

function create32BitBmp(rows, {
  compression = 0,
  masks = {},
  topDown = false,
} = {}) {
  const height = rows.length;
  const width = rows[0].length;
  const dibSize = 124;
  const pixelOffset = 14 + dibSize;
  const rowStride = width * 4;
  const buffer = Buffer.alloc(pixelOffset + rowStride * height);
  buffer.write("BM", 0, "ascii");
  buffer.writeUInt32LE(buffer.length, 2);
  buffer.writeUInt32LE(pixelOffset, 10);
  buffer.writeUInt32LE(dibSize, 14);
  buffer.writeInt32LE(width, 18);
  buffer.writeInt32LE(topDown ? -height : height, 22);
  buffer.writeUInt16LE(1, 26);
  buffer.writeUInt16LE(32, 28);
  buffer.writeUInt32LE(compression, 30);
  buffer.writeUInt32LE(rowStride * height, 34);
  buffer.writeUInt32LE(masks.red ?? 0, 54);
  buffer.writeUInt32LE(masks.green ?? 0, 58);
  buffer.writeUInt32LE(masks.blue ?? 0, 62);
  buffer.writeUInt32LE(masks.alpha ?? 0, 66);

  for (let fileRow = 0; fileRow < height; fileRow += 1) {
    const sourceRow = rows[topDown ? fileRow : height - 1 - fileRow];
    for (let column = 0; column < width; column += 1) {
      const offset = pixelOffset + fileRow * rowStride + column * 4;
      const { red, green, blue, alpha = 0 } = sourceRow[column];
      buffer[offset] = blue;
      buffer[offset + 1] = green;
      buffer[offset + 2] = red;
      buffer[offset + 3] = alpha;
    }
  }
  return buffer;
}

function rgbDistance(firstHex, secondHex) {
  const channels = (hex) => [
    Number.parseInt(hex.slice(1, 3), 16),
    Number.parseInt(hex.slice(3, 5), 16),
    Number.parseInt(hex.slice(5, 7), 16),
  ];
  const first = channels(firstHex);
  const second = channels(secondHex);
  return Math.hypot(...first.map((channel, index) => channel - second[index]));
}

function assertDistinctContrastingPalette(result) {
  const colors = [result.accent, result.secondary, result.highlight];
  for (let first = 0; first < colors.length; first += 1) {
    for (let second = first + 1; second < colors.length; second += 1) {
      assert.ok(
        rgbDistance(colors[first], colors[second]) >= 24,
        `${colors[first]} and ${colors[second]} must remain visibly distinct`,
      );
    }
  }
  for (const color of colors) {
    for (const surface of Object.values(SURFACES[result.appearance])) {
      assert.ok(contrastRatio(color, surface) >= 4.5, `${color} must contrast with ${surface}`);
    }
  }
}

test("a light image selects light appearance", () => {
  const result = resolveStyleFromPixels(solidPixels("#f2eee8"), {});
  assert.equal(result.appearance, "light");
  assert.equal(result.fallback, false);
});

test("a dark image selects dark appearance", () => {
  const result = resolveStyleFromPixels(solidPixels("#151b25"), {});
  assert.equal(result.appearance, "dark");
  assert.equal(result.fallback, false);
});

test("automatic colors meet contrast against every theme surface", () => {
  const pixels = [
    ...solidPixels("#d8a87c", 160),
    ...solidPixels("#6f8fa8", 96),
    ...solidPixels("#9a6f8f", 64),
  ];
  for (const appearance of ["light", "dark"]) {
    const result = resolveStyleFromPixels(pixels, { appearance });
    for (const name of ["accent", "secondary", "highlight"]) {
      for (const surface of Object.values(SURFACES[appearance])) {
        assert.ok(
          contrastRatio(result[name], surface) >= 4.5,
          `${result[name]} must contrast with ${surface} in ${appearance}`,
        );
      }
    }
  }
});

test("solid-image tonal palettes remain distinct after contrast enforcement", () => {
  for (const sample of [
    { name: "light", color: "#f5f5f5", explicit: {} },
    { name: "dark", color: "#101010", explicit: {} },
    { name: "chromatic", color: "#ff0000", explicit: { appearance: "dark" } },
    { name: "grayscale", color: "#808080", explicit: { appearance: "light" } },
  ]) {
    const result = resolveStyleFromPixels(solidPixels(sample.color), sample.explicit);
    assertDistinctContrastingPalette(result, sample.name);
  }
});

test("transparent pixels do not affect appearance detection", () => {
  const result = resolveStyleFromPixels([
    ...solidPixels("#ffffff", 200).map((pixel) => ({ ...pixel, alpha: 127 })),
    ...solidPixels("#101010", 8),
  ]);
  assert.equal(result.appearance, "dark");
});

test("explicit values win independently and normalize colors to lowercase", () => {
  const result = resolveStyleFromPixels(solidPixels("#f5f5f5"), {
    appearance: "dark",
    accent: "#AABBCC",
    secondary: "#445566",
    highlight: "#778899",
  });
  assert.deepEqual(result, {
    appearance: "dark",
    accent: "#aabbcc",
    secondary: "#445566",
    highlight: "#778899",
    fallback: false,
  });
});

test("partial overrides preserve supplied fields and derive the rest", () => {
  const result = resolveStyleFromPixels(solidPixels("#9d704f"), {
    accent: "#123456",
  });
  assert.equal(result.accent, "#123456");
  assert.notEqual(result.secondary, DEFAULT_STYLE.secondary);
  assert.match(result.highlight, /^#[0-9a-f]{6}$/);
});

test("each partial override wins independently while omitted fields stay image-derived", () => {
  const pixels = solidPixels("#9d704f");
  const baseline = resolveStyleFromPixels(pixels);
  const cases = [
    { explicit: { appearance: "light" }, supplied: "appearance", expected: "light" },
    { explicit: { accent: "#ABCDEF" }, supplied: "accent", expected: "#abcdef" },
    { explicit: { secondary: "#ABCDEF" }, supplied: "secondary", expected: "#abcdef" },
    { explicit: { highlight: "#ABCDEF" }, supplied: "highlight", expected: "#abcdef" },
  ];
  for (const { explicit, supplied, expected } of cases) {
    const result = resolveStyleFromPixels(pixels, explicit);
    assert.equal(result[supplied], expected);
    if (supplied !== "appearance") assert.equal(result.appearance, baseline.appearance);
    for (const name of ["accent", "secondary", "highlight"]) {
      if (name === supplied) continue;
      assert.notEqual(result[name], DEFAULT_STYLE[name], `${name} should come from image pixels`);
      if (supplied !== "appearance") assert.equal(result[name], baseline[name]);
      for (const surface of Object.values(SURFACES[result.appearance])) {
        assert.ok(contrastRatio(result[name], surface) >= 4.5);
      }
    }
  }
});

test("invalid explicit appearance and colors are rejected", () => {
  assert.throws(
    () => resolveStyleFromPixels(solidPixels("#ffffff"), { appearance: "system" }),
    /appearance/,
  );
  assert.throws(
    () => resolveStyleFromPixels(solidPixels("#ffffff"), { accent: "#abc" }),
    /accent/,
  );
});

test("the real CLI normalizes an SVG through sips and parses its 32-bit BMP", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-svg-"));
  try {
    const svg = path.join(directory, "light.svg");
    const bmp = path.join(directory, "sips.bmp");
    await fs.writeFile(svg, [
      '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="8">',
      '<rect width="12" height="8" fill="#f4f1ea"/>',
      "</svg>",
    ].join(""));

    const sips = spawnSync("/usr/bin/sips", [
      "-s", "format", "bmp", "-Z", "64", svg, "--out", bmp,
    ], { encoding: "utf8" });
    assert.equal(sips.status, 0, sips.stderr);
    const normalized = await fs.readFile(bmp);
    assert.equal(normalized.readUInt16LE(28), 32);
    assert.ok(normalized.readInt32LE(22) < 0, "sips BMP should exercise top-down row order");

    const result = runAnalyzer(["--image", svg, "--format", "json"]);
    assert.equal(result.status, 0, result.stderr);
    const style = JSON.parse(result.stdout);
    assert.equal(style.appearance, "light");
    assert.equal(style.fallback, false);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("the BMP parser handles padded bottom-up 24-bit input", async () => {
  const red = { red: 255, green: 0, blue: 0 };
  const green = { red: 0, green: 255, blue: 0 };
  const blue = { red: 0, green: 0, blue: 255 };
  const white = { red: 255, green: 255, blue: 255 };
  const pixels = parseBmp(create24BitBmp([
    [red, green, blue],
    [white, red, green],
  ]));
  assert.deepEqual(pixels, [
    { ...red, alpha: 255 },
    { ...green, alpha: 255 },
    { ...blue, alpha: 255 },
    { ...white, alpha: 255 },
    { ...red, alpha: 255 },
    { ...green, alpha: 255 },
  ]);
});

test("32-bit BI_RGB treats its reserved fourth byte as opaque", () => {
  const pixels = parseBmp(create32BitBmp([[
    { red: 12, green: 34, blue: 56, alpha: 0 },
  ]]));
  assert.deepEqual(pixels, [{ red: 12, green: 34, blue: 56, alpha: 255 }]);
});

test("top-down sips bitfields decode exact masks and alpha semantics", () => {
  const sipsMasks = {
    red: 0x00ff0000,
    green: 0x0000ff00,
    blue: 0x000000ff,
    alpha: 0xff000000,
  };
  const pixels = parseBmp(create32BitBmp([
    [
      { red: 12, green: 34, blue: 56, alpha: 0 },
      { red: 78, green: 90, blue: 123, alpha: 200 },
    ],
    [
      { red: 210, green: 180, blue: 150, alpha: 255 },
      { red: 1, green: 2, blue: 3, alpha: 128 },
    ],
  ], { compression: 3, masks: sipsMasks, topDown: true }));
  assert.deepEqual(pixels, [
    { red: 12, green: 34, blue: 56, alpha: 0 },
    { red: 78, green: 90, blue: 123, alpha: 200 },
    { red: 210, green: 180, blue: 150, alpha: 255 },
    { red: 1, green: 2, blue: 3, alpha: 128 },
  ]);
});

test("bitfields reject unsupported and overlapping mask layouts", () => {
  const pixel = [[{ red: 12, green: 34, blue: 56, alpha: 255 }]];
  assert.throws(() => parseBmp(create32BitBmp(pixel, {
    compression: 3,
    masks: {
      red: 0x000000ff,
      green: 0x0000ff00,
      blue: 0x00ff0000,
      alpha: 0xff000000,
    },
  })), /unsupported.*mask/i);
  assert.throws(() => parseBmp(create32BitBmp(pixel, {
    compression: 3,
    masks: {
      red: 0x00ff0000,
      green: 0x00ff0000,
      blue: 0x000000ff,
      alpha: 0xff000000,
    },
  })), /overlap/i);
});

test("missing and malformed images fall back once with a human warning", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-fallback-"));
  try {
    const malformed = path.join(directory, "malformed.img");
    await fs.writeFile(malformed, "not an image");
    for (const image of [path.join(directory, "missing.png"), malformed]) {
      const result = runAnalyzer(["--image", image, "--format", "json"]);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(warningCount(result.stderr), 1, result.stderr);
      assert.deepEqual(JSON.parse(result.stdout), { ...DEFAULT_STYLE, fallback: true });
    }
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("no visible pixels preserve partial overrides and warn exactly once", () => {
  const source = [
    `import { resolveStyleFromPixels } from ${JSON.stringify(analyzerUrl)};`,
    "const style = resolveStyleFromPixels([{ red: 255, green: 255, blue: 255, alpha: 0 }],",
    "  { appearance: 'light', accent: '#ABCDEF' });",
    "process.stdout.write(JSON.stringify(style));",
  ].join("\n");
  const result = spawnSync(process.execPath, ["--input-type=module", "--eval", source], {
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(warningCount(result.stderr), 1, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    appearance: "light",
    accent: "#abcdef",
    secondary: DEFAULT_STYLE.secondary,
    highlight: DEFAULT_STYLE.highlight,
    fallback: true,
  });
});

test("all explicit fields skip missing-image analysis", () => {
  const result = runAnalyzer([
    "--image", "/definitely/not/present.png",
    "--appearance", "light",
    "--accent", "#AABBCC",
    "--secondary", "#112233",
    "--highlight", "#445566",
    "--format", "json",
  ]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  assert.deepEqual(JSON.parse(result.stdout), {
    appearance: "light",
    accent: "#aabbcc",
    secondary: "#112233",
    highlight: "#445566",
    fallback: false,
  });
});

test("fallback keeps explicit fields and defaults only missing fields", () => {
  const result = runAnalyzer([
    "--image", "/definitely/not/present.png",
    "--appearance", "light",
    "--accent", "#ABCDEF",
    "--format", "json",
  ]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(warningCount(result.stderr), 1, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    appearance: "light",
    accent: "#abcdef",
    secondary: DEFAULT_STYLE.secondary,
    highlight: DEFAULT_STYLE.highlight,
    fallback: true,
  });
});

test("invalid CLI explicit values are hard errors", () => {
  for (const arguments_ of [
    ["--image", "unused", "--appearance", "system"],
    ["--image", "unused", "--accent", "#abc"],
  ]) {
    const result = runAnalyzer(arguments_);
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stderr, /已使用默认配色/);
  }
});

test("TSV output contains exactly four ordered fields", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-tsv-"));
  try {
    const svg = path.join(directory, "dark.svg");
    await fs.writeFile(svg, [
      '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">',
      '<rect width="4" height="4" fill="#101820"/>',
      "</svg>",
    ].join(""));
    const result = runAnalyzer(["--image", svg, "--format", "tsv"]);
    assert.equal(result.status, 0, result.stderr);
    const fields = result.stdout.trimEnd().split("\t");
    assert.equal(fields.length, 4);
    assert.deepEqual(fields, ["dark", ...fields.slice(1)]);
    fields.slice(1).forEach((field) => assert.match(field, /^#[0-9a-f]{6}$/));
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
