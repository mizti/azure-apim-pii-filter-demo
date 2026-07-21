targetScope = 'resourceGroup'

@description('Environment name used for naming')
param environmentName string

@description('Deployment location')
param location string = resourceGroup().location

@description('Tags to apply to resources')
param tags object = {}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

var presidioServiceName = 'presidio-api'
var demoServiceName = 'demo-api'

var presidioFunctionName = '${abbrs.webSitesFunctions}${environmentName}-presidio-${take(resourceToken, 6)}'
var demoFunctionName = '${abbrs.webSitesFunctions}${environmentName}-demo-${take(resourceToken, 6)}'

var presidioPlanName = '${abbrs.webServerFarms}${environmentName}-presidio-${take(resourceToken, 6)}'
var demoPlanName = '${abbrs.webServerFarms}${environmentName}-demo-${take(resourceToken, 6)}'

var presidioStorageName = 'stp${take(uniqueString(resourceToken, 'presidio'), 21)}'
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

resource presidioStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: presidioStorageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
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
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
  }
}

module presidioPlan './core/host/appserviceplan.bicep' = {
  name: 'presidio-plan'
  params: {
    name: presidioPlanName
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

module presidioFunction './core/host/flex-function.bicep' = {
  name: 'presidio-function'
  params: {
    name: presidioFunctionName
    location: location
    tags: union(tags, { 'azd-service-name': presidioServiceName })
    appServicePlanId: presidioPlan.outputs.id
    storageAccountName: presidioStorage.name
    applicationInsightsId: appInsights.outputs.id
    applicationInsightsConnectionString: appInsights.outputs.connectionString
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
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
    applicationInsightsId: appInsights.outputs.id
    applicationInsightsConnectionString: appInsights.outputs.connectionString
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    appSettings: {
      PRESIDIO_API_URL: '${presidioFunction.outputs.uri}/api/presidio/analyze'
      PRESIDIO_TIMEOUT_SECONDS: '10'
    }
  }
}

output PRESIDIO_FUNCTION_APP_NAME string = presidioFunction.outputs.name
output PRESIDIO_FUNCTION_BASE_URL string = presidioFunction.outputs.uri
output DEMO_FUNCTION_APP_NAME string = demoFunction.outputs.name
output DEMO_FUNCTION_BASE_URL string = demoFunction.outputs.uri
