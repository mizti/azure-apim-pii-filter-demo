#!/usr/bin/env bash
set -euo pipefail

command -v az >/dev/null
command -v azd >/dev/null

az account show >/dev/null
azd auth login --check-status >/dev/null || true

echo "Prerequisites look good."
