#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <resource-group> <publisher-email> <location>"
  exit 1
fi

RG_NAME="$1"
PUBLISHER_EMAIL="$2"
LOCATION="$3"

DEMO_URL="$(az resource list -g "$RG_NAME" --resource-type "Microsoft.Web/sites" --query "[?contains(name, 'demo')].properties.defaultHostName | [0]" -o tsv)"
PRESIDIO_URL="$(az resource list -g "$RG_NAME" --resource-type "Microsoft.Web/sites" --query "[?contains(name, 'presidio')].properties.defaultHostName | [0]" -o tsv)"

if [[ -z "$DEMO_URL" || -z "$PRESIDIO_URL" ]]; then
  echo "Could not find demo/presidio function apps in resource group: $RG_NAME"
  exit 1
fi

TOKEN="$(echo -n "$RG_NAME" | sha1sum | cut -c1-8)"
APIM_NAME="apim-${TOKEN}"

az deployment group create \
  -g "$RG_NAME" \
  -f infra/apim.bicep \
  -p apimName="$APIM_NAME" \
     location="$LOCATION" \
     publisherEmail="$PUBLISHER_EMAIL" \
     demoFunctionBaseUrl="https://${DEMO_URL}" \
     presidioFunctionBaseUrl="https://${PRESIDIO_URL}"

echo "APIM deployment triggered/completed: $APIM_NAME"
