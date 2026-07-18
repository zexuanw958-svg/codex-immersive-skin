import fs from "node:fs/promises";
import crypto from "node:crypto";
import path from "node:path";

const [mode, configPath, backupPath, ...args] = process.argv.slice(2);
let appearance = "dark";
let keepBackup = false;
let validateOnly = false;
let expectedConfigSha256 = null;
for (let index = 0; index < args.length; index += 1) {
  const argument = args[index];
  if (argument === "--appearance" && mode === "install") {
    const value = args[index + 1];
    if (!value || value.startsWith("--")) throw new Error("--appearance requires a value");
    appearance = value;
    index += 1;
  } else if (argument === "--expected-config-sha256" && mode === "install") {
    const value = args[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error("--expected-config-sha256 requires a value");
    }
    if (!/^[0-9a-f]{64}$/i.test(value)) {
      throw new Error("--expected-config-sha256 must be exactly 64 hexadecimal characters");
    }
    expectedConfigSha256 = value.toLowerCase();
    index += 1;
  } else if (argument === "--keep-backup" && mode === "restore") {
    keepBackup = true;
  } else if (argument === "--validate-only" && mode === "restore") {
    validateOnly = true;
  } else {
    throw new Error(`Unknown or misplaced option: ${argument}`);
  }
}
if (!["light", "dark"].includes(appearance)) throw new Error("--appearance must be light or dark");
const settings = new Map([
  ["appearanceTheme", `appearanceTheme = "${appearance}"`],
  ["appearanceDarkCodeThemeId", 'appearanceDarkCodeThemeId = "codex"'],
]);

if (!["install", "restore"].includes(mode) || !configPath || !backupPath) {
  throw new Error("Usage: theme-config.mjs <install|restore> <config-path> <backup-path> [--appearance light|dark] [--expected-config-sha256 <64hex>]");
}

function desktopSection(content) {
  const header = /^[ \t]*\[desktop\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|$)/m.exec(content);
  if (!header) return null;
  const bodyStart = header.index + header[0].length;
  const remainder = content.slice(bodyStart);
  const nextHeader = /^[ \t]*\[/m.exec(remainder);
  const bodyEnd = nextHeader ? bodyStart + nextHeader.index : content.length;
  return {
    bodyStart,
    bodyEnd,
    body: content.slice(bodyStart, bodyEnd),
    headerEndedAtEof: !/(?:\r\n|\n)$/.test(header[0]),
  };
}

function replaceSetting(body, key, line, eol) {
  const pattern = new RegExp(`^[ \\t]*${key.replace(/[.*+?^${}()|[\\]\\]/g, "\\$&")}[ \\t]*=.*(?:\\r?\\n)?`, "m");
  if (line === null) return body.replace(pattern, "");
  if (pattern.test(body)) return body.replace(pattern, `${line}${eol}`);
  const separator = body.length && !/(?:\r\n|\n)$/.test(body) ? eol : "";
  return `${body}${separator}${line}${eol}`;
}

function textHash(value) {
  return crypto.createHash("sha256").update(value, "utf8").digest("hex");
}

function sameConfigPath(first, second) {
  const normalize = (value) => {
    const resolved = path.resolve(value);
    return process.platform === "win32" ? resolved.toLowerCase() : resolved;
  };
  return typeof first === "string" && normalize(first) === normalize(second);
}

function validateBackup(backup, { allowPending = false } = {}) {
  if (!backup || backup.schemaVersion !== 1 || backup.platform !== process.platform
    || !sameConfigPath(backup.configPath, configPath) || !backup.values) {
    throw new Error("Theme backup identity or schema does not match this config.");
  }
  if (backup.transaction !== undefined) {
    const transaction = backup.transaction;
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!transaction || typeof transaction !== "object"
      || !["pending", "active"].includes(transaction.state)
      || typeof transaction.owner !== "string" || !uuid.test(transaction.owner)) {
      throw new Error("Theme backup transaction metadata is invalid.");
    }
    if (transaction.state === "pending" && !allowPending) {
      throw new Error("Theme backup transaction is pending in another install; no config was changed.");
    }
  }
  for (const key of settings.keys()) {
    const value = backup.values[key];
    const validLine = typeof value === "string"
      && new RegExp(`^[ \\t]*${key}[ \\t]*=[^\\r\\n]*$`).test(value);
    if (!(key in backup.values) || (value !== null && !validLine)) {
      throw new Error(`Theme backup value is invalid: ${key}`);
    }
  }
  if (backup.structure !== undefined) {
    const structure = backup.structure;
    const sha256 = /^[0-9a-f]{64}$/;
    if (!structure || typeof structure !== "object"
      || typeof structure.desktopSectionExisted !== "boolean"
      || !Number.isSafeInteger(structure.contentLength) || structure.contentLength < 0
      || typeof structure.contentSha256 !== "string" || !sha256.test(structure.contentSha256)
      || !Number.isSafeInteger(structure.sectionBodyLength) || structure.sectionBodyLength < 0
      || typeof structure.sectionBodySha256 !== "string" || !sha256.test(structure.sectionBodySha256)
      || typeof structure.appendedSection !== "string"
      || !["\n", "\r\n"].includes(structure.eol)
      || (structure.headerEolAdded !== undefined && typeof structure.headerEolAdded !== "boolean")
      || (structure.headerEolAdded === true && !structure.desktopSectionExisted)
      || (structure.desktopSectionExisted && structure.appendedSection !== "")) {
      throw new Error("Theme backup structure metadata is invalid.");
    }
    if (!structure.desktopSectionExisted) {
      const header = `[desktop]${structure.eol}`;
      const allowed = structure.contentLength === 0
        ? [header]
        : [`${structure.eol}${header}`, `${structure.eol}${structure.eol}${header}`];
      if (!allowed.includes(structure.appendedSection)) {
        throw new Error("Theme backup structure metadata is invalid.");
      }
    }
  }
  return backup;
}

async function waitForTestBarrier(stage) {
  if (process.env.CODEX_IMMERSIVE_TEST_MODE !== "1"
      || process.env.CODEX_IMMERSIVE_THEME_CONFIG_TEST_BARRIER_STAGE !== stage) return;
  if (typeof process.send !== "function") throw new Error("Theme-config test IPC is unavailable.");
  await new Promise((resolve, reject) => {
    let settled = false;
    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      process.off("message", onMessage);
      process.off("disconnect", onDisconnect);
      if (error) reject(error);
      else resolve();
    };
    const onMessage = (message) => {
      if (message?.type === "theme-config-barrier-release" && message.stage === stage) finish();
    };
    const onDisconnect = () => finish(new Error("Theme-config test IPC disconnected."));
    const timeout = setTimeout(
      () => finish(new Error(`Timed out at theme-config test barrier: ${stage}`)),
      10000,
    );
    process.on("message", onMessage);
    process.once("disconnect", onDisconnect);
    process.send({ type: "theme-config-barrier-ready", stage }, (error) => {
      if (error) finish(error);
    });
  });
}

async function assertFileHash(file, expectedHash) {
  let current;
  try {
    current = await fs.readFile(file, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    current = null;
  }
  if (current === null || textHash(current) !== expectedHash) {
    const conflict = new Error("Codex config changed concurrently; nothing was overwritten.");
    conflict.code = "ECONFLICT";
    throw conflict;
  }
}

const transientRenameErrors = new Set(["EACCES", "EBUSY", "EPERM"]);

async function renameWithExpectedHash(temporary, file, expectedHash) {
  const attempts = expectedHash === null ? 1 : 8;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (expectedHash !== null) await assertFileHash(file, expectedHash);
    try {
      await fs.rename(temporary, file);
      return;
    } catch (error) {
      if (!transientRenameErrors.has(error.code) || attempt + 1 >= attempts) throw error;
      const delayMs = Math.min(25 * (2 ** attempt), 400);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}

function temporaryPath(file) {
  return `${file}.${process.pid}.${crypto.randomUUID()}.tmp`;
}

async function atomicWrite(file, value, modeBits, expectedHash = null) {
  const temporary = temporaryPath(file);
  try {
    await fs.writeFile(temporary, value, { mode: modeBits, flag: "wx" });
    await renameWithExpectedHash(temporary, file, expectedHash);
    await fs.chmod(file, modeBits);
  } finally {
    await fs.rm(temporary, { force: true }).catch(() => {});
  }
}

async function atomicCreate(file, value, modeBits) {
  const temporary = temporaryPath(file);
  try {
    await fs.writeFile(temporary, value, { mode: modeBits, flag: "wx" });
    await fs.link(temporary, file);
    await fs.chmod(file, modeBits);
  } finally {
    await fs.rm(temporary, { force: true }).catch(() => {});
  }
}

async function removeOwnedPendingBackup(file, expectedHash, owner) {
  let current;
  try {
    current = await fs.readFile(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return;
    throw error;
  }
  if (textHash(current) !== expectedHash) return;
  let backup;
  try {
    backup = validateBackup(JSON.parse(current), { allowPending: true });
  } catch {
    return;
  }
  if (backup.transaction?.state !== "pending" || backup.transaction.owner !== owner) return;
  await fs.unlink(file);
}

let content;
try {
  content = await fs.readFile(configPath, "utf8");
} catch (error) {
  if (error.code === "ENOENT") throw new Error(`Codex config not found: ${configPath}`);
  throw error;
}

const initialConfigSha256 = textHash(content);
if (mode === "install" && expectedConfigSha256 !== null
    && initialConfigSha256 !== expectedConfigSha256) {
  throw new Error("The config hash does not match the expected config snapshot; nothing was changed.");
}
const originalStat = await fs.stat(configPath);
const eol = content.match(/\r\n|\n/)?.[0] ?? "\n";
let section = desktopSection(content);
const originalContent = content;
const originalSection = section;
let appendedSection = "";
let headerEolAdded = false;
if (mode === "install" && section?.headerEndedAtEof) {
  content += eol;
  headerEolAdded = true;
  section = desktopSection(content);
}
if (mode === "install" && !section) {
  const leadingEol = content.length > 0 && !/(?:\r\n|\n)$/.test(content) ? eol : "";
  const blankLine = content.length > 0 ? eol : "";
  appendedSection = `${leadingEol}${blankLine}[desktop]${eol}`;
  content += appendedSection;
  section = desktopSection(content);
}

if (mode === "install") {
  let existingBackup = null;
  let createdBackup = null;
  try {
    existingBackup = JSON.parse(await fs.readFile(backupPath, "utf8"));
    validateBackup(existingBackup);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw new Error(`Could not validate the existing theme backup: ${error.message}`);
    }
    const values = {};
    for (const key of settings.keys()) {
      const match = new RegExp(`^[ \\t]*${key}[ \\t]*=.*$`, "m").exec(section.body);
      values[key] = match ? match[0] : null;
    }
    const owner = crypto.randomUUID();
    const backup = {
      schemaVersion: 1,
      platform: process.platform,
      createdAt: new Date().toISOString(),
      configPath,
      transaction: {
        state: "pending",
        owner,
      },
      values,
      structure: {
        desktopSectionExisted: originalSection !== null,
        contentLength: originalContent.length,
        contentSha256: initialConfigSha256,
        sectionBodyLength: originalSection?.body.length ?? 0,
        sectionBodySha256: textHash(originalSection?.body ?? ""),
        appendedSection,
        headerEolAdded,
        eol,
      },
    };
    const pendingText = `${JSON.stringify(backup, null, 2)}\n`;
    const activeText = `${JSON.stringify({
      ...backup,
      transaction: { ...backup.transaction, state: "active" },
    }, null, 2)}\n`;
    await fs.mkdir(path.dirname(backupPath), { recursive: true, mode: 0o700 });
    await waitForTestBarrier("before-backup-create");
    try {
      await atomicCreate(backupPath, pendingText, 0o600);
      createdBackup = {
        activeText,
        owner,
        pendingHash: textHash(pendingText),
      };
    } catch (error) {
      if (error.code === "EEXIST") {
        throw new Error("Theme backup was created concurrently; no config was changed.");
      }
      throw error;
    }
  }

  let body = section.body;
  for (const [key, line] of settings) body = replaceSetting(body, key, line, eol);
  const updated = content.slice(0, section.bodyStart) + body + content.slice(section.bodyEnd);
  await waitForTestBarrier("before-config-write");
  try {
    await atomicWrite(
      configPath,
      updated,
      originalStat.mode & 0o777,
      expectedConfigSha256 ?? initialConfigSha256,
    );
  } catch (error) {
    if (createdBackup !== null) {
      try {
        await removeOwnedPendingBackup(backupPath, createdBackup.pendingHash, createdBackup.owner);
      } catch (cleanupError) {
        error.message += ` The pending backup could not be cleaned up safely: ${cleanupError.message}`;
      }
    }
    throw error;
  }
  if (createdBackup !== null) {
    await atomicWrite(backupPath, createdBackup.activeText, 0o600, createdBackup.pendingHash);
  }
  console.log(`Saved the original base-theme keys and selected the ${appearance} Codex base theme.`);
} else {
  let backup;
  try {
    backup = validateBackup(JSON.parse(await fs.readFile(backupPath, "utf8")));
  } catch (error) {
    if (error.code === "ENOENT") throw new Error("No selective pre-install theme backup is available.");
    throw new Error(`Could not read the theme backup: ${error.message}`);
  }
  const structure = backup.structure;
  let restored;
  if (!section) {
    if (structure?.desktopSectionExisted === false) {
      restored = content;
    } else {
      throw new Error("The Codex desktop section is missing; nothing was restored.");
    }
  } else {
    let body = section.body;
    for (const key of settings.keys()) {
      body = replaceSetting(body, key, backup.values[key] ?? null, eol);
    }
    if (structure?.desktopSectionExisted === true
        && textHash(body) !== structure.sectionBodySha256
        && body.endsWith(structure.eol ?? eol)) {
      const withoutAddedEol = body.slice(0, -(structure.eol ?? eol).length);
      if (withoutAddedEol.length === structure.sectionBodyLength
          && textHash(withoutAddedEol) === structure.sectionBodySha256) {
        body = withoutAddedEol;
      }
    }
    restored = content.slice(0, section.bodyStart) + body + content.slice(section.bodyEnd);
    if (structure?.desktopSectionExisted === true && structure.headerEolAdded === true) {
      if (!restored.endsWith(structure.eol)) {
        throw new Error("The generated desktop header separator changed; nothing was restored.");
      }
      const withoutHeaderEol = restored.slice(0, -structure.eol.length);
      if (withoutHeaderEol.length !== structure.contentLength
          || textHash(withoutHeaderEol) !== structure.contentSha256) {
        throw new Error("The desktop header changed after install; nothing was restored.");
      }
      restored = withoutHeaderEol;
    }
    if (structure?.desktopSectionExisted === false) {
      if (body.length === 0 && restored.endsWith(structure.appendedSection)) {
        restored = restored.slice(0, -structure.appendedSection.length);
      }
    }
  }
  if (validateOnly) {
    console.log("Validated the saved base-theme restore transaction.");
  } else {
    const contentSha256 = textHash(content);
    await waitForTestBarrier("before-config-write");
    if (restored !== content) {
      await atomicWrite(configPath, restored, originalStat.mode & 0o777, contentSha256);
    } else {
      await assertFileHash(configPath, contentSha256);
    }
    if (!keepBackup) {
      await assertFileHash(configPath, textHash(restored));
      await fs.unlink(backupPath);
    }
    console.log("Restored the saved base-theme keys.");
  }
}
