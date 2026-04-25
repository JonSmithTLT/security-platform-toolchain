#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/yara-rules"
URL="${YARA_RULES_REPO_URL:-}"
YARA_FORGE_RULESET="${YARA_FORGE_RULESET:-extended}"
YARA_FORGE_RELEASE_API="${YARA_FORGE_RELEASE_API:-https://api.github.com/repos/YARAHQ/yara-forge/releases/latest}"

require_cmd sha256sum
mkdir -p "${OUT_DIR}"
if [[ -z "${URL}" ]]; then
    require_cmd curl
    require_cmd python3
    require_cmd unzip
    log "Fetching YARA Forge ${YARA_FORGE_RULESET} rules"
    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"
    release_json="${OUT_DIR}/yara-forge-release.json"
    download "${YARA_FORGE_RELEASE_API}" "${release_json}"
    asset_url="$(python3 - "${release_json}" "${YARA_FORGE_RULESET}" <<'PY'
import json
import sys

release_path, ruleset = sys.argv[1], sys.argv[2].lower()
with open(release_path, "r", encoding="utf-8") as fh:
    release = json.load(fh)
assets = release.get("assets", [])
matches = [
    asset.get("browser_download_url", "")
    for asset in assets
    if ruleset in asset.get("name", "").lower() and asset.get("name", "").lower().endswith(".zip")
]
print(matches[0] if matches else "")
PY
)"
    if [[ -z "${asset_url}" ]]; then
        warn "Could not find a YARA Forge ${YARA_FORGE_RULESET} zip asset in the latest release"
        write_metadata "${OUT_DIR}" "yara-rules" "yara-forge:${YARA_FORGE_RULESET}:asset-not-found"
        exit 0
    fi
    download "${asset_url}" "${OUT_DIR}/yara-forge-${YARA_FORGE_RULESET}.zip"
    unzip -q "${OUT_DIR}/yara-forge-${YARA_FORGE_RULESET}.zip" -d "${OUT_DIR}/yara-forge-${YARA_FORGE_RULESET}"
    write_metadata "${OUT_DIR}" "yara-rules" "${asset_url}"
    write_checksums "${OUT_DIR}"
    exit 0
fi
require_cmd git
log "Fetching YARA rules from ${URL}"
if [[ -d "${OUT_DIR}/.git" ]]; then
    git -C "${OUT_DIR}" pull --ff-only
else
    rm -rf "${OUT_DIR}"
    git clone --depth 1 "${URL}" "${OUT_DIR}"
fi
write_metadata "${OUT_DIR}" "yara-rules" "${URL}"
write_checksums "${OUT_DIR}"
