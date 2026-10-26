targetScope = 'resourceGroup'

@description('Location of the backend Function and its storage account.')
param location string

@description('Name of the dedicated backend virtual network.')
param virtualNetworkName string

@description('Resource ID of the storage account used by the Function.')
param storageAccountId string

@description('Tags applied to the backend network resources.')
param tags object = {}

var storageServices = [
  'blob'
  'queue'
  'table'
]

resource backendNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.42.0.0/24']
    }
    subnets: [
      {
        name: 'functions'
        properties: {
          addressPrefix: '10.42.0.0/26'
          delegations: [
            {
              name: 'flex-consumption'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.42.0.64/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource storageDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for service in storageServices: {
  name: 'privatelink.${service}.core.windows.net'
  location: 'global'
  tags: tags
}]

resource storageDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (service, i) in storageServices: {
  parent: storageDnsZones[i]
  name: virtualNetworkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: backendNetwork.id
    }
  }
}]

resource storageEndpoints 'Microsoft.Network/privateEndpoints@2023-09-01' = [for service in storageServices: {
  name: '${virtualNetworkName}-${service}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${backendNetwork.id}/subnets/private-endpoints'
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-${service}'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: [service]
        }
      }
    ]
  }
}]

resource storageDnsGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = [for (service, i) in storageServices: {
  parent: storageEndpoints[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: service
        properties: {
          privateDnsZoneId: storageDnsZones[i].id
        }
      }
    ]
  }
}]

output functionSubnetId string = '${backendNetwork.id}/subnets/functions'
