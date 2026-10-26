# Tres servidores con Bicep (Azure)

Esta parte requiere suscripcion Azure; las credenciales AWS no sirven aqui.
main.bicep coordina modulos de red, seguridad y un modulo servidor repetido
exactamente tres veces. No hay dependencias con el stack CloudFormation.

Se crean tres VM Linux privadas, tres NIC, discos y una VNet/subred/NSG.
No se crean IP publicas, Bastion ni NAT. Para conectarse desde Windows se
requiere VPN o Bastion aparte. El portal permite comprobar el aprovisionamiento;
la web de prueba en 8080 solo es accesible desde la red privada.
No usar claves privadas o contrasenas en el repositorio.

## Validar y desplegar (desde esta carpeta)

Con Azure CLI instalado y una llave publica SSH existente:

```powershell
az login
az account show
az bicep version
New-Item -ItemType Directory -Path ../.build -Force | Out-Null
az bicep build --file main.bicep --outfile ../.build/main.azure.json
$sshKey = (Get-Content "$env:USERPROFILE/.ssh/id_ed25519.pub" -Raw).Trim()
az group create --name rg-practico5 --location eastus
az deployment group what-if --resource-group rg-practico5 --template-file main.bicep --parameters sshPublicKey="$sshKey"
az deployment group create --name practico5 --resource-group rg-practico5 --template-file main.bicep --parameters sshPublicKey="$sshKey"
az vm list --resource-group rg-practico5 --output table
```

Si no tienen llave, generar una local con ssh-keygen sin sobrescribir ninguna
existente; usar exclusivamente el archivo .pub como parametro.
Comprobar suscripcion, region, cuota para tres VM y disponibilidad de Standard_B1s.
Los discos administrados tienen cifrado en reposo de Azure por defecto.

No se compilo ni se desplego Bicep en esta preparacion: faltan Azure CLI/Bicep y
acceso a una suscripcion. what-if es una comprobacion previa, no crea las VM.
La creacion del grupo SI cambia Azure. Revisar what-if antes de create.

Para limpieza, solo despues de revisar que este grupo contiene unicamente el
laboratorio: az group delete --name rg-practico5. Esto borra sus tres VM y discos.
