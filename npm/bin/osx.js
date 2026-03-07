#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const binaryPath = path.join(__dirname, "..", "lib", "vendor", "osx");

if (!fs.existsSync(binaryPath)) {
  console.error("osx-query is not installed correctly: native binary is missing");
  console.error("Try reinstalling: npm i -g osx-query");
  process.exit(1);
}

const result = spawnSync(binaryPath, process.argv.slice(2), {
  stdio: "inherit",
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
