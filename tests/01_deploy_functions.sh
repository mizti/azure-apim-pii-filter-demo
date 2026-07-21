#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <env-name> <location>"
  exit 1
fi

ENV_NAME="$1"
LOCATION="$2"

azd env new "$ENV_NAME" --no-prompt || azd env select "$ENV_NAME"
azd env set AZURE_LOCATION "$LOCATION"

azd provision
azd deploy

echo "Function apps are provisioned and deployed via azd."
