# Azure APIM + Decision-1 Architecture

## Purpose

Screen customer support messages for PII at the API gateway before forwarding
approved messages to a business API. Presidio and its wrapper Function are removed.

## Request Flow

1. The client calls `POST /customer-support/messages` on APIM.
2. APIM validates JSON and extracts a non-empty string `text`.
3. If the query contains the `no-pii-filter` key, APIM skips steps 3–6 and
   forwards the validated input in step 7. The value is ignored, including `false`.
   Otherwise APIM sends `state.text` and the Japanese classification instructions/criteria to
   the Foundry Decision API: `/providers/microsoft/v1/systemone`.
4. The APIM system-assigned managed identity authenticates to
   `https://cognitiveservices.azure.com`. No model API key is stored in APIM.
5. A `choice` of `pii` returns `400` without calling the backend.
6. Only an answer with `type=choice` and `choice=no_pii` is allowed through.
7. APIM rewrites the request to `POST /api/customer-support/messages` and
   forwards a normalized JSON object containing only `text`, without query parameters.
8. The backend validates the input and returns an acceptance response. It does
   not perform PII detection or make an outbound model call.

Invalid client JSON or a missing, blank, or non-string `text` produces `400`.
Decision API non-200 responses, network errors, malformed responses, unsupported
answer types, unknown labels, and policy execution errors produce `502`.
Gateway errors are traced without recording the submitted text or access token.
There is no fallback that accepts a request when classification fails.
The explicit query bypass does not call Decision-1; input validation and request
normalization still apply.

## Resources and Deployment

- `infra/main.bicep`: subscription deployment, resource group, all modules and azd outputs.
- `infra/decision1.bicep`: AIServices account, Decision-1 v1, developer inference role.
- `infra/apim.bicep`: Developer SKU APIM, system identity, inference role scoped
  to the Foundry account, API operation, named values and policy.
- `infra/policies/customer-support.xml`: input validation, model request,
  classification gate and backend rewrite.
- `infra/functions-stack.bicep`: one Flex Consumption Function, plan, storage,
  Application Insights and Log Analytics.
- `infra/backend-network.bicep`: a dedicated VNet, a Flex Consumption integration
  subnet delegated to `Microsoft.App/environments`, and Blob/Queue/Table private
  endpoints with private DNS zones and VNet links.
- `azure.yaml`: only the `demo-api` Function service; `azd up` provisions the
  complete infrastructure and deploys its code.

The model uses DataZoneStandard with capacity 60 by default (observed:
60 RPM / 60,000 TPM). An account in Japan East does not guarantee processing
only in Japan East; the DataZoneStandard data-zone rules apply.
The model account disables local/key authentication.

The backend storage account disables public network access and shared keys.
The Function uses VNet integration to reach storage through its private endpoints.
This replaces the original no-VNet backend design because the deployment
subscription's governance policy enforces disabled storage public access.
No policy exemption or public-access workaround is used.
APIM and Foundry remain on public HTTPS endpoints with managed identity.

The earlier standalone test resource group is not imported into the azd
environment and is not deleted by `azd down`.

## Security and Scope

- The sample exposes anonymous APIM and Function APIs; the backend VNet integration
  protects outbound storage connectivity, not inbound Function access.
- Direct calls to the Function bypass PII screening. Production deployments
  must restrict backend ingress and authenticate gateway-to-backend requests.
- The demo's unauthenticated `no-pii-filter` query parameter also bypasses screening.
  Remove this branch or enforce authorization before using it in production.
- PII screening targets only `text`; other fields are discarded rather than
  forwarded without inspection.
- Classification is model-based, not a production DLP guarantee. Evaluate false
  positives, false negatives, prompt injection, Japanese text and latency using
  representative labeled data.
- The gateway uses the selected label, not a custom confidence threshold.
- Unlike Presidio, Decision-1 does not return matched entity spans or reasons.
- The previous second screening layer in the backend has intentionally been removed.
