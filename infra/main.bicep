targetScope = 'subscription'

@minLength(1)
@maxLength(32)
@description('Environment name used to generate resource names.')
param environmentName string

@description('Primary resource location. Verify Decision-1 availability before deploying.')
param location string

@description('Optional resource group name override.')
param resourceGroupName string = ''

@description('Email address used as the API Management publisher contact.')
param publisherEmail string

@description('Object ID of the developer allowed to run direct Decision-1 tests.')
param principalId string

@description('Decision-1 capacity units.')
@minValue(1)
param decision1Capacity int = 60

var tags = {
  'azd-env-name': environmentName
}
var resourceToken = take(uniqueString(subscription().id, environmentName, location), 8)

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : 'rg-${environmentName}'
  location: location
  tags: tags
}

module functionsStack './functions-stack.bicep' = {
  scope: rg
  name: 'functions-stack'
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

module decision1 './decision1.bicep' = {
  scope: rg
  name: 'decision1'
  params: {
    location: location
    principalId: principalId
    capacity: decision1Capacity
    tags: tags
  }
}

module apim './apim.bicep' = {
  scope: rg
  name: 'apim'
  params: {
    apimName: 'apim-${environmentName}-${resourceToken}'
    location: location
    publisherEmail: publisherEmail
    demoFunctionBaseUrl: functionsStack.outputs.demoFunctionBaseUrl
    decision1AccountName: decision1.outputs.decision1AccountName
    decision1Endpoint: decision1.outputs.decision1Endpoint
    decision1DeploymentName: decision1.outputs.decision1DeploymentName
    tags: tags
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name
output RESOURCE_GROUP_NAME string = rg.name
output DEMO_FUNCTION_APP_NAME string = functionsStack.outputs.demoFunctionAppName
output DEMO_FUNCTION_BASE_URL string = functionsStack.outputs.demoFunctionBaseUrl
output DECISION1_ACCOUNT_NAME string = decision1.outputs.decision1AccountName
output DECISION1_ENDPOINT string = decision1.outputs.decision1Endpoint
output DECISION1_DEPLOYMENT string = decision1.outputs.decision1DeploymentName
output APIM_NAME string = apim.outputs.apimName
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
