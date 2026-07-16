# README Public Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the repository README as a polished Chinese-first project landing page with a Douyin return path, then publish the verified repository publicly.

**Architecture:** This is a documentation-and-release change only. `README.md` becomes the user-facing landing page, existing repository-owned theme images provide honest visual previews, and the repository remains private until local validation and remote commit verification both pass.

**Tech Stack:** GitHub-flavored Markdown, HTML alignment blocks, shields.io badges, Bash validation scripts, Git, GitHub CLI

---

## File map

- Modify `README.md`: public project landing page, installation guide, safety notes, attribution, and English summary.
- Preserve `assets/morning-mist.png`: light-theme background preview.
- Preserve `examples/warm-sand/background.png`: dark-theme background preview.
- Preserve `LICENSE` and `NOTICE.md`: licensing and upstream notices.
- Reference `docs/superpowers/specs/2026-07-16-readme-public-launch-design.md`: approved product and publishing requirements.
- Create this plan at `docs/superpowers/plans/2026-07-16-readme-public-launch.md`.

No runtime JavaScript, shell scripts, theme configuration, assets, license text, or NOTICE text will change.

### Task 1: Rebuild the README landing page

**Files:**
- Modify: `README.md`
- Reference: `docs/superpowers/specs/2026-07-16-readme-public-launch-design.md`

- [ ] **Step 1: Record the factual content that must survive the rewrite**

Run:

```bash
rg -n 'Fei-Away/Codex-Dream-Skin|HeiGeAi/codex-miku-theme|com\.openai\.codex|127\.0\.0\.1|MIT License|OpenAI|50 MB|3200 px|16 MB' README.md
```

Expected: every listed attribution, safety boundary, license statement, and image limit appears in the current README before editing.

- [ ] **Step 2: Replace the opening with the approved Hero block**

The opening must use this exact information hierarchy:

```markdown
<div align="center">

# ✨ Codex Immersive Skin

**把自己的图片，变成 macOS Codex Desktop 的沉浸式主题。**

主页独立横幅 · 任务页低干扰背景 · 磨砂内容层 · 浅色 / 深色自适应 · 一键验证与恢复

[![Platform: macOS](https://img.shields.io/badge/platform-macOS-111827?style=flat-square&logo=apple&logoColor=white)](#-使用前准备)
[![License: MIT](https://img.shields.io/badge/license-MIT-2563eb?style=flat-square)](LICENSE)
[![Theme: Light / Dark](https://img.shields.io/badge/theme-light%20%2F%20dark-8b5cf6?style=flat-square)](#-换成自己的图片)
[![Tests: Passing](https://img.shields.io/badge/tests-passing-16a34a?style=flat-square)](#-自检与恢复)
[![Restore: Reversible](https://img.shields.io/badge/restore-reversible-f59e0b?style=flat-square)](#-自检与恢复)

<sub>🎬 更多 AI 工具实战玩法：作者抖音 <strong>@泽轩604</strong>（App 内搜索即达）</sub>

<sub><a href="#-30-秒理解">✨ 特点</a> · <a href="#-快速开始">🚀 安装</a> · <a href="#-换成自己的图片">🖼️ 自定义</a> · <a href="#-工作原理与安全边界">🛡️ 安全</a> · <a href="#-常见问题">❓ FAQ</a> · <a href="#-english-summary">English</a></sub>

</div>
```

Immediately below the Hero, add a short unofficial-project notice and the complete upstream attribution. Do not link the Douyin line to the unrelated `travel-plan-viz` video.

- [ ] **Step 3: Reorganize the Chinese documentation into the approved section order**

Use these headings in order:

```markdown
## ✨ 30 秒理解
## 🖼️ 两套内置主题
## 💻 使用前准备
## 🚀 快速开始
## 🎨 换成自己的图片
## 🧰 桌面入口
## ✅ 自检与恢复
## 🛡️ 工作原理与安全边界
## ❓ 常见问题
## 🙏 来源与致谢
## 📄 许可证、素材与免责声明
## English Summary
```

The `30 秒理解` section must be a two-column feature table covering immersive layout, native component adaptation, light/dark modes, persistent reinjection, and verification/recovery. The theme section must render the two real repository assets side by side:

```html
<table>
  <tr>
    <td align="center"><img src="assets/morning-mist.png" alt="晨雾浅色主题背景预览" width="100%"></td>
    <td align="center"><img src="examples/warm-sand/background.png" alt="暖沙深色主题背景预览" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>晨雾 · Light</strong></td>
    <td align="center"><strong>暖沙 · Dark</strong></td>
  </tr>
</table>
```

Keep the existing ZIP installation, Git clone, CLI customization, demo reset, warm-sand switch, static test, live verification, and restore commands semantically unchanged. Add a short FAQ for macOS Gatekeeper, supported platforms, whether the app bundle is modified, and how to fully restore.

- [ ] **Step 4: Add a concise English summary**

The English section must include the following facts without duplicating the full Chinese guide:

```markdown
## English Summary

Codex Immersive Skin turns a user-owned image into an immersive theme for Codex Desktop on macOS while keeping the native sidebar, cards, project picker, task content, and composer usable.

### Highlights

- User-selected backgrounds with light and dark appearance modes.
- Runtime reinjection after refreshes, route changes, and renderer recreation.
- Signed bundled Node.js validation; no modification of Codex.app, app.asar, or its code signature.
- Desktop shortcuts for customization, live verification, and complete restoration.

### Quick start

Download the repository ZIP, extract it, and open `Install Codex Immersive Skin.command`. If Gatekeeper blocks the file, right-click it in Finder and choose **Open**.

This project is based on the MIT-licensed `Fei-Away/Codex-Dream-Skin` and takes creative inspiration from `HeiGeAi/codex-miku-theme` and 黑哥Ai. It is an independent community project and is not published, sponsored, authorized, or endorsed by OpenAI.
```

- [ ] **Step 5: Check required copy and local assets**

Run:

```bash
rg -n '@泽轩604|Fei-Away/Codex-Dream-Skin|HeiGeAi/codex-miku-theme|不是 OpenAI|not published.*OpenAI|127\.0\.0\.1|app\.asar' README.md
test -f assets/morning-mist.png
test -f examples/warm-sand/background.png
test -f LICENSE
test -f NOTICE.md
```

Expected: all commands exit 0, both previews exist, and both Chinese and English attribution/disclaimer text is present.

### Task 2: Validate the private release candidate

**Files:**
- Test: `README.md`
- Test: repository runtime and release archive through existing scripts

- [ ] **Step 1: Check Markdown whitespace and repository-local references**

Run:

```bash
git diff --check
for path in \
  assets/morning-mist.png \
  examples/warm-sand/background.png \
  references/asset-provenance.md \
  LICENSE \
  NOTICE.md; do
  test -e "$path" || { echo "Missing README target: $path" >&2; exit 1; }
done
```

Expected: no whitespace errors and no missing local targets.

- [ ] **Step 2: Run the full existing test suite**

Run:

```bash
./tests/run-tests.sh
```

Expected: Node test output reports 9 passing tests and ends with `PASS: syntax, payload, custom-theme, config round-trip, HOME recovery, signature, and doctor checks.`

- [ ] **Step 3: Build and inspect the release archive**

Run:

```bash
./scripts/build-release.sh
unzip -t release/codex-immersive-skin-v1.0.0.zip
unzip -Z1 release/codex-immersive-skin-v1.0.0.zip | rg 'README\.md$|assets/morning-mist\.png$|examples/warm-sand/background\.png$'
```

Expected: the archive builds successfully, `unzip -t` reports no errors, and all three required public-facing files are present.

- [ ] **Step 4: Scan publishable files for secrets and local privacy leaks**

Run:

```bash
if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!release/**' \
  --glob '!docs/superpowers/**' \
  '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|session[_-]?token|access[_-]?token\s*[:=]|password\s*[:=])' .; then
  echo 'Credential-like content found.' >&2
  exit 1
fi

if rg -n '(/Users/[^/[:space:]]+|/var/folders/)' README.md CHANGELOG.md NOTICE.md SKILL.md references scripts assets examples tests *.command; then
  echo 'Local private path found.' >&2
  exit 1
fi
```

Expected: both scans return no matches.

- [ ] **Step 5: Review the complete diff**

Run:

```bash
git diff -- README.md
git status --short --branch
```

Expected: only the approved README change is pending; the repository remains on `main` and GitHub visibility is still Private.

### Task 3: Commit and verify the remote private repository

**Files:**
- Commit: `README.md`

- [ ] **Step 1: Commit the README**

Run:

```bash
git add README.md
git commit -m "docs: redesign README for public launch"
```

Expected: one commit is created containing only `README.md`.

- [ ] **Step 2: Push `main` while the repository is still Private**

Run:

```bash
git push origin main
```

Expected: Git reports that `main` was updated successfully.

- [ ] **Step 3: Verify local and remote commits match**

Run:

```bash
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
printf 'local=%s\nremote=%s\n' "$LOCAL_SHA" "$REMOTE_SHA"
test "$LOCAL_SHA" = "$REMOTE_SHA"
```

Expected: both SHAs are identical.

### Task 4: Make the GitHub repository public

**Files:**
- External state: `zexuanw958-svg/codex-immersive-skin` repository visibility

- [ ] **Step 1: Confirm the final pre-public state**

Run:

```bash
test -z "$(git status --porcelain)"
gh repo view zexuanw958-svg/codex-immersive-skin --json nameWithOwner,visibility,defaultBranchRef,url
```

Expected: the working tree is clean, the default branch is `main`, and visibility is `PRIVATE`.

- [ ] **Step 2: Change visibility with the explicit consequence flag**

Run:

```bash
gh repo edit zexuanw958-svg/codex-immersive-skin \
  --visibility public \
  --accept-visibility-change-consequences
```

Expected: GitHub accepts the visibility change without an error.

- [ ] **Step 3: Verify public visibility and unauthenticated reachability**

Run:

```bash
gh repo view zexuanw958-svg/codex-immersive-skin \
  --json nameWithOwner,visibility,defaultBranchRef,url
curl --fail --silent --show-error \
  https://api.github.com/repos/zexuanw958-svg/codex-immersive-skin \
  | rg '"visibility": "public"|"private": false'
```

Expected: GitHub CLI returns `PUBLIC`, the public API request succeeds without credentials, and the API response confirms public visibility.

- [ ] **Step 4: Record the final public commit and URL**

Run:

```bash
git rev-parse HEAD
gh repo view zexuanw958-svg/codex-immersive-skin --json url,visibility --jq '.url + " " + .visibility'
```

Expected: output includes the released commit SHA and `https://github.com/zexuanw958-svg/codex-immersive-skin PUBLIC`.
