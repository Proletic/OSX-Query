"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const https = require("node:https");
const readline = require("node:readline/promises");
const { pipeline } = require("node:stream/promises");
const { createWriteStream } = require("node:fs");
const { spawnSync } = require("node:child_process");

const pkg = require("../package.json");
const { getAssetName } = require("./platform");

async function download(url, destination) {
  await new Promise((resolve, reject) => {
    const request = https.get(
      url,
      {
        headers: {
          "User-Agent": "osx-query-installer",
        },
      },
      async (response) => {
        if (
          response.statusCode &&
          response.statusCode >= 300 &&
          response.statusCode < 400 &&
          response.headers.location
        ) {
          response.resume();
          try {
            await download(response.headers.location, destination);
            resolve();
          } catch (error) {
            reject(error);
          }
          return;
        }

        if (response.statusCode !== 200) {
          reject(
            new Error(
              `Failed to download ${url} (status ${response.statusCode || "unknown"})`
            )
          );
          return;
        }

        try {
          await pipeline(response, createWriteStream(destination));
          resolve();
        } catch (error) {
          reject(error);
        }
      }
    );

    request.on("error", reject);
  });
}

function extract(zipPath, outputDir) {
  const result = spawnSync("ditto", ["-x", "-k", zipPath, outputDir], {
    stdio: "inherit",
  });

  if (result.status !== 0) {
    throw new Error("Failed to extract release archive");
  }
}

function installBinary(extractedRoot, vendorDir) {
  const entries = fs.readdirSync(extractedRoot, { withFileTypes: true });
  const packageDir = entries.find((entry) => entry.isDirectory());

  if (!packageDir) {
    throw new Error("Release archive did not contain the expected directory");
  }

  const sourceBinary = path.join(extractedRoot, packageDir.name, "osx");
  const targetBinary = path.join(vendorDir, "osx");

  if (!fs.existsSync(sourceBinary)) {
    throw new Error("Release archive did not contain the osx binary");
  }

  fs.mkdirSync(vendorDir, { recursive: true });
  fs.copyFileSync(sourceBinary, targetBinary);
  fs.chmodSync(targetBinary, 0o755);
  return targetBinary;
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

async function maybePromptForSkills() {
  if (!shouldPromptForSkills()) {
    console.log(
      "Optional: run `npx skills add Moulik-Budhiraja/OSX-Query` to install the Codex skill."
    );
    return;
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    const answer = await rl.question(
      "Install the optional Codex skill now? This will run `npx skills add Moulik-Budhiraja/OSX-Query` [y/N]: "
    );

    if (!/^(y|yes)$/i.test(answer.trim())) {
      console.log(
        "Skipped skill install. You can run `npx skills add Moulik-Budhiraja/OSX-Query` later."
      );
      return;
    }
  } finally {
    rl.close();
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

async function main() {
  const binaryVersion = pkg.osxBinaryVersion || pkg.version;
  const assetName = getAssetName(binaryVersion);
  const url = `https://github.com/Moulik-Budhiraja/OSX-Query/releases/download/v${binaryVersion}/${assetName}`;
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "osx-query-"));
  const zipPath = path.join(tempDir, assetName);
  const extractDir = path.join(tempDir, "extract");
  const vendorDir = path.join(__dirname, "vendor");

  try {
    console.log(`Downloading ${assetName}`);
    await download(url, zipPath);

    fs.rmSync(vendorDir, { recursive: true, force: true });
    fs.mkdirSync(extractDir, { recursive: true });

    extract(zipPath, extractDir);
    const installedBinary = installBinary(extractDir, vendorDir);
    console.log(`Installed osx at ${installedBinary}`);
    console.log("Run `osx --help` to get started.");
    await maybePromptForSkills();
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
