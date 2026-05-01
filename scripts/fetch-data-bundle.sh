#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
DATA_DIR="${DATA_DIR:-data-bundles/sources}"

make data-fetch TAG="${TAG}" DATA_DIR="${DATA_DIR}"
