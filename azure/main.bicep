targetScope = 'resourceGroup'

@description('Prefijo de las tres VM y su red.')
@minLength(3)
@maxLength(12)
param prefix string = 'practico5'
param location string = resourceGroup().location
@description('Usuario Linux de las tres VM; no es una identidad de Azure.')
param adminUsername string = 'azureuser'
@description('Contenido de la llave PUBLICA SSH. Nunca usar la privada.')
@minLength(20)
param sshPublicKey string
@description('Comprobar disponibilidad y cuota en la suscripcion antes de crear.')
param vmSize string = 'Standard_B1s'

module security 'modules/seguridad.bicep' = {
  name: 'seguridad'
  params: {
    prefix: prefix
    location: location
  }
}
module network 'modules/red.bicep' = {
  name: 'red'
  params: {
    prefix: prefix
    location: location
    nsgId: security.outputs.nsgId
  }
}
// Tres servidores privados. Bastion/VPN se configura aparte si se requiere acceso.
module servers 'modules/servidor.bicep' = [for i in range(0, 3): {
  name: 'servidor-${i + 1}'
  params: {
    vmName: '${prefix}-vm-${i + 1}'
    location: location
    subnetId: network.outputs.subnetId
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
  }
}]
output virtualMachines array = [for i in range(0, 3): {
  id: servers[i].outputs.vmId
  privateIp: servers[i].outputs.privateIp
}]
