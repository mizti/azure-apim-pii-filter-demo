targetScope = 'resourceGroup'

@description('APIM service name.')
param apimName string

@description('Deployment location.')
param location string = resourceGroup().location

@description('Publisher email.')
param publisherEmail string

@description('Publisher display name.')
param publisherName string = 'APIM Decision-1 Demo'

@description('Public URL of the customer support backend Function App.')
param demoFunctionBaseUrl string

@description('Foundry account name in this resource group.')
param decision1AccountName string

@description('Foundry resource endpoint without an API path.')
param decision1Endpoint string

@description('Decision-1 deployment name.')
param decision1DeploymentName string

@description('Tags applied to APIM.')
param tags object = {}

var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource decisionFoundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: decision1AccountName
}

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

resource decisionInferenceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(decisionFoundry.id, apim.id, cognitiveServicesUserRoleId)
  scope: decisionFoundry
  properties: {
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
  }
}

resource customerSupportApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'customer-support-api'
  parent: apim
  properties: {
    displayName: 'Customer Support API'
    path: 'customer-support'
    protocols: [
      'https'
    ]
    serviceUrl: demoFunctionBaseUrl
    subscriptionRequired: false
  }
}

resource submitMessage 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  name: 'submit-message'
  parent: customerSupportApi
  properties: {
    displayName: 'Submit customer support message'
    method: 'POST'
    urlTemplate: '/messages'
    responses: [
      { statusCode: 200 }
      { statusCode: 400 }
      { statusCode: 502 }
    ]
  }
}

resource decisionEndpoint 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  name: 'decision1-endpoint'
  parent: apim
  properties: {
    displayName: 'decision1-endpoint'
    value: '${decision1Endpoint}/providers/microsoft/v1/systemone'
    secret: false
  }
}

resource decisionDeployment 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  name: 'decision1-deployment'
  parent: apim
  properties: {
    displayName: 'decision1-deployment'
    value: decision1DeploymentName
    secret: false
  }
}

resource customerSupportPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  name: 'policy'
  parent: customerSupportApi
  dependsOn: [
    decisionEndpoint
    decisionDeployment
    decisionInferenceRole
  ]
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/customer-support.xml')
  }
}

output apimGatewayUrl string = 'https://${apim.name}.azure-api.net'
output apimName string = apim.name
