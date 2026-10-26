> Actualizacion: para la consigna de Git sync AUTOMATICO, seguir [GIT_SYNC.md](GIT_SYNC.md).
> El flujo manual de este README corresponde al despliegue inicial ya realizado.

# Practico 5: CloudFormation anidado, Git colaborativo y Bicep

Repositorio: https://github.com/Willxd123/cloudformation-mod2.git

## Que entrega este proyecto

1. CloudFormation organizado en un stack raiz y tres stacks hijos.
2. Dos servidores EC2 de prueba, separados de Terraform/Pulumi: frontend Nginx
   publico y backend Python privado. Se comprueba el backend mediante /backend/.
3. Flujo entre dos personas usando Git y change sets sobre el MISMO stack.
4. Codigo Bicep separado para aprovisionar tres VM privadas en Azure.

Este ejemplo no despliega las aplicaciones Django/Angular del practico anterior,
ni migra las EC2 existentes. Los nombres backend/frontend describen el rol de los
servidores de demostracion. No contiene contrasenas ni necesita llaves AWS en Git.
El ZIP de ejemplo anterior ya estaba eliminado al comenzar; no se restauro.

## Estructura

```text
bootstrap.yaml                 Bucket privado donde publicar templates
main.yaml                      Stack raiz; punto de entrada
  templates/red.yaml           VPC, subred publica/privada, rutas
  templates/seguridad.yaml     Grupos frontend/backend, sin SSH abierto
  templates/servidores.yaml    Dos EC2, scripts de inicio y etiquetas
scripts/stack.ps1               Package, change sets, ejecucion y consultas
scripts/check_templates.py     Comprobaciones locales de contratos y controles
policies/security.guard        Reglas para cfn-guard
azure/                         Tres servidores Bicep en Azure (otro despliegue)
```

CloudFormation NO combina todos los YAML como Terraform combina los .tf.
main.yaml declara AWS::CloudFormation::Stack y conecta sus parametros/salidas.
Las rutas TemplateURL locales solo sirven como entrada de cloudformation package;
no subir main.yaml sin empaquetar directamente a Create Stack.

## Arquitectura AWS

```text
Internet -> frontend Nginx:80 (subred publica)
                    |
                    +-- /backend/ -> backend Python:8080 (subred privada)
```

El backend no tiene IP publica, NAT ni dependencia de descargas. Usa Python 3 de
Ubuntu. El frontend necesita Internet para instalar Nginx. No se abre SSH en
ninguno de los dos servidores. HTTPS y acceso administrativo privado se dejan
fuera de este laboratorio; no ingresar credenciales ni datos sensibles en HTTP.
Discos cifrados e IMDSv2 obligatorio. No hay alta disponibilidad ni backup de datos.
La AMI por defecto es la Ubuntu 24.04 que ya uso el grupo en us-east-1; comprobar
que siga disponible. Si se cambia region, elegir una AMI Ubuntu 24.04 amd64 valida
antes de desplegar. Conservar la AMI fija durante la demostracion colaborativa.

## Diferencia entre los practicos

- Practico 4: template, creacion de servidores y revision/ejecucion de change set.
- Practico 5: refactorizacion en stacks anidados y dos personas actualizando el
  mismo stack desde el mismo repositorio; tres servidores con Bicep en Azure.

Aqui Git sincroniza el CODIGO. CloudFormation administra el estado del stack en
AWS; no se utiliza terraform.tfstate ni un archivo .tflock para este proyecto.
La integracion automatica se prepara con deployment.yaml y main.git-sync.yaml.
Falta conectarla en AWS siguiendo GIT_SYNC.md; crear estos archivos no activa
la sincronizacion. No mezclar actualizaciones manuales y Git sync una vez conectado.

## Requisitos

- AWS CLI v2 y credenciales de una identidad autorizada; perfil default por defecto.
- Git, PowerShell y Python con PyYAML para las comprobaciones locales opcionales.
- Permisos para CloudFormation (stacks raiz/hijos y change sets), EC2/redes,
  lectura/escritura de los templates S3 y configuracion del bucket de bootstrap.
- AMI y cuota para dos t3.micro disponibles en us-east-1.
- Ambos integrantes usan misma cuenta, region, StackName y bucket de templates.

No crear claves del usuario root ni subir ~/.aws, access keys o .env al repositorio.
No se crean roles IAM de aplicaciones: los servidores de prueba no llaman APIs AWS.
El script usa los permisos del perfil que lo ejecuta. Cada equipo puede usar un
perfil local distinto; el perfil no tiene que llamarse igual en las dos maquinas.

## Validacion local

```powershell
python scripts/check_templates.py
```

Este script revisa YAML, contratos entre padre/hijos y controles basicos. NO es
un validador completo del esquema de AWS. La .cfnlintrc.yaml selecciona los cinco
templates AWS; no analiza el cloud-init YAML de Azure como CloudFormation.
Para validacion completa se propone cfn-lint 1.57.2 en una .venv local:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\cfn-lint.exe
```

La instalacion aun no se ejecuto; requiere acceso a PyPI.
Para seguridad, con cfn-guard disponible:

```powershell
cfn-guard validate --rules policies/security.guard --data templates/servidores.yaml
cfn-guard validate --rules policies/security.guard --data bootstrap.yaml
```

La ejecucion de estos validadores completos queda pendiente si no estan instalados.
Azure CLI/Bicep no estaban disponibles: ver azure/README.md para compilar y what-if.

## Primer despliegue AWS: hacer una sola vez por el equipo

Desde la raiz de ESTE repositorio:

```powershell
$env:AWS_PROFILE = 'default'
aws sts get-caller-identity --profile default
aws ec2 describe-images --image-ids ami-02a9cdd4e98bc3c78 --region us-east-1 --query 'Images[].{ID:ImageId,Estado:State,Arquitectura:Architecture,Nombre:Name}' --profile default
```

Confirmar la cuenta y la imagen antes de crear. El siguiente comando SI crea el
bucket de templates con CloudFormation; no crea EC2:

```powershell
.\scripts\stack.ps1 -Action Bootstrap
```

Copiar el valor BucketName mostrado. Usarlo en ambos equipos; no crear otro stack
ni otro bucket para el segundo integrante. No usar el bucket tfstate para esto.
En los siguientes ejemplos reemplazar NOMBRE-BUCKET por ese nombre real.

```powershell
.\scripts\stack.ps1 -Action Validate
.\scripts\stack.ps1 -Action Plan -TemplatesBucket 'NOMBRE-BUCKET' -ChangeSetName 'inicial'
```

Plan publica templates hijos privados en S3 y genera .build/main.packaged.yaml;
crea un change set CREATE con --include-nested-stacks, pero NO lo ejecuta.
El stack puede aparecer en REVIEW_IN_PROGRESS: es normal, no hay EC2 aun.
No borrar ni versionar a mano el YAML empaquetado: es un artefacto derivado.

Revisar en CloudFormation el stack practico5-compartido -> Change sets -> inicial.
Inspeccionar tambien los change sets hijos: el padre muestra cambios de stacks,
y los hijos muestran las EC2/redes. No basta ver solo el resumen del padre.
Si todo corresponde a recursos NUEVOS de este laboratorio:

```powershell
.\scripts\stack.ps1 -Action Execute -ChangeSetName 'inicial'
.\scripts\stack.ps1 -Action Status
```

Execute crea los servidores; es una operacion diferente de Plan. Esperar
CREATE_COMPLETE del stack y los hijos. Los scripts cloud-init pueden continuar
instalando despues de que CloudFormation termina: no hay CreationPolicy/cfn-signal.
Probar FrontendUrl y FrontendUrl/backend/ despues de unos minutos. No afirmar que
la aplicacion esta lista solo por CREATE_COMPLETE.
Si falla, revisar los eventos del stack raiz y el hijo que fallo. Los eventos de
validacion previa pueden consultarse con describe-events; los eventos de recursos
del despliegue, con describe-stack-events. No repetir Execute sin diagnosticar.

## Defensa entre dos personas sobre el mismo stack

No trabajan dos stacks separados. Ambas maquinas usan practico5-compartido y
us-east-1, y la misma rama main. No ejecutar cambios simultaneos: CloudFormation
serializa operaciones del stack y no combina templates de ramas diferentes.

### Preparacion compartida

```powershell
git clone https://github.com/Willxd123/cloudformation-mod2.git
cd cloudformation-mod2
git switch main
git pull --ff-only origin main
```

Si el integrante ya clono el repo, usar solo switch y pull. Verificar que todos
los archivos esten subidos antes de clonar. No hacer git reset --hard para
resolver diferencias; conservar los cambios de ambos y resolver conflictos.

### Integrante A

1. Con stack inicial ya funcionando, cambiar en main.yaml SOLO el Default de
   BackendRevision de inicial a integrante-a. Conservar todos los demas valores.
2. Compartir el codigo:

```powershell
git add main.yaml
git commit -m "Agrega revision del integrante A al backend"
git push origin main
.\scripts\stack.ps1 -Action Plan -TemplatesBucket 'NOMBRE-BUCKET' -ChangeSetName 'cambio-a'
```

3. Revisar change sets raiz/hijo: cambio de etiqueta Revision del backend,
   sin reemplazos de EC2. Despues:

```powershell
.\scripts\stack.ps1 -Action Execute -ChangeSetName 'cambio-a'
```

### Integrante B

1. Esperar a que A termine su actualizacion, sincronizar y comprobar que el
   Default BackendRevision ya contiene integrante-a.

```powershell
git pull --ff-only origin main
```

2. Cambiar SOLO el Default de FrontendRevision a integrante-b. No quitar A.

```powershell
git add main.yaml
git commit -m "Agrega revision del integrante B al frontend"
git push origin main
.\scripts\stack.ps1 -Action Plan -TemplatesBucket 'NOMBRE-BUCKET' -ChangeSetName 'cambio-b'
```

3. Revisar que solo cambia Revision del frontend; no aceptar reemplazos.

```powershell
.\scripts\stack.ps1 -Action Execute -ChangeSetName 'cambio-b'
```

4. A hace git pull. Mostrar EC2 backend con Revision=integrante-a y frontend con
   Revision=integrante-b. Ambos cambios deben permanecer y el stack debe estar en
   UPDATE_COMPLETE. No aplicar desde codigo viejo: puede revertir etiquetas.

Los change sets son fotografias del cambio propuesto; crear uno nuevo despues
que otro integrante actualice el stack, no ejecutar planes viejos.

## Guion corto para explicar

"main.yaml es el punto de entrada. Crea tres stacks hijos y conecta sus salidas:
la red entrega VPC/subredes, seguridad entrega los grupos y servidores consume
esos identificadores. Package publica templates hijos en S3. El change set nos
permite revisar antes de ejecutar. A actualiza backend, B hace pull y actualiza
frontend sobre el mismo stack. Git guarda el codigo, CloudFormation el estado."

## Bicep: tres servidores

Ver azure/README.md y azure/main.bicep. Requiere suscripcion Azure y su propio
inicio de sesion, no AWS. No se crean recursos Azure desde los scripts AWS.

## Limpieza

Borrar practico5-compartido desde CloudFormation elimina sus stacks hijos y
servidores. Verificar el nombre antes de borrar. No usar Terraform/Pulumi para
eliminar estos recursos ni asociar las EC2 anteriores a este stack.
El bootstrap es independiente y RETIENE su bucket incluso si se borra su stack.
Para retirarlo definitivamente hay que limpiar todos los objetos/versiones y
revisar su eliminacion aparte. No toca el bucket que guarda el estado Terraform.

## Estado de esta preparacion

Comprobados localmente: lectura YAML, contratos de stacks anidados, controles
basicos de discos/IMDS/bucket, sintaxis Bash embebida y sintaxis PowerShell.
Pendientes: cfn-lint, cfn-guard, validacion AWS/creacion de change sets y ejecucion.
La sesion de esta herramienta no pudo conectar con STS; no se crearon recursos,
no se hizo commit ni push. Bicep queda pendiente de compilacion y validacion Azure.

## Referencias

- https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html
- https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/change-sets-for-nested-stacks.html
- https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/git-sync.html
- https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview
