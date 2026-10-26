targetScope = 'resourceGroup'

@description('Environment name used for naming')
param environmentName string

@description('Deployment location')
param location string = resourceGroup().location

@description('Tags to apply to resources')
param tags object = {}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

var demoServiceName = 'demo-api'

var demoFunctionName = '${abbrs.webSitesFunctions}${environmentName}-support-${take(resourceToken, 6)}'

var demoPlanName = '${abbrs.webServerFarms}${environmentName}-support-${take(resourceToken, 6)}'

var demoStorageName = 'std${take(uniqueString(resourceToken, 'demo'), 21)}'

var appInsightsName = '${abbrs.insightsComponents}${environmentName}-${take(resourceToken, 6)}'
var logAnalyticsName = '${abbrs.operationalInsightsWorkspaces}${environmentName}-${take(resourceToken, 6)}'

module logAnalytics './core/monitor/loganalytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
  }
}

module appInsights './core/monitor/applicationinsights.bicep' = {
  name: 'app-insights'
  params: {
    name: appInsightsName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

resource demoStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: demoStorageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
  }
}

module demoPlan './core/host/appserviceplan.bicep' = {
  name: 'demo-plan'
  params: {
    name: demoPlanName
    location: location
    tags: tags
    kind: 'functionapp'
    reserved: true
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
  }
}

module backendNetwork './backend-network.bicep' = {
  name: 'backend-network'
  params: {
    location: location
    virtualNetworkName: 'vnet-${environmentName}-${take(resourceToken, 6)}'
    storageAccountId: demoStorage.id
    tags: tags
  }
}

module demoFunction './core/host/flex-function.bicep' = {
  name: 'demo-function'
  params: {
    name: demoFunctionName
    location: location
    tags: union(tags, { 'azd-service-name': demoServiceName })
    appServicePlanId: demoPlan.outputs.id
    storageAccountName: demoStorage.name
    // Preserve the existing storage-scoped setting across backend replacement.
    storageDiagnosticSettingName: '${abbrs.webSitesFunctions}${environmentName}-demo-${take(resourceToken, 6)}-storage-logs'
    virtualNetworkSubnetId: backendNetwork.outputs.functionSubnetId
    applicationInsightsId: appInsights.outputs.id
    applicationInsightsConnectionString: appInsights.outputs.connectionString
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

output demoFunctionAppName string = demoFunction.outputs.name
output demoFunctionBaseUrl string = demoFunction.outputs.uri
