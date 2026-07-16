# Automatic Theme Colors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Derive readable theme colors and light/dark appearance locally from the selected image while preserving every explicit override and keeping the repository private.

**Architecture:** A dependency-free Node.js analyzer asks macOS sips for a 64-pixel BMP preview, parses its pixels, chooses deterministic dominant colors, and adjusts only automatic colors to WCAG 4.5:1. The existing customizer passes only explicit overrides to that analyzer and writes the resolved result through the unchanged theme writer.

**Tech Stack:** Bash 3.2, Node.js 22 standard library, macOS sips, node:test, Git, GitHub CLI

---

## File map

- Create scripts/analyze-image.mjs: BMP parsing, palette extraction, appearance detection, contrast enforcement, overrides, fallback, and CLI.
- Create tests/auto-palette.test.mjs: all automatic-color behavior.
- Modify scripts/customize-theme-macos.sh: stop pre-filling omitted options and consume analyzer output.
- Modify tests/run-tests.sh: execute all test files.
- Modify scripts/build-release.sh: package the analyzer and new test.
- Modify README.md: automatic-color copy and exact creator handle only.
- Modify NOTICE.md: remove the later clarification so final bytes match the clean baseline.
- Create outside the repository: viewer deployment prompt and upgrade receipt.
- Update the external progress source and delete the used task prompt only after success.

LICENSE, scripts/write-theme.mjs, theme assets, runtime CSS/injection code, and README attribution wording do not change.

### Task 1: Build the analyzer with TDD

**Files:**
- Create: tests/auto-palette.test.mjs
- Create: scripts/analyze-image.mjs
- Modify: tests/run-tests.sh

- [ ] **Step 1: Write failing tests for light, dark, and contrast**

The test imports this planned interface:

~~~~js
import {
  DEFAULT_STYLE,
  SURFACES,
  contrastRatio,
  resolveStyleFromPixels,
} from "../scripts/analyze-image.mjs";
~~~~

Use a solidPixels helper returning repeated RGBA objects. Add these exact behaviors:

~~~~js
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
        assert.ok(contrastRatio(result[name], surface) >= 4.5);
      }
    }
  }
});
~~~~

Change tests/run-tests.sh to:

~~~~bash
"$NODE" --test "$ROOT"/tests/*.test.mjs
~~~~

Run ./tests/run-tests.sh.

Expected: RED with ERR_MODULE_NOT_FOUND for scripts/analyze-image.mjs. A syntax/fixture error is not valid RED proof.

- [ ] **Step 2: Implement the minimal analyzer core**

The module exports these exact values and callable signatures:

- DEFAULT_STYLE is a frozen object containing dark, #7cff46, #36d7e8, and #642a8c.
- SURFACES is a frozen object containing the existing light surfaces (#e7f0f1, #f8fbfb, #edf4f4) and dark surfaces (#071116, #0b1a20, #10272c).
- contrastRatio(firstHex, secondHex) returns the WCAG ratio as a number.
- resolveStyleFromPixels(pixels, explicit = {}) returns the resolved style synchronously.
- resolveImageStyle(imagePath, explicit = {}) normalizes with sips and returns the resolved style asynchronously.

Implementation requirements:

- Validate explicit appearance as light/dark and colors as six-digit hex.
- Ignore pixels with alpha below 128.
- Mean WCAG luminance at least 0.45 selects light; lower selects dark.
- Quantize each RGB channel to 16 levels.
- Each bucket records count, RGB sums, saturation, and luminance.
- Rank by count times (0.35 plus 0.65 times saturation).
- Select three buckets with Euclidean RGB distance at least 48.
- If fewer exist, create deterministic lightness variants from the best image-derived candidate.
- Move automatic HSL lightness toward black for light themes or white for dark themes until worst contrast against all three surfaces is at least 4.5.
- Copy explicit values after automatic resolution so they remain exact.
- Valid pixels return fallback false.

Run ./tests/run-tests.sh.

Expected: the three new tests and nine existing tests pass.

- [ ] **Step 3: Write failing tests for overrides, BMP input, and fallback**

Add:

~~~~js
test("explicit values win independently", () => {
  const result = resolveStyleFromPixels(solidPixels("#f5f5f5"), {
    appearance: "dark",
    accent: "#112233",
    secondary: "#445566",
    highlight: "#778899",
  });
  assert.equal(result.appearance, "dark");
  assert.equal(result.accent, "#112233");
  assert.equal(result.secondary, "#445566");
  assert.equal(result.highlight, "#778899");
});

test("partial overrides preserve supplied fields and derive the rest", () => {
  const result = resolveStyleFromPixels(solidPixels("#9d704f"), {
    accent: "#123456",
  });
  assert.equal(result.accent, "#123456");
  assert.notEqual(result.secondary, DEFAULT_STYLE.secondary);
  assert.match(result.highlight, /^#[0-9a-f]{6}$/);
});
~~~~

Also:

- write a small light SVG under a temporary directory;
- invoke the analyzer CLI with process.execPath and JSON output;
- assert the CLI reads it through sips and detects light;
- invoke the CLI with a missing image;
- assert status 0, fallback true, existing defaults, and stderr matching 无法从图片自动取色，已使用默认配色.

Run only the new test and confirm the added cases fail for missing CLI/BMP/fallback behavior.

- [ ] **Step 4: Implement BMP normalization, CLI, and fallback**

CLI contract:

~~~~text
node scripts/analyze-image.mjs --image PATH
  [--appearance light|dark]
  [--accent #rrggbb]
  [--secondary #rrggbb]
  [--highlight #rrggbb]
  [--format json|tsv]
~~~~

Requirements:

- If all four fields are explicit, skip image analysis.
- Otherwise create a system temporary directory, run /usr/bin/sips -s format bmp -Z 64 IMAGE --out TEMP.bmp, and always remove the directory.
- Parse width, signed height, bits per pixel, pixel offset, row stride, row order, and BGR(A) order.
- Accept 24-bit uncompressed BMP and the 32-bit sips output.
- On analysis failure, preserve explicit fields, fill missing fields from DEFAULT_STYLE, set fallback true, print the warning once, and exit 0.
- Invalid explicit values are hard errors.
- JSON serves tests. TSV order is appearance, accent, secondary, highlight for Bash.

Run:

~~~~bash
./tests/run-tests.sh
git diff --check
~~~~

Expected: all tests pass.

Commit:

~~~~bash
git add scripts/analyze-image.mjs tests/auto-palette.test.mjs tests/run-tests.sh
git commit -m "feat: add automatic theme palette analysis"
~~~~

### Task 2: Integrate the analyzer into the customizer with TDD

**Files:**
- Modify: tests/auto-palette.test.mjs
- Modify: scripts/customize-theme-macos.sh

- [ ] **Step 1: Add failing customizer integration tests**

Using temporary HOME and synthetic SVG images, spawn scripts/customize-theme-macos.sh with --image, --name, and --no-apply. Read the resulting theme.json from the temporary state directory.

Required tests:

1. No style flags on a light SVG produces light appearance, non-default automatic colors, and 4.5 contrast.
2. Explicit dark plus #112233, #445566, and #778899 persists those values exactly.
3. Only --accent #123456 preserves it while deriving secondary and highlight.

Run the new test file.

Expected: RED because the current script hard-codes dark and the default trio.

- [ ] **Step 2: Track only explicit options**

Initialize:

~~~~bash
ACCENT=""
SECONDARY=""
HIGHLIGHT=""
APPEARANCE=""
~~~~

Validate appearance only when non-empty. Existing argument names and errors remain unchanged.

- [ ] **Step 3: Resolve final style after prepared-image creation**

After moving the prepared JPEG into the theme directory:

- create style_args with --image, prepared path, and --format tsv;
- append appearance/accent/secondary/highlight arguments only when non-empty;
- invoke analyze-image.mjs with the already validated signed Node.js;
- read the four tab-separated fields into APPEARANCE, ACCENT, SECONDARY, HIGHLIGHT;
- verify none are empty;
- pass them to the unchanged write-theme.mjs call.

Analyzer fallback is successful output with a warning. Only analyzer startup/programming failure becomes the existing hard failure.

- [ ] **Step 4: Verify GREEN and commit**

Run:

~~~~bash
./tests/run-tests.sh
git diff --check
~~~~

Expected: automatic, explicit, partial, fallback, contrast, and all old tests pass.

Commit:

~~~~bash
git add scripts/customize-theme-macos.sh tests/auto-palette.test.mjs
git commit -m "feat: apply image-derived theme colors"
~~~~

### Task 3: Update product packaging and documentation

**Files:**
- Modify: scripts/build-release.sh
- Modify: README.md
- Modify: NOTICE.md
- Create outside repository: viewer deployment prompt

- [ ] **Step 1: Capture immutable baselines**

Run:

~~~~bash
git show 53b672e:LICENSE | shasum -a 256
git show 53b672e:NOTICE.md | shasum -a 256
git show 9b6f374:README.md | sed -n '21p'
~~~~

Record hashes and exact attribution copy for final comparison.

- [ ] **Step 2: Restore NOTICE byte identity**

Remove only the later Release asset clarification paragraph.

Verify:

~~~~bash
cmp <(git show 53b672e:NOTICE.md) NOTICE.md
cmp <(git show 53b672e:LICENSE) LICENSE
~~~~

Both commands must exit 0.

- [ ] **Step 3: Extend the release whitelist**

Add exactly:

~~~~text
scripts/analyze-image.mjs
tests/auto-palette.test.mjs
~~~~

Internal docs/superpowers files remain outside the end-user ZIP.

- [ ] **Step 4: Apply only the allowed README edits**

Creator line:

~~~~html
<sub>🎬 作者抖音：<strong>@泽轩604</strong>（App 内搜索即达）</sub>
~~~~

Customization copy:

~~~~markdown
不填写 --accent、--secondary、--highlight 和 --appearance 时，脚本会在本机从图片自动提取三种强调色并判断浅色 / 深色；只填写其中一部分时，明确填写的值优先，其余项目继续自动生成。整个过程不需要模型看图。
~~~~

Keep Markdown code formatting around flag names in the actual README. Keep the manual command as an explicit-override example. Do not change attribution, commands, limits, disclaimers, or other content.

- [ ] **Step 5: Create the external viewer prompt**

The content-workspace artifact must tell a viewer's Codex to:

1. inspect README, LICENSE, NOTICE, and installers;
2. disclose the MIT upstream and non-OpenAI status;
3. confirm macOS and Codex prerequisites;
4. install the complete repository;
5. ask for an owned/authorized image;
6. omit colors and appearance unless the viewer requests overrides;
7. run Verify and preserve the Restore path;
8. report install location, theme, verification, customization, and restore instructions.

It must say the model should not inspect the image because local automatic analysis handles colors. Do not embed a private repository URL.

- [ ] **Step 6: Validate and commit**

Run:

~~~~bash
./tests/run-tests.sh
./scripts/build-release.sh
unzip -t release/codex-immersive-skin-v1.0.0.zip
unzip -Z1 release/codex-immersive-skin-v1.0.0.zip | rg "scripts/analyze-image.mjs$|tests/auto-palette.test.mjs$"
cmp <(git show 53b672e:NOTICE.md) NOTICE.md
cmp <(git show 53b672e:LICENSE) LICENSE
git diff --check
~~~~

Commit:

~~~~bash
git add README.md NOTICE.md scripts/build-release.sh
git commit -m "docs: document automatic theme colors"
~~~~

### Task 4: Final validation, private push, and external receipts

**Files:**
- External state: local main and private GitHub main
- Create externally: automatic-color upgrade receipt
- Modify externally: progress source of truth
- Delete externally after success: used automatic-color task prompt

- [ ] **Step 1: Run the full local gate**

Run:

~~~~bash
./tests/run-tests.sh
./scripts/build-release.sh
unzip -t release/codex-immersive-skin-v1.0.0.zip
git diff --check 9b6f374..HEAD
cmp <(git show 53b672e:NOTICE.md) NOTICE.md
cmp <(git show 53b672e:LICENSE) LICENSE
~~~~

Scan tracked files and ZIP names/content for credentials, literal personal paths, private emails, third-party character assets, and prohibited claims. Upstream names in attribution are allowed.

- [ ] **Step 2: Obtain final spec and quality approval**

Reviewers must confirm all requested behavior, TDD evidence, explicit priority, 4.5 contrast, fallback, no new dependencies, README boundary, LICENSE/NOTICE identity, release contents, and clean scans.

- [ ] **Step 3: Fast-forward main**

From the main repository:

~~~~bash
git merge --ff-only auto-theme-colors
~~~~

Expected: no merge commit, conflict, or unrelated change.

- [ ] **Step 4: Push privately and verify**

Load and follow web-access before network operations.

~~~~bash
gh repo view zexuanw958-svg/codex-immersive-skin --json visibility,defaultBranchRef,url
git push origin main
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
test "$LOCAL_SHA" = "$REMOTE_SHA"
gh repo view zexuanw958-svg/codex-immersive-skin --json visibility,defaultBranchRef,url
~~~~

Visibility must be PRIVATE before and after. Never change it.

- [ ] **Step 5: Write the external upgrade receipt**

Record changed files, the one-sentence algorithm, final tests N/N, final SHA, PRIVATE verification, README scope, LICENSE/NOTICE byte identity, and final ZIP checksum.

- [ ] **Step 6: Update progress and delete the used prompt**

Mark automatic colors complete, record the viewer prompt and receipt, and leave public conversion pending external revalidation.

Delete the used automatic-color prompt through apply_patch only after every prior check passes.

- [ ] **Step 7: Final status**

Local main must be clean and aligned with origin/main. External artifacts must exist. The used prompt must be absent. No public operation may have occurred.

---

Execution mode is already selected: subagent-driven development with independent spec and quality review after each task.
