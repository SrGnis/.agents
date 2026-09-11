#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
CONFIG_FILE="${CONFIG_DIR}/opencode.jsonc"

if [[ ! -f "${CONFIG_FILE}" && -f "${CONFIG_DIR}/opencode.json" ]]; then
    CONFIG_FILE="${CONFIG_DIR}/opencode.json"
fi
[[ -f "${CONFIG_FILE}" ]] || exit 0

node - "${CONFIG_FILE}" <<'NODE'
const fs = require("fs");
const configFile = process.argv[2];
let source = fs.readFileSync(configFile, "utf8");
let result = "";
let inString = false;
let escaped = false;
let lineComment = false;
let blockComment = false;
for (let i = 0; i < source.length; i += 1) {
  const character = source[i];
  const next = source[i + 1];
  if (lineComment) {
    if (character === "\n") { lineComment = false; result += character; }
    continue;
  }
  if (blockComment) {
    if (character === "*" && next === "/") { blockComment = false; i += 1; }
    continue;
  }
  if (inString) {
    result += character;
    if (escaped) escaped = false;
    else if (character === "\\") escaped = true;
    else if (character === '"') inString = false;
    continue;
  }
  if (character === '"') { inString = true; result += character; }
  else if (character === "/" && next === "/") { lineComment = true; i += 1; }
  else if (character === "/" && next === "*") { blockComment = true; i += 1; }
  else result += character;
}

let config;
try { config = JSON.parse(result.replace(/,\s*([}\]])/g, "$1")); }
catch (error) {
  console.error(`Unable to parse ${configFile}: ${error.message}`);
  process.exit(1);
}
if (config.mcp && typeof config.mcp === "object") {
  delete config.mcp.crawl4ai;
  if (Object.keys(config.mcp).length === 0) delete config.mcp;
}
fs.writeFileSync(configFile, `${JSON.stringify(config, null, 2)}\n`);
NODE

printf '\033[32m[OK]\033[0m OpenCode MCP configuration updated (%s)\n' "${CONFIG_FILE}"
