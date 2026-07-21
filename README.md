# Azure APIM Presidio Demo

This repository demonstrates PII screening at Azure API Management before requests are forwarded to a demo REST API.

## Architecture

- API Management Developer SKU
- Presidio wrapper API on Azure Functions Flex Consumption
- Demo REST API on Azure Functions Flex Consumption
- No VNet integration

See [Architecture](docs/architecture.md) and [API interfaces](docs/api-interfaces.md).

## Deploy Functions

```bash
az login --use-device-code
azd auth login
azd env new apim-presidio-demo
azd env set AZURE_LOCATION japaneast
azd up
```

The resource group name is available after deployment:

```bash
azd env get-value RESOURCE_GROUP_NAME
```

## Deploy API Management

APIM is separate because Developer SKU provisioning can take around 40 minutes.

```bash
./tests/02_deploy_apim.sh \
    "$(azd env get-value RESOURCE_GROUP_NAME)" \
    "your-email@example.com" \
    "$(azd env get-value AZURE_LOCATION)"
```

## Test

```bash
./tests/00_prerequisites.sh
./tests/03_test_function_direct.sh "$(azd env get-value DEMO_FUNCTION_BASE_URL)"
./tests/04_test_apim.sh "https://<apim-name>.azure-api.net"
```

The expected result is HTTP `200` for a request without PII and HTTP `400` for a request containing an email address or phone number.
