# Git sync automatico sobre el stack existente

## Situacion

El stack raiz practico5-compartido ya funciona en us-east-1 con tres hijos.
Esta preparacion NO conecta AWS con GitHub ni actualiza recursos por si sola.
La conexion se configura una vez por consola AWS y autoriza el repositorio GitHub.
Usar el stack PADRE, nunca Network, Security o Servers individualmente.

## Archivos vigilados

- deployment.yaml: apunta al template versionado y define parametros efectivos.
- main.git-sync.yaml: copia de la configuracion empaquetada que ya desplegamos;
  conserva los logical IDs y las URLs S3 de los templates anidados.
- templates/*.yaml y main.yaml: fuentes editables para cambios estructurales.

No seleccionar main.yaml directamente en Git sync: sus TemplateURL locales no
son URLs S3 utilizables por CloudFormation. .build/ permanece excluido de Git,
pero main.git-sync.yaml SI debe estar versionado para que AWS pueda leerlo.
Las URLs de templates no son secretos y no convierten el bucket en publico.

## Publicacion inicial del repositorio

Revisar git status y git diff antes de subir. Confirmar que no hay llaves o .env.

```powershell
git add .
git commit -m "Prepara stacks anidados y Git sync automatico"
git push origin main
```

La eliminacion del ZIP ya estaba pendiente antes de esta preparacion. Revisarla
antes del commit para decidir si incluirla; no hay que recuperarlo para desplegar.

## Conectar en AWS (una sola vez)

1. CloudFormation -> us-east-1 -> stack raiz practico5-compartido.
2. Sincronizacion Git -> Conectarse.
3. Autorizar conexion GitHub mediante AWS CodeConnections. La persona que
   autorice la instalacion necesita permisos en Willxd123/cloudformation-mod2.
4. Elegir repositorio Willxd123/cloudformation-mod2 y rama main.
5. Usar archivo de despliegue existente: deployment.yaml (desde la raiz del repo).
   Si pide template, indicar main.git-sync.yaml.
6. Configurar el rol de Git sync que ofrece la consola, revisando sus permisos.
   Git sync necesita permisos de orquestacion CloudFormation/EventBridge. El rol
   que ejecute operaciones del stack tambien necesita acceso a los templates S3
   y a los recursos EC2/red; el rol automatico de sincronizacion no equivale a
   permisos completos sobre los recursos del laboratorio.
7. Revisar la configuracion antes de guardar. El primer sync puede intentar una
   actualizacion. Conservar parametros y logical IDs; no aceptar reemplazos de VM.
8. Si AWS abre un pull request de configuracion, revisarlo y combinarlo antes
   de probar la sincronizacion.

Evidencia: repositorio, rama, ruta deployment.yaml, estado de sync y commit
aplicado visibles en la pesta?a del stack padre. Solo que los archivos existan
localmente no demuestra la conexion.

## Defensa A / B sin apply ni Execute manual

Esperar primero a que la sincronizacion inicial termine correctamente.

A cambia SOLO BackendRevision en deployment.yaml de inicial a integrante-a:

```powershell
git add deployment.yaml
git commit -m "Actualiza revision backend integrante A"
git push origin main
```

No ejecutar stack.ps1 Execute: Git sync genera/ejecuta la actualizacion. Esperar
UPDATE_COMPLETE y comprobar la etiqueta Revision del backend.

B sincroniza, conserva BackendRevision y cambia SOLO FrontendRevision a integrante-b:

```powershell
git pull --ff-only origin main
# Editar deployment.yaml y conservar la revision del integrante A.
git add deployment.yaml
git commit -m "Actualiza revision frontend integrante B"
git push origin main
```

Esperar el sync y UPDATE_COMPLETE. Mostrar backend Revision=integrante-a y
frontend Revision=integrante-b. A hace pull para quedar en el mismo commit.
Las etiquetas se editan en deployment.yaml, no en los Defaults de main.yaml,
porque los parametros del archivo de despliegue son los que Git sync aplica.

No compartir llaves AWS por Git. Una vez conectado Git sync, quien tenga permiso
para subir cambios a la rama vigilada puede provocar despliegues mediante Git;
no necesita credenciales AWS locales para hacer el push. Para revisar AWS si
necesita una identidad con permisos. Proteger main y usar PR cuando corresponda.

## Si se modifica red, seguridad o servidores hijos

Git sync no ejecuta cloudformation package ni publica automaticamente archivos
locales en S3. Antes del push, un integrante autorizado publica las nuevas versiones:

```powershell
.\scripts\stack.ps1 -Action GitSync -TemplatesBucket 'practico5-templates-templatesbucket-ooxefdxmh7vz'
git diff -- main.yaml templates main.git-sync.yaml deployment.yaml
```

Subir fuente y main.git-sync.yaml actualizado en EL MISMO commit. Las URLs por
contenido evitan sobrescribir versiones previas. Revisar impacto antes del push,
porque Git sync puede ejecutarlo automaticamente. No sobrescribir deployment.yaml
con revisiones iniciales ni perder los cambios del compa?ero.

El script GitSync publica templates, pero no actualiza el stack por CLI.
La actualizacion del stack se produce por Git sync despues del push.
Para automatizar TAMBIEN el empaquetado de templates hijos se requiere un pipeline
adicional con un rol autorizado; no se configuro ese pipeline en esta practica.

## Referencias

- https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/git-sync.html
- https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/git-sync-concepts-terms.html
- https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/git-sync-prereq.html
