# Bicep Authoring Skill

Use this skill when the user asks to create, modify, review, refactor, or troubleshoot Azure Bicep infrastructure-as-code.

## Goal

Produce production-grade Bicep that is deployable, maintainable, reviewable, and consistent across environments.

Do not merely generate syntactically valid Bicep. Prioritize correct Azure resource relationships, safe defaults, explicit dependencies only where needed, modular structure, secure configuration, and clear parameters.

## Core behavior

When working on Bicep, always follow this order:

1. Understand the deployment scope and target architecture.
2. Identify required Azure resource types, dependencies, identities, networking, diagnostics, and RBAC.
3. Prefer Azure Verified Modules when they fit the requirement.
4. Use native Bicep resources when AVM would add unnecessary complexity or when the requested resource is not covered well by AVM.
5. Generate or edit Bicep using clear module boundaries.
6. Include environment-specific values through parameters, not hard-coded values.
7. Review the output for security, idempotency, maintainability, naming, and linter issues.
8. Provide deployment and validation commands when useful.

## Required questions before authoring

Ask only when the missing information materially affects the design. If reasonable defaults are possible, proceed and state assumptions.

Important missing inputs:

* Deployment scope: resource group, subscription, management group, or tenant.
* Target environment names: dev, stg, prod, sandbox, etc.
* Azure region strategy.
* Naming convention.
* Tagging requirements.
* Existing network topology.
* Public access policy.
* Private endpoint and private DNS requirements.
* Managed identity requirements.
* RBAC requirements.
* Diagnostic settings / Log Analytics workspace requirements.
* Whether to use AVM modules, native resources, or a mix.

Do not ask for information that can be safely parameterized.

## Output contract

For any new Bicep implementation, provide these files unless the user asks for a narrower output:

```
infra/
  main.bicep
  main.bicepparam
  modules/
    <resource>.bicep
  bicepconfig.json
```

For small examples, a single `main.bicep` is acceptable, but mention that production code should be split into modules when the resource graph grows.

## Bicep file structure

Use this order inside Bicep files:

1. `targetScope`
2. `metadata`
3. `@description` parameters
4. variables
5. existing resources
6. resources
7. modules
8. outputs

Every non-obvious parameter, resource, and output should have a description.

Use symbolic names that describe role, not Azure type alone.

Bad:

```bicep
resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
```

Good:

```bicep
resource appStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
```

## Parameter rules

Parameterize values that vary by environment:

* environment name
* location
* SKU/tier
* capacity
* subnet IDs
* private endpoint enablement
* diagnostics enablement
* tags
* allowed IP ranges
* role assignment principals

Do not parameterize stable implementation details without a reason.

Avoid unsafe defaults for production-impacting parameters. For example, do not default `publicNetworkAccess` to enabled unless the user explicitly wants public access.

Use `@allowed` for constrained values such as environment, SKU, redundancy, or access mode.

Use `@secure()` for secrets and credentials. Prefer Key Vault references or managed identities instead of passing secrets directly.

## Naming rules

If the repository has a naming convention, follow it exactly.

If no convention is provided, use a deterministic naming pattern:

```bicep
var workloadToken = toLower(replace(workloadName, '-', ''))
var environmentToken = toLower(environmentName)
var locationToken = toLower(replace(location, ' ', ''))
```

Resource names must respect Azure service-specific naming restrictions.

Do not invent globally unique names with random strings unless global uniqueness is required. When uniqueness is required, prefer deterministic `uniqueString()` based on stable deployment identifiers.

Example:

```bicep
var storageAccountName = take('st${workloadToken}${environmentToken}${uniqueString(subscription().id, resourceGroup().id)}', 24)
```

## Tags

Support tags as an object parameter and merge required tags with user-provided tags.

```bicep
@description('Additional tags to apply to all supported resources.')
param tags object = {}

var requiredTags = {
  workload: workloadName
  environment: environmentName
  managedBy: 'bicep'
}

var mergedTags = union(requiredTags, tags)
```

Apply tags to all taggable resources.

## Modules

Use modules to separate lifecycle or ownership boundaries, not merely to reduce line count.

Good module boundaries:

* network
* private endpoints
* monitoring
* identity
* app service
* storage
* database
* role assignments
* policy assignments

Avoid modules with excessive parameter pass-through and no abstraction value.

Module outputs should expose only stable identifiers needed by callers:

* resource ID
* principal ID
* endpoint FQDN
* subnet ID
* connection string secret URI, not secret value

## AVM usage

Prefer Azure Verified Modules when:

* the resource has complex secure defaults,
* the module is stable and actively maintained,
* the user wants standardized enterprise patterns,
* the required configuration maps cleanly to the AVM interface.

Avoid AVM when:

* it obscures a small/simple resource,
* the module interface is more complex than the requested deployment,
* the user needs low-level control not exposed by the module,
* the repository already has a strong internal module convention.

When using AVM, pin a module version. Do not use floating versions.

## Existing resources

Use `existing` for shared infrastructure that should not be created by the current deployment:

* virtual networks
* subnets
* private DNS zones
* Log Analytics workspaces
* Key Vaults
* user-assigned managed identities
* container registries

Do not recreate shared platform resources unless explicitly requested.

## Dependencies

Rely on Bicep's implicit dependency tracking through symbolic references.

Use explicit `dependsOn` only when Azure has a real ordering requirement that is not represented by property references.

Do not add blanket `dependsOn` arrays to every resource.

## Security baseline

Default to secure settings unless the user explicitly asks otherwise.

General rules:

* Prefer managed identity over secrets.
* Prefer RBAC over access keys where supported.
* Disable public network access by default for data services when private networking is available.
* Use minimum required TLS versions.
* Enable HTTPS-only settings.
* Avoid outputting secrets, keys, connection strings, or SAS tokens.
* Use Key Vault secret references rather than embedding secret values.
* Use least-privilege role assignments.
* Make destructive or broad permissions explicit in comments or explanation.

## Networking baseline

When private endpoints are requested:

* create private endpoint resources separately from the target service module unless the lifecycle is clearly coupled,
* include private DNS zone group wiring,
* support existing private DNS zones,
* do not assume the DNS zone should be created in the application resource group,
* parameterize subnet IDs,
* make public access behavior explicit.

## Diagnostics baseline

For production-like resources, include diagnostic settings when supported.

Prefer sending logs and metrics to an existing Log Analytics workspace.

Use a parameter to enable or disable diagnostics only if different environments have legitimate differences.

Do not silently omit diagnostics for critical resources such as Key Vault, Storage, App Service, SQL, Container Apps, Application Gateway, Firewall, or API Management.

## RBAC baseline

Create role assignments in a dedicated module when there are multiple assignments or cross-scope assignments.

Use stable GUID names for role assignments:

```bicep
name: guid(scopeResource.id, principalId, roleDefinitionId)
```

Do not use display names for role definitions. Use role definition IDs.

## bicepconfig.json

Include a strict linter configuration for production repositories.

Recommended baseline:

```json
{
  "analyzers": {
    "core": {
      "enabled": true,
      "rules": {
        "adminusername-should-not-be-literal": { "level": "error" },
        "artifacts-parameters": { "level": "warning" },
        "decompiler-cleanup": { "level": "warning" },
        "explicit-values-for-loc-params": { "level": "warning" },
        "max-asserts": { "level": "warning" },
        "max-outputs": { "level": "warning" },
        "max-params": { "level": "warning" },
        "max-resources": { "level": "warning" },
        "max-variables": { "level": "warning" },
        "no-hardcoded-env-urls": { "level": "error" },
        "no-unnecessary-dependson": { "level": "error" },
        "no-unused-existing-resources": { "level": "error" },
        "no-unused-params": { "level": "error" },
        "no-unused-vars": { "level": "error" },
        "outputs-should-not-contain-secrets": { "level": "error" },
        "prefer-interpolation": { "level": "error" },
        "prefer-unquoted-property-names": { "level": "error" },
        "protect-commandtoexecute-secrets": { "level": "error" },
        "secure-parameter-default": { "level": "error" },
        "secure-params-in-nested-deploy": { "level": "error" },
        "secure-secrets-in-params": { "level": "error" },
        "simplify-interpolation": { "level": "error" },
        "simplify-json-null": { "level": "error" },
        "use-parent-property": { "level": "error" },
        "use-recent-api-versions": { "level": "warning" },
        "use-resource-id-functions": { "level": "error" },
        "use-safe-access": { "level": "error" },
        "use-stable-resource-identifiers": { "level": "error" }
      }
    }
  }
}
```

If a rule is not supported by the installed Bicep version, remove or downgrade that rule rather than disabling the linter.

## Validation commands

When delivering Bicep, include relevant commands.

Resource group scope:

```bash
az bicep build --file infra/main.bicep
az deployment group validate \
  --resource-group <rg-name> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
az deployment group what-if \
  --resource-group <rg-name> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Subscription scope:

```bash
az bicep build --file infra/main.bicep
az deployment sub validate \
  --location <location> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
az deployment sub what-if \
  --location <location> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

## Review checklist

Before finalizing Bicep, check:

* Correct `targetScope`.
* Appropriate API versions.
* No unused parameters, variables, or existing resources.
* No unnecessary `dependsOn`.
* No secret outputs.
* No hard-coded environment-specific values.
* Tags applied consistently.
* Diagnostics included or explicitly justified as omitted.
* Public access explicitly enabled or disabled.
* Managed identity used where possible.
* RBAC uses stable role assignment names.
* Private endpoint DNS wiring is complete when private endpoints are used.
* Module outputs are minimal and stable.
* `.bicepparam` does not contain secrets.

## Response style

When explaining Bicep decisions:

* Be direct.
* State assumptions.
* Separate generated code from rationale.
* Point out trade-offs, especially AVM vs native resources.
* Warn about risky defaults.
* Do not claim the code is production-ready unless validation commands have been run or the user confirms the target Azure environment.

## Refactoring behavior

When refactoring existing Bicep:

1. Preserve behavior unless asked to change architecture.
2. Identify unsafe defaults and dead code.
3. Remove unnecessary `dependsOn`.
4. Extract modules only when it improves lifecycle boundaries or reuse.
5. Replace hard-coded values with parameters only when they vary by environment.
6. Keep diffs small unless a larger rewrite is justified.

## Common anti-patterns to avoid

* One huge `main.bicep` for all infrastructure.
* Splitting every resource into its own module without lifecycle reason.
* Outputting secrets or connection strings.
* Hard-coding subscription IDs, tenant IDs, object IDs, or environment names.
* Creating shared platform resources inside app deployment modules.
* Using public access by default for data services.
* Using access keys when managed identity and RBAC are available.
* Adding explicit dependencies everywhere.
* Using latest or floating module versions.
* Copying ARM JSON patterns into Bicep unnecessarily.
* Over-parameterizing implementation details.

## When uncertain

If Azure service behavior, API version support, AVM interface, or linter rule availability is uncertain, say so and verify against official Microsoft documentation or the target repository before finalizing.
