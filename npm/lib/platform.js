"use strict";

function getAssetName(version) {
  if (process.platform !== "darwin") {
    throw new Error("osx-query only supports macOS");
  }

  if (process.arch === "arm64") {
    return `osx-v${version}-arm64.zip`;
  }

  if (process.arch === "x64") {
    return `osx-v${version}-x86_64.zip`;
  }

  throw new Error(`Unsupported architecture: ${process.arch}`);
}

module.exports = {
  getAssetName,
};
