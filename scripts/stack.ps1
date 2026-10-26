param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Validate', 'Bootstrap', 'Package', 'GitSync', 'Plan', 'Changes', 'Execute', 'Status')]
    [string]$Action,
    [string]$StackName = 'practico5-compartido',
    [string]$BootstrapStack = 'practico5-templates',
    [string]$TemplatesBucket,
    [string]$ChangeSetName,
    [string]$Region = 'us-east-1',
    [string]$Profile = 'default'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root '.build'
$packaged = Join-Path $build 'main.packaged.yaml'
$command = Get-Command aws.exe -ErrorAction SilentlyContinue
if ($command) { $awsExe = $command.Source }
else { $awsExe = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe' }
if (-not (Test-Path -LiteralPath $awsExe)) { throw 'Instala AWS CLI v2.' }
function Invoke-Aws {
    param([string[]]$Arguments)
    & $awsExe @Arguments --region $Region --profile $Profile --no-cli-pager
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI fallo: $($Arguments -join ' ')" }
}
function Publish-Templates {
    if (-not $TemplatesBucket) { throw 'Falta -TemplatesBucket con el bucket del bootstrap.' }
    New-Item -ItemType Directory -Path $build -Force | Out-Null
    Invoke-Aws -Arguments @('cloudformation', 'package', '--template-file', (Join-Path $root 'main.yaml'), '--s3-bucket', $TemplatesBucket, '--s3-prefix', 'nested', '--output-template-file', $packaged)
}
# Al ejecutar este script se realizan las acciones indicadas. Nunca llama a
# execute-change-set desde Plan: crear el plan y ejecutarlo son pasos separados.
switch ($Action) {
    'Validate' {
        # Validacion de sintaxis del servicio. No sustituye cfn-lint/cfn-guard.
        $templates = @((Join-Path $root 'bootstrap.yaml'), (Join-Path $root 'main.yaml'))
        $templates += @(Get-ChildItem (Join-Path $root 'templates') -Filter '*.yaml' | ForEach-Object FullName)
        foreach ($template in $templates) {
            Write-Host "Validando $template"
            Invoke-Aws -Arguments @('cloudformation', 'validate-template', '--template-body', "file://$template")
        }
    }
    'Bootstrap' {
        # Crea solo el bucket para templates; no crea EC2.
        Invoke-Aws -Arguments @('cloudformation', 'deploy', '--stack-name', $BootstrapStack, '--template-file', (Join-Path $root 'bootstrap.yaml'), '--no-fail-on-empty-changeset')
        Invoke-Aws -Arguments @('cloudformation', 'describe-stacks', '--stack-name', $BootstrapStack, '--query', 'Stacks[0].Outputs')
    }
    'Package' { Publish-Templates }
    'GitSync' {
        # Publica hijos y prepara el template que Git sync leera desde GitHub.
        # NO actualiza el stack ni sobrescribe las revisiones de deployment.yaml.
        Publish-Templates
        Copy-Item -LiteralPath $packaged -Destination (Join-Path $root 'main.git-sync.yaml') -Force
        Write-Host 'Listo main.git-sync.yaml. Revisar diff y subirlo junto con los templates.'
        Write-Host 'Conservar los parametros actuales de deployment.yaml; Git sync los aplica.'
    }
    'Plan' {
        Publish-Templates
        if (-not $ChangeSetName) { $ChangeSetName = 'revision-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
        $ErrorActionPreference = 'Continue'
        try {
            $raw = & $awsExe cloudformation describe-stacks --stack-name $StackName --region $Region --profile $Profile --output json --no-cli-pager 2>&1
            $stackExitCode = $LASTEXITCODE
        } finally { $ErrorActionPreference = 'Stop' }
        if ($stackExitCode -ne 0) {
            if (($raw | Out-String) -notmatch 'does not exist') { throw ($raw | Out-String) }
            $changeType = 'CREATE'
        } else {
            $stack = ($raw | Out-String | ConvertFrom-Json).Stacks[0]
            if ($stack.StackStatus -match 'IN_PROGRESS$' -and $stack.StackStatus -ne 'REVIEW_IN_PROGRESS') {
                throw "Stack ocupado: $($stack.StackStatus). Espera antes de crear otro change set."
            }
            $changeType = if ($stack.StackStatus -eq 'REVIEW_IN_PROGRESS') { 'CREATE' } else { 'UPDATE' }
        }
        Invoke-Aws -Arguments @('cloudformation', 'create-change-set', '--stack-name', $StackName, '--change-set-name', $ChangeSetName, '--change-set-type', $changeType, '--include-nested-stacks', '--capabilities', 'CAPABILITY_NAMED_IAM', 'CAPABILITY_AUTO_EXPAND', '--template-body', "file://$packaged", '--description', 'Revision colaborativa del stack raiz y sus hijos')
        & $awsExe cloudformation wait change-set-create-complete --stack-name $StackName --change-set-name $ChangeSetName --region $Region --profile $Profile
        $waitExitCode = $LASTEXITCODE
        Invoke-Aws -Arguments @('cloudformation', 'describe-change-set', '--stack-name', $StackName, '--change-set-name', $ChangeSetName)
        if ($waitExitCode -ne 0) { throw 'El change set no esta listo. Revisar StatusReason (puede no haber cambios).' }
        Write-Host "Plan listo: $ChangeSetName. Revisar tambien los cambios hijos en CloudFormation."
        Write-Host "Para ejecutar: .\scripts\stack.ps1 -Action Execute -StackName $StackName -ChangeSetName $ChangeSetName -Region $Region -Profile $Profile"
    }
    'Changes' {
        if (-not $ChangeSetName) { throw 'Falta -ChangeSetName.' }
        Invoke-Aws -Arguments @('cloudformation', 'describe-change-set', '--stack-name', $StackName, '--change-set-name', $ChangeSetName)
    }
    'Execute' {
        if (-not $ChangeSetName) { throw 'Falta -ChangeSetName revisado.' }
        $status = Invoke-Aws -Arguments @('cloudformation', 'describe-stacks', '--stack-name', $StackName, '--query', 'Stacks[0].StackStatus', '--output', 'text')
        Invoke-Aws -Arguments @('cloudformation', 'execute-change-set', '--stack-name', $StackName, '--change-set-name', $ChangeSetName)
        $waiter = if ($status -eq 'REVIEW_IN_PROGRESS') { 'stack-create-complete' } else { 'stack-update-complete' }
        Invoke-Aws -Arguments @('cloudformation', 'wait', $waiter, '--stack-name', $StackName)
        Invoke-Aws -Arguments @('cloudformation', 'describe-stacks', '--stack-name', $StackName, '--query', 'Stacks[0].Outputs')
    }
    'Status' {
        Invoke-Aws -Arguments @('cloudformation', 'describe-stacks', '--stack-name', $StackName, '--query', 'Stacks[0].{Estado:StackStatus,Salidas:Outputs}')
    }
}
