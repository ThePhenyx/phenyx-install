#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Template  = Join-Path $ScriptDir 'docker-compose.template.yml'
$Output    = Join-Path $ScriptDir 'docker-compose.yml'

if (-not (Test-Path $Template)) {
    Write-Error "No se encuentra $Template"
    exit 1
}

Write-Host "=== Generador de docker-compose.yml para Phenyx Health ==="
Write-Host ""

$missing = @()
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { $missing += 'docker' }
else {
    try { docker compose version *> $null } catch { $missing += 'docker compose (v2)' }
    if ($LASTEXITCODE -ne 0) { $missing += 'docker compose (v2)' }
}
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { $missing += 'aws' }
if ($missing.Count -gt 0) {
    Write-Warning "Faltan las siguientes herramientas:"
    $missing | ForEach-Object { Write-Warning "  - $_" }
    Write-Warning "Puedes continuar generando el docker-compose.yml, pero las"
    Write-Warning "necesitarás antes de hacer login en ECR y arrancar el sistema."
    Write-Host ""
}

function Prompt-Default([string]$Label, [string]$Default) {
    if ($Default) {
        $val = Read-Host "$Label [$Default]"
        if ([string]::IsNullOrEmpty($val)) { return $Default } else { return $val }
    } else {
        return Read-Host $Label
    }
}

function Prompt-Secret([string]$Label) {
    $sec = Read-Host $Label -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function New-RandomSecret {
    $chars = [char[]]([char]'A'..[char]'Z' + [char]'a'..[char]'z' + [char]'0'..[char]'9')
    -join (1..48 | ForEach-Object { $chars | Get-Random })
}

Write-Host "--- Puerto del host ---"
Write-Host "Puerto con el que Docker publica el frontend en esta maquina."
Write-Host "El backend, rodaskernel y Postgres no se publican: solo son accesibles"
Write-Host "desde dentro de la red interna de Docker (el frontend proxya /api/ al backend)."
$FRONTEND_PORT = Prompt-Default "Puerto del frontend" "80"
Write-Host ""

Write-Host "--- JWT secret ---"
$jwtChoice = Prompt-Default "¿Generar uno aleatorio? (s/n)" "s"
if ($jwtChoice -match '^[sS]$') {
    $JWT_SECRET = New-RandomSecret
    Write-Host "  Generado."
} else {
    $JWT_SECRET = Prompt-Secret "JWT_SECRET"
    if ([string]::IsNullOrEmpty($JWT_SECRET)) {
        Write-Error "JWT_SECRET no puede estar vacío"
        exit 1
    }
}
Write-Host ""

Write-Host "--- Usuario admin inicial ---"
Write-Host "Credenciales con las que se creara el usuario admin la primera vez que"
Write-Host "arranque el backend contra una BD vacia. Si la BD ya tiene usuarios,"
Write-Host "estas variables se ignoran (no sobrescriben nada)."
Write-Host ""
Write-Host "AVISO: la contrasena que introduzcas quedara guardada EN CLARO dentro"
Write-Host "del docker-compose.yml generado. Protege ese fichero (permisos,"
Write-Host "copias de seguridad) y cambia la contrasena desde la propia aplicacion"
Write-Host "despues del primer login."
$DEFAULT_USER_NAME = Prompt-Default "Nombre de usuario admin" "admin"
$DEFAULT_USER_PASSWORD = Prompt-Secret "Contrasena del admin"
if ([string]::IsNullOrEmpty($DEFAULT_USER_PASSWORD)) {
    Write-Error "La contrasena del admin no puede estar vacia"
    exit 1
}
Write-Host ""

Write-Host "--- Base de datos ---"
$dbChoice = Prompt-Default "¿Usar Postgres incluido (i) o base de datos propia (p)?" "i"
$UseInternalDb = $false
if ($dbChoice -match '^[iI]$') {
    $UseInternalDb = $true
    $DB_HOST = 'phenyxdb'
    $DB_PORT = '5432'
    $DB_NAME = 'postgres'
    $DB_USER = 'postgres'
    $passChoice = Prompt-Default "¿Generar contraseña aleatoria para el Postgres incluido? (s/n)" "s"
    if ($passChoice -match '^[sS]$') {
        $DB_PASS = New-RandomSecret
        Write-Host "  Contraseña generada."
    } else {
        $DB_PASS = Prompt-Secret "Contraseña de Postgres"
        if ([string]::IsNullOrEmpty($DB_PASS)) { Write-Error "La contraseña no puede estar vacía"; exit 1 }
    }
} else {
    $DB_HOST = Prompt-Default "DB_HOST" ""
    $DB_PORT = Prompt-Default "DB_PORT" "5432"
    $DB_NAME = Prompt-Default "DB_NAME" "phenyx"
    $DB_USER = Prompt-Default "DB_USER" "phenyx"
    $DB_PASS = Prompt-Secret "DB_PASS"
    if ([string]::IsNullOrEmpty($DB_HOST) -or [string]::IsNullOrEmpty($DB_PASS)) {
        Write-Error "DB_HOST y DB_PASS son obligatorios"
        exit 1
    }
}
Write-Host ""

$NODE_ENV = 'prod'

if (Test-Path $Output) {
    $backup = "$Output.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $Output $backup
    Write-Host "Backup del docker-compose.yml anterior: $backup"
}

$lines = Get-Content $Template
$result = New-Object System.Collections.Generic.List[string]
$skip = $false
foreach ($line in $lines) {
    if ($line -match '^# >>> PHENYX_DB_(BLOCK|DEPENDS)_START') {
        if (-not $UseInternalDb) { $skip = $true }
        continue
    }
    if ($line -match '^# <<< PHENYX_DB_(BLOCK|DEPENDS)_END') {
        $skip = $false
        continue
    }
    if (-not $skip) { $result.Add($line) }
}

$content = $result -join "`n"
$content = $content.Replace('${JWT_SECRET}',       $JWT_SECRET)
$content = $content.Replace('${DB_HOST}',          $DB_HOST)
$content = $content.Replace('${DB_PORT}',          $DB_PORT)
$content = $content.Replace('${DB_NAME}',          $DB_NAME)
$content = $content.Replace('${DB_USER}',          $DB_USER)
$content = $content.Replace('${DB_PASS}',          $DB_PASS)
$content = $content.Replace('${NODE_ENV}',         $NODE_ENV)
$content = $content.Replace('${FRONTEND_PORT}',    $FRONTEND_PORT)
$content = $content.Replace('${DEFAULT_USER_NAME}',     $DEFAULT_USER_NAME)
$content = $content.Replace('${DEFAULT_USER_PASSWORD}', $DEFAULT_USER_PASSWORD)

Set-Content -Path $Output -Value $content -Encoding UTF8
Write-Host "docker-compose.yml generado en $Output"
Write-Host ""

Write-Host @'
=== Siguientes pasos ===
1. Haz login en ECR (ver README, sección "Paso 2 - Login en ECR").
2. Arranca el sistema:
     docker compose up -d
     docker compose ps

Si más adelante quieres cambiar puertos, URL pública, contraseñas u otro
dato, vuelve a ejecutar este mismo script.
'@
