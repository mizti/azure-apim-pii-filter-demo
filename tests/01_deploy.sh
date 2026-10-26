#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <env-name> <location> <publisher-email>"
  exit 1
fi

ENV_NAME="$1"
LOCATION="$2"
PUBLISHER_EMAIL="$3"

environments="$(azd env list --output json)"
if jq -e --arg name "$ENV_NAME" 'any(.[]; .Name == $name)' <<< "$environments" >/dev/null; then
  azd env select "$ENV_NAME"
else
  azd env new "$ENV_NAME" --no-prompt
fi
azd env set AZURE_SUBSCRIPTION_ID "$(az account show --query id --output tsv)"
azd env set AZURE_LOCATION "$LOCATION"
azd env set PUBLISHER_EMAIL "$PUBLISHER_EMAIL"
azd env set AZURE_PRINCIPAL_ID "$(az ad signed-in-user show --query id --output tsv)"

az provider register --namespace Microsoft.App --wait
azd up --no-prompt

echo "APIM, Decision-1, and the customer support backend are deployed via azd."
