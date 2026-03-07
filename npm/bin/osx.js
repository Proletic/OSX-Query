#!/usr/bin/env node

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const https = require("node:https");
const readline = require("node:readline/promises");
const { spawnSync } = require("node:child_process");

const pkg = require("../package.json");
const binaryPath = path.join(__dirname, "..", "lib", "vendor", "osx");
const packageName = pkg.name;
const defaultCheckIntervalMs = 24 * 60 * 60 * 1000;

function getCacheFilePath() {
  const baseDir =
    process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache");
  return path.join(baseDir, "osx-query", "update-check.json");
}

function parseVersion(version) {
  return version.split(".").map((part) => Number.parseInt(part, 10) || 0);
}

function isNewerVersion(latest, current) {
  const latestParts = parseVersion(latest);
  const currentParts = parseVersion(current);
  const length = Math.max(latestParts.length, currentParts.length);

  for (let index = 0; index < length; index += 1) {
    const lhs = latestParts[index] || 0;
    const rhs = currentParts[index] || 0;
    if (lhs > rhs) {
      return true;
    }
    if (lhs < rhs) {
      return false;
    }
  }

  return false;
}

function readCache(cacheFile) {
  try {
    return JSON.parse(fs.readFileSync(cacheFile, "utf8"));
  } catch {
    return null;
  }
}

function writeCache(cacheFile, payload) {
  fs.mkdirSync(path.dirname(cacheFile), { recursive: true });
  fs.writeFileSync(cacheFile, `${JSON.stringify(payload)}\n`);
}

function shouldPromptForSkills() {
  if (process.env.CI) {
    return false;
  }

  if (process.env.OSX_QUERY_SKIP_SKILLS_PROMPT === "1") {
    return false;
  }

  return Boolean(process.stdin.isTTY && process.stdout.isTTY);
}

function fetchLatestVersion() {
  return new Promise((resolve, reject) => {
    const request = https.get(
      `https://registry.npmjs.org/${packageName}/latest`,
      {
        headers: {
          Accept: "application/json",
          "User-Agent": "osx-query-update-check",
        },
        timeout: 1500,
      },
      (response) => {
        if (response.statusCode !== 200) {
          response.resume();
          reject(new Error(`Unexpected status ${response.statusCode || "unknown"}`));
          return;
        }

        let body = "";
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          body += chunk;
        });
        response.on("end", () => {
          try {
            const parsed = JSON.parse(body);
            if (!parsed.version) {
              reject(new Error("Registry response did not include a version"));
              return;
            }
            resolve(parsed.version);
          } catch (error) {
            reject(error);
          }
        });
      }
    );

    request.on("timeout", () => {
      request.destroy(new Error("Timed out"));
    });
    request.on("error", reject);
  });
}

async function maybeWarnAboutUpdate() {
  if (process.env.OSX_QUERY_DISABLE_UPDATE_CHECK === "1") {
    return;
  }

  const cacheFile = getCacheFilePath();
  const now = Date.now();
  const intervalHours = Number.parseInt(
    process.env.OSX_QUERY_UPDATE_CHECK_INTERVAL_HOURS || "",
    10
  );
  const intervalMs =
    Number.isFinite(intervalHours) && intervalHours > 0
      ? intervalHours * 60 * 60 * 1000
      : defaultCheckIntervalMs;

  const cached = readCache(cacheFile);
  if (cached && typeof cached.checkedAt === "number" && now - cached.checkedAt < intervalMs) {
    if (cached.latestVersion && isNewerVersion(cached.latestVersion, pkg.version)) {
      console.error(
        `A newer osx-query is available (${cached.latestVersion}). Update with: npm i -g osx-query`
      );
    }
    return;
  }

  try {
    const latestVersion = await fetchLatestVersion();
    writeCache(cacheFile, { checkedAt: now, latestVersion });
    if (isNewerVersion(latestVersion, pkg.version)) {
      console.error(
        `A newer osx-query is available (${latestVersion}). Update with: npm i -g osx-query`
      );
    }
  } catch {
    // Network or registry failures should never block the CLI.
  }
}

async function maybePromptForSkills() {
  if (!shouldPromptForSkills()) {
    return;
  }

  const cacheFile = getCacheFilePath();
  const cached = readCache(cacheFile) || {};
  if (cached.skillsPromptedAt) {
    return;
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  let answer = "";
  try {
    answer = await rl.question(
      "Install the optional Codex skill now? This will run `npx skills add Moulik-Budhiraja/OSX-Query` [y/N]: "
    );
  } finally {
    rl.close();
  }

  const nextCache = {
    ...cached,
    skillsPromptedAt: Date.now(),
  };
  writeCache(cacheFile, nextCache);

  if (!/^(y|yes)$/i.test(answer.trim())) {
    return;
  }

  const command = process.platform === "win32" ? "npx.cmd" : "npx";
  const result = spawnSync(command, ["skills", "add", "Moulik-Budhiraja/OSX-Query"], {
    stdio: "inherit",
  });

  if (result.error) {
    console.warn(
      "Skill installer could not be launched. Run `npx skills add Moulik-Budhiraja/OSX-Query` manually."
    );
    return;
  }

  if (result.status !== 0) {
    console.warn(
      "Skill install did not complete successfully. Run `npx skills add Moulik-Budhiraja/OSX-Query` manually."
    );
  }
}

if (!fs.existsSync(binaryPath)) {
  console.error("osx-query is not installed correctly: native binary is missing");
  console.error("Try reinstalling: npm i -g osx-query");
  process.exit(1);
}

async function main() {
  await maybeWarnAboutUpdate();
  await maybePromptForSkills();

  const result = spawnSync(binaryPath, process.argv.slice(2), {
    stdio: "inherit",
  });

  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }

  process.exit(result.status === null ? 1 : result.status);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
