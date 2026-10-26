targetScope = 'resourceGroup'

metadata description = 'Microsoft-Decision-1 deployment for standalone tests or APIM integration.'

@description('Region supporting the selected Decision-1 deployment SKU.')
param location string = resourceGroup().location

@description('Globally unique Foundry resource and custom subdomain name.')
param foundryName string = 'foundry-decision1-${take(uniqueString(resourceGroup().id), 10)}'

@description('Decision-1 deployment name used as the inference request model value.')
param deploymentName string = 'decision-1'

@description('Deployment SKU. Verify model availability and quota in the target region before deploying.')
@allowed([
  'DataZoneStandard'
  'GlobalStandard'
])
param deploymentSku string = 'DataZoneStandard'

@description('Decision-1 capacity units. Check the returned deployment rateLimits for effective RPM and TPM.')
@minValue(1)
param capacity int = 60

@description('Object ID of the identity allowed to invoke the Decision API.')
param principalId string

@description('Type of the identity receiving the inference role.')
@allowed([
  'User'
  'ServicePrincipal'
])
param principalType string = 'User'

@description('Tags applied to the Foundry resource.')
param tags object = {}

var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource decisionFoundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryName
  location: location
  tags: union(tags, {
    workload: 'apim-decision1-demo'
    managedBy: 'bicep'
  })
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: foundryName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource decisionDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: decisionFoundry
  name: deploymentName
  sku: {
    name: deploymentSku
    capacity: capacity
  }
  properties: {
    model: {
      format: 'Microsoft'
      name: 'Microsoft-Decision-1'
      version: '1'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource inferenceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(decisionFoundry.id, principalId, cognitiveServicesUserRoleId)
  scope: decisionFoundry
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
  }
}

output decision1AccountName string = decisionFoundry.name
output decision1ResourceId string = decisionFoundry.id
output decision1Endpoint string = 'https://${decisionFoundry.name}.services.ai.azure.com'
output decision1DeploymentName string = decisionDeployment.name
