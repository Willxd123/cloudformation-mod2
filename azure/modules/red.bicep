param prefix string
param location string
param nsgId string
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.70.0.0/16']
    }
  }
}
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: 'servidores'
  properties: {
    addressPrefix: '10.70.1.0/24'
    networkSecurityGroup: {
      id: nsgId
    }
    defaultOutboundAccess: false
  }
}
output subnetId string = subnet.id
