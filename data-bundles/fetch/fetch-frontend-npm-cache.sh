#!/usr/bin/env bash
# data-bundles/fetch/fetch-frontend-npm-cache.sh
# Resolve the Phase 9 frontend package lock and populate an npm cache for
# offline/internal installs. Uses npm as the first blessed validation path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_ROOT="${1:-${ROOT_DIR}/data-bundles/sources}"
if [[ "${OUTPUT_ROOT}" != /* ]]; then
    OUTPUT_ROOT="${ROOT_DIR}/${OUTPUT_ROOT}"
fi
mkdir -p "${OUTPUT_ROOT}"
OUTPUT_ROOT="$(cd "${OUTPUT_ROOT}" && pwd)"

FRONTEND_REQ="${ROOT_DIR}/requirements/frontend"
FRONTEND_ROOT="${OUTPUT_ROOT}/frontend-npm/node22"
LOG_DIR="${FRONTEND_NPM_LOG_DIR:-${ROOT_DIR}/artifacts/frontend-npm-fetch}"
LOG_FILE="${LOG_DIR}/frontend-npm-fetch.log"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

mkdir -p "${FRONTEND_ROOT}" "${LOG_DIR}"

restore_host_ownership() {
    local path="$1"
    [[ -e "${path}" ]] || return 0
    docker run --rm \
        -v "${path}:/target" \
        node:22-bookworm-slim \
        sh -c "chown -R ${HOST_UID}:${HOST_GID} /target" >/dev/null 2>&1 || true
}

restore_host_ownership "${FRONTEND_ROOT}"
restore_host_ownership "${FRONTEND_REQ}"

printf '==> Resolving frontend npm dependencies (node:22-bookworm-slim)\n'
printf '==> Frontend npm fetch log: %s\n' "${LOG_FILE}"

set +e
docker run --rm -i \
    -v "${FRONTEND_REQ}:/src" \
    -v "${FRONTEND_ROOT}:/out" \
    node:22-bookworm-slim \
    bash -s 2>&1 <<'SHEOF' | tee "${LOG_FILE}"
set -euo pipefail

rm -rf /tmp/frontend-work
mkdir -p /tmp/frontend-work /out/npm-cache /out/package
cp /src/package.json /tmp/frontend-work/package.json

cd /tmp/frontend-work
npm install --package-lock-only --ignore-scripts --cache /out/npm-cache
cp package-lock.json /src/package-lock.json
cp package.json package-lock.json /out/package/

npm ci --ignore-scripts --cache /out/npm-cache
npm cache verify --cache /out/npm-cache

node <<'NODEEOF'
const fs = require("fs");
const crypto = require("crypto");
const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));
const rootPkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
const packages = Object.entries(lock.packages || {})
  .filter(([path]) => path.startsWith("node_modules/"))
  .map(([path, meta]) => ({
    name: path.slice("node_modules/".length),
    version: meta.version || "",
    resolved: meta.resolved || "",
    integrity: meta.integrity || "",
    dev: Boolean(meta.dev),
    optional: Boolean(meta.optional)
  }))
  .sort((a, b) => a.name.localeCompare(b.name));
const digest = crypto
  .createHash("sha256")
  .update(fs.readFileSync("package-lock.json"))
  .digest("hex");
const manifest = {
  schema_version: "1.0.0",
  node: process.version,
  package_manager: "npm",
  lockfile: "package-lock.json",
  lockfile_sha256: digest,
  package_count: packages.length,
  generated_at: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  groups: rootPkg["x-spt-package-groups"] || {},
  packages
};
fs.writeFileSync("/out/frontend-npm-manifest.json", JSON.stringify(manifest, null, 2) + "\n");
console.log(`frontend npm packages resolved: ${packages.length}`);
NODEEOF

cd /out
find npm-cache package -type f -print | sort | xargs sha256sum > SHA256SUMS
sha256sum frontend-npm-manifest.json package/package-lock.json package/package.json >> SHA256SUMS
SHEOF
docker_rc=${PIPESTATUS[0]}
set -e

restore_host_ownership "${FRONTEND_ROOT}"
restore_host_ownership "${FRONTEND_REQ}"

if (( docker_rc != 0 )); then
    printf 'ERROR: frontend npm fetch failed; see %s\n' "${LOG_FILE}" >&2
    printf '       Last error context:\n' >&2
    tail -n 40 "${LOG_FILE}" >&2 || true
    exit "${docker_rc}"
fi

printf '==> Frontend npm cache written to %s\n' "${FRONTEND_ROOT}"
