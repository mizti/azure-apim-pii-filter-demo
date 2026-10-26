#!/usr/bin/env bash
set -euo pipefail

command -v az >/dev/null
command -v azd >/dev/null
command -v curl >/dev/null
command -v jq >/dev/null

az account show >/dev/null
azd auth login --check-status >/dev/null

echo "Prerequisites look good."
