#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/crawl4ai"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
CONFIG_FILE="${CONFIG_DIR}/opencode.jsonc"

if [[ ! -f "${CONFIG_FILE}" && -f "${CONFIG_DIR}/opencode.json" ]]; then
    CONFIG_FILE="${CONFIG_DIR}/opencode.json"
fi

source "${TOOL_DIR}/.env"
mkdir -p "${CONFIG_DIR}"

node - "${CONFIG_FILE}" "http://localhost:${CRAWL4AI_PORT:-11235}" "${CRAWL4AI_API_TOKEN:-}" <<'NODE'
const fs = require("fs");
const [configFile, crawl4aiUrl, crawl4aiToken] = process.argv.slice(2);
const entry = {
  type: "local",
  command: ["crawl4ai-mcp", "--stdio", "--endpoint", crawl4aiUrl],
  enabled: true,
};

if (crawl4aiToken) {
  entry.environment = { CRAWL4AI_BEARER_TOKEN: crawl4aiToken };
}

function parseJsonc(source) {
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
  return JSON.parse(result.replace(/,\s*([}\]])/g, "$1"));
}

let config = {};
if (fs.existsSync(configFile)) {
  try { config = parseJsonc(fs.readFileSync(configFile, "utf8")); }
  catch (error) {
    console.error(`Unable to parse ${configFile}: ${error.message}`);
    process.exit(1);
  }
}
if (!config.mcp || typeof config.mcp !== "object" || Array.isArray(config.mcp)) config.mcp = {};
config.mcp.crawl4ai = entry;
fs.writeFileSync(configFile, `${JSON.stringify(config, null, 2)}\n`);
NODE

printf '\033[32m[OK]\033[0m OpenCode MCP configuration updated (%s)\n' "${CONFIG_FILE}"
