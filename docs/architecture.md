# Azure APIM + Presidio Demo Architecture

## Purpose
This demo verifies that API requests do not contain personally identifiable information (PII) before they reach a business API.

The design demonstrates two independent protection layers:
- Application-level validation in the internal PII Filter Function.
- Gateway-level validation in API Management policy.

## Target Architecture
- Azure API Management (Developer SKU)
- Azure Functions (Presidio wrapper API, Flex Consumption)
- Azure Functions (Demo REST API, Flex Consumption)

Flow:
1. A client sends a request to APIM.
2. APIM policy sends the same payload to the Presidio Function.
3. If PII is detected, APIM returns `400 Bad Request`.
4. If not detected, APIM forwards the customer support message to the internal PII Filter Function.
5. The PII Filter Function also calls the Presidio Function for defense in depth.

## Components
- `presidio-api` (Function App)
  - Hosts `/api/pii-filter/analyze`.
  - Returns detection result and matching entities.
- `demo-api` (Function App)
  - Hosts the internal `/api/pii-filter/messages` endpoint.
  - Calls Presidio API and rejects requests containing PII.
- APIM
  - Public endpoint for the demo.
  - Enforces PII screening policy before forwarding to backend.

## Non-goals
- VNet integration is intentionally omitted.
- This demo is not a production-grade DLP implementation.

## Deployment Units
- `infra/main.bicep`: resource group, Function App plans, Function Apps, storage, App Insights.
- `infra/apim.bicep`: APIM service, APIs, operation policy for PII screening.

## Security Notes
- Use function authentication and APIM managed identity in production.
- Restrict direct Function App ingress in production.
- Store secrets in Key Vault for production.
