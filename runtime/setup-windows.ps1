param(
  [switch]$NoLaunch,
  [switch]$ResetDatabase,
  [switch]$ForceTools
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

. "$PSScriptRoot\windows-common.ps1"

$script:PhpExe = $null
$script:SetupMarker = Join-Path $script:RuntimeDir ".setup-complete"
$script:PhpVersion = "8.4"
$script:MariaDbVersion = "11.4.8"
$script:NodeVersion = "22.23.4"

function Assert-Adminless {
  if (-not [Environment]::Is64BitOperatingSystem) {
    throw "Este proyecto necesita Windows de 64 bits."
  }
  if ([Environment]::OSVersion.Version.Major -lt 10) {
    Write-Warn "Windows anterior a 10 no está probado. Puede funcionar, pero no está soportado."
  }
}

function Get-Download {
  param([string]$Url, [string]$Destination, [long]$MinBytes = 1024)
  if (Test-Path -LiteralPath $Destination) {
    if ((Get-Item -LiteralPath $Destination).Length -ge $MinBytes) { return }
    Remove-Item -LiteralPath $Destination -Force
  }
  Write-Step "Descargando $(Split-Path -Leaf $Destination) ..."
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    & $curl.Source --fail --location --retry 3 --retry-delay 2 --output $Destination $Url
    if ($LASTEXITCODE -ne 0) { throw "No se pudo descargar $Url (curl $LASTEXITCODE)." }
  } else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
  }
  if (-not (Test-Path -LiteralPath $Destination)) { throw "La descarga no creó $Destination." }
  if ((Get-Item -LiteralPath $Destination).Length -lt $MinBytes) { throw "Descarga incompleta: $Url" }
}

function Expand-ZipTo {
  param([string]$Zip, [string]$Destination)
  if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  }
  $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
  if ($tar) {
    & $tar.Source -xf $Zip -C $Destination
    if ($LASTEXITCODE -eq 0) { return }
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Destination)
}

function Get-FileHashSafe {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Install-Php {
  $phpDir = Join-Path $script:BinDir "php"
  $phpExe = Join-Path $phpDir "php.exe"
  if ((-not (Test-Path -LiteralPath $phpExe)) -or $ForceTools) {
    $url = "https://windows.php.net/downloads/releases/latest/php-$script:PhpVersion-nts-Win32-vs17-x64-latest.zip"
    $zip = Join-Path $script:DownloadDir "php-$script:PhpVersion.zip"
    Get-Download -Url $url -Destination $zip -MinBytes 10000000
    Write-Step "Extrayendo PHP ..."
    if (Test-Path -LiteralPath $phpDir) { Remove-Item -LiteralPath $phpDir -Recurse -Force }
    Expand-ZipTo -Zip $zip -Destination $phpDir
    Get-ChildItem -LiteralPath $phpDir -Filter "*.exe" | ForEach-Object {
      Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue
    }
  }
  if (-not (Test-Path -LiteralPath $phpExe)) { throw "No se encontró php.exe después de instalar PHP." }

  $ini = Join-Path $phpDir "php.ini"
  $extDir = (Join-Path $phpDir "ext").Replace("\", "/")
  $iniText = @"
[PHP]
extension_dir = "$extDir"
extension=curl
extension=exif
extension=fileinfo
extension=gd
extension=intl
extension=mbstring
extension=openssl
extension=pdo_mysql
extension=mysqli
extension=sodium
extension=zip

memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
date.timezone = UTC
log_errors = On
error_reporting = E_ALL
"@
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($ini, $iniText, $utf8)

  $version = & $phpExe -r "echo PHP_VERSION;"
  if ($LASTEXITCODE -ne 0) { throw "php.exe no se pudo ejecutar." }
  if ([version]$version -lt [version]"8.2.0") { throw "PHP $version es demasiado antiguo (se necesita 8.2+)." }
  $modules = @(& $phpExe -m)
  # bcmath is optional for Laravel/ramsey/uuid and is not shipped in the
  # official Windows NTS build, so it is intentionally not checked here.
  foreach ($required in @("pdo_mysql", "mbstring", "openssl", "fileinfo", "curl", "zip", "intl", "gd")) {
    if ($modules -notcontains $required) {
      Write-Warn "La extensión PHP '$required' no está activa. Revisa $ini"
    }
  }
  Write-Ok "PHP $version listo (runtime\bin\php)."
  return $phpExe
}

function Install-MariaDb {
  $dbDir = Join-Path $script:BinDir "mariadb"
  $serverExe = Join-Path $dbDir "bin\mariadbd.exe"
  if ((-not (Test-Path -LiteralPath $serverExe)) -or $ForceTools) {
    $url = "https://archive.mariadb.org/mariadb-$script:MariaDbVersion/winx64-packages/mariadb-$script:MariaDbVersion-winx64.zip"
    $zip = Join-Path $script:DownloadDir "mariadb-$script:MariaDbVersion.zip"
    Get-Download -Url $url -Destination $zip -MinBytes 50000000

    Write-Step "Verificando checksum de MariaDB ..."
    $sumsUrl = "https://archive.mariadb.org/mariadb-$script:MariaDbVersion/winx64-packages/sha256sums.txt"
    $sumsFile = Join-Path $script:DownloadDir "mariadb-sha256sums.txt"
    Get-Download -Url $sumsUrl -Destination $sumsFile -MinBytes 20
    $line = Select-String -LiteralPath $sumsFile -Pattern "mariadb-$script:MariaDbVersion-winx64\.zip" | Select-Object -First 1
    if ($line) {
      $expected = ($line.Line -split "\s+")[0]
      $actual = Get-FileHashSafe -Path $zip
      if ($actual -ne $expected) { throw "Checksum de MariaDB incorrecto. Descarga corrupta o manipulada." }
      Write-Ok "Checksum de MariaDB correcto."
    }

    Write-Step "Extrayendo MariaDB ..."
    $tmp = Join-Path $script:DownloadDir "mariadb-extract"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    Expand-ZipTo -Zip $zip -Destination $tmp
    $top = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    if (-not $top) { throw "El ZIP de MariaDB no tiene la estructura esperada." }
    if (Test-Path -LiteralPath $dbDir) { Remove-Item -LiteralPath $dbDir -Recurse -Force }
    Move-Item -LiteralPath $top.FullName -Destination $dbDir
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $dbDir "bin") -Filter "*.exe" | ForEach-Object {
      Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue
    }
  }
  if (-not (Test-Path -LiteralPath $serverExe)) { throw "No se encontró mariadbd.exe después de instalar MariaDB." }
  Write-Ok "MariaDB $script:MariaDbVersion listo (runtime\bin\mariadb)."
}

function Install-Node {
  $nodeExe = Join-Path $script:BinDir "node.exe"
  if ((-not (Test-Path -LiteralPath $nodeExe)) -or $ForceTools) {
    $url = "https://nodejs.org/dist/v$script:NodeVersion/node-v$script:NodeVersion-win-x64.zip"
    $zip = Join-Path $script:DownloadDir "node-$script:NodeVersion-win-x64.zip"
    Get-Download -Url $url -Destination $zip -MinBytes 20000000

    Write-Step "Verificando checksum de Node.js ..."
    $sumsUrl = "https://nodejs.org/dist/v$script:NodeVersion/SHASUMS256.txt"
    $sumsFile = Join-Path $script:DownloadDir "node-sha256sums.txt"
    Get-Download -Url $sumsUrl -Destination $sumsFile -MinBytes 100
    $line = Select-String -LiteralPath $sumsFile -Pattern "node-v$script:NodeVersion-win-x64\.zip" | Select-Object -First 1
    if ($line) {
      $expected = ($line.Line -split "\s+")[0]
      $actual = Get-FileHashSafe -Path $zip
      if ($actual -ne $expected) { throw "Checksum de Node.js incorrecto. Descarga corrupta o manipulada." }
      Write-Ok "Checksum de Node.js correcto."
    }

    Write-Step "Extrayendo node.exe ..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
      $entry = $archive.Entries | Where-Object { $_.FullName -match "/node\.exe$" } | Select-Object -First 1
      if (-not $entry) { throw "No se encontró node.exe dentro del ZIP." }
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $nodeExe, $true)
    } finally {
      $archive.Dispose()
    }
    Unblock-File -LiteralPath $nodeExe -ErrorAction SilentlyContinue
  }
  if (-not (Test-Path -LiteralPath $nodeExe)) { throw "No se encontró node.exe después de instalar Node.js." }
  $nv = & $nodeExe --version
  Write-Ok "Node.js $nv listo (runtime\bin\node.exe)."
}

function Ensure-Vendor {
  $autoload = Join-Path $script:LaravelDir "vendor\autoload.php"
  if (Test-Path -LiteralPath $autoload) {
    Write-Ok "Dependencias PHP ya incluidas (vendor/)."
    return
  }
  Write-Step "Faltan las dependencias PHP; intentando composer install ..."
  $composer = Get-Command composer.bat -ErrorAction SilentlyContinue
  $composerPhar = Join-Path $script:BinDir "composer.phar"
  if (-not $composer) {
    Get-Download -Url "https://getcomposer.org/download/latest-stable/composer.phar" -Destination $composerPhar -MinBytes 1000000
  }
  Push-Location $script:LaravelDir
  try {
    if ($composer) {
      & $composer.Source install --no-interaction --prefer-dist --no-dev --optimize-autoloader --no-progress
    } else {
      & $script:PhpExe $composerPhar install --no-interaction --prefer-dist --no-dev --optimize-autoloader --no-progress
    }
    if ($LASTEXITCODE -ne 0) { throw "composer install falló. Revisa tu conexión a internet." }
  } finally {
    Pop-Location
  }
  if (-not (Test-Path -LiteralPath $autoload)) { throw "composer install no creó vendor/autoload.php." }
  Write-Ok "Dependencias PHP instaladas."
}

function Invoke-Php {
  param([string[]]$PhpArgs, [switch]$AllowFailure)
  Push-Location $script:LaravelDir
  try {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $output = & $script:PhpExe @PhpArgs 2>&1
      $code = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $old
    }
    foreach ($line in @($output)) { Write-Host "    $line" }
  } finally {
    Pop-Location
  }
  if ($code -ne 0 -and -not $AllowFailure) {
    throw "PHP falló (código $code): php $($PhpArgs -join ' ')"
  }
  return $code
}

function Configure-Env {
  $envFile = Join-Path $script:LaravelDir ".env"
  $example = Join-Path $script:LaravelDir ".env.example"
  if (-not (Test-Path -LiteralPath $envFile)) {
    Copy-Item -LiteralPath $example -Destination $envFile
    Write-Step "Creado .env a partir de .env.example."
  }
  Set-EnvValue -Path $envFile -Key "APP_NAME" -Value '"Ninja Saga Local Server"'
  Set-EnvValue -Path $envFile -Key "APP_ENV" -Value "local"
  Set-EnvValue -Path $envFile -Key "APP_DEBUG" -Value "true"
  Set-EnvValue -Path $envFile -Key "APP_URL" -Value "https://ninjasage.test"
  Set-EnvValue -Path $envFile -Key "DB_CONNECTION" -Value "mysql"
  Set-EnvValue -Path $envFile -Key "DB_HOST" -Value "127.0.0.1"
  Set-EnvValue -Path $envFile -Key "DB_PORT" -Value "$script:MariaDbPort"
  Set-EnvValue -Path $envFile -Key "DB_DATABASE" -Value "ninjasage"
  Set-EnvValue -Path $envFile -Key "DB_USERNAME" -Value "root"
  Set-EnvValue -Path $envFile -Key "DB_PASSWORD" -Value ""
  Set-EnvValue -Path $envFile -Key "SESSION_VALIDATE_BYPASS" -Value "true"
  Set-EnvValue -Path $envFile -Key "SKILL_SWF_PATH" -Value (Format-EnvPath (Join-Path $script:ClientDir "skills"))
  Set-EnvValue -Path $envFile -Key "ENEMY_SWF_PATH" -Value (Format-EnvPath (Join-Path $script:ClientDir "enemy"))
  Set-EnvValue -Path $envFile -Key "SKILL_DEFAULT_SWF" -Value "skill_01.swf"

  $keyLine = Select-String -LiteralPath $envFile -Pattern '^APP_KEY=(.*)$' | Select-Object -First 1
  if (-not $keyLine -or $keyLine.Matches[0].Groups[1].Value.Trim() -eq "") {
    Write-Step "Generando APP_KEY ..."
    [void](Invoke-Php -PhpArgs @("artisan", "key:generate", "--force", "--no-interaction"))
  }
  [void](Invoke-Php -PhpArgs @("artisan", "config:clear"))
}

function Initialize-Database {
  $datadir = Join-Path $script:RuntimeDir "mysql"
  $marker = Join-Path $datadir ".windows-initialized"
  $db = Get-MariaDbTools

  if ($ResetDatabase) {
    Write-Warn "ResetDatabase: se va a crear una base de datos nueva."
    Stop-LocalServices
    if (Test-Path -LiteralPath $datadir) {
      $backup = Join-Path $script:RuntimeDir ("mysql.legacy-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
      Move-Item -LiteralPath $datadir -Destination $backup
      Write-Warn "La base anterior se conservó en $backup"
    }
  }

  if ((Test-Path -LiteralPath (Join-Path $datadir "mysql")) -and (-not (Test-Path -LiteralPath $marker))) {
    if (Test-Port -Port $script:MariaDbPort) {
      throw "Hay una base de datos en runtime\mysql sin marca de Windows y el puerto $script:MariaDbPort está ocupado. Detén ese servicio y vuelve a ejecutar setup.bat."
    }
    $backup = Join-Path $script:RuntimeDir ("mysql.legacy-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    Move-Item -LiteralPath $datadir -Destination $backup
    Write-Warn "Se preservó una base de datos anterior en $backup"
  }

  if (-not (Test-Path -LiteralPath (Join-Path $datadir "mysql"))) {
    if (-not (Test-Path -LiteralPath $datadir)) { New-Item -ItemType Directory -Force -Path $datadir | Out-Null }
    $db = Get-MariaDbTools
    if (-not $db -or -not $db.Install) { throw "No encontré mariadb-install-db.exe." }
    Write-Step "Inicializando MariaDB (solo la primera vez) ..."
    # The Windows mariadb-install-db.exe does NOT accept the Unix installer flags
    # (--auth-root-authentication-method / --skip-test-db).  Its supported flags are
    # datadir, port, password, service, etc.  With no --password the root account is
    # created without a password, which is what the local .env expects.
    $argLine = "--datadir=`"$datadir`" --port=$script:MariaDbPort"
    $p = Start-Process -FilePath $db.Install -ArgumentList $argLine -Wait -NoNewWindow -PassThru
    if ($p.ExitCode -ne 0) { throw "mariadb-install-db falló con código $($p.ExitCode)." }
    Set-Content -LiteralPath $marker -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Encoding ASCII
    Write-Ok "Base de datos inicializada en runtime\mysql."
  }

  $db = Start-LocalMariaDb
  if (-not $db -or -not $db.Client) { throw "No encontré el cliente de MariaDB." }

  & $db.Client --host=127.0.0.1 --port=$script:MariaDbPort --user=root --execute="CREATE DATABASE IF NOT EXISTS ninjasage CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  if ($LASTEXITCODE -ne 0) { throw "No se pudo crear la base de datos ninjasage." }

  [void](Invoke-Php -PhpArgs @("artisan", "migrate", "--force", "--no-interaction"))

  $items = (& $db.Client --host=127.0.0.1 --port=$script:MariaDbPort --user=root --database=ninjasage --skip-column-names --batch --execute="SELECT COUNT(*) FROM items;").Trim()
  if ([int]$items -eq 0) {
    Write-Step "Cargando datos del juego (items, skills, misiones, NPCs...) ..."
    [void](Invoke-Php -PhpArgs @("artisan", "db:seed", "--force", "--no-interaction"))
  } else {
    Write-Ok "Los datos del juego ya estaban cargados ($items items)."
    [void](Invoke-Php -PhpArgs @("artisan", "db:seed", "--class=DemoUserSeeder", "--force", "--no-interaction") -AllowFailure)
    [void](Invoke-Php -PhpArgs @("artisan", "db:seed", "--class=AdminUserSeeder", "--force", "--no-interaction") -AllowFailure)
  }

  [void](Invoke-Php -PhpArgs @("artisan", "package:discover", "--no-interaction") -AllowFailure)
  [void](Invoke-Php -PhpArgs @("artisan", "view:clear") -AllowFailure)
  [void](Invoke-Php -PhpArgs @("artisan", "config:clear") -AllowFailure)

  $counts = & $db.Client --host=127.0.0.1 --port=$script:MariaDbPort --user=root --database=ninjasage --skip-column-names --batch --execute="SELECT (SELECT COUNT(*) FROM items), (SELECT COUNT(*) FROM skills), (SELECT COUNT(*) FROM enemies), (SELECT COUNT(*) FROM missions), (SELECT COUNT(*) FROM users);"
  Write-Ok "Base de datos lista. items/skills/enemies/missions/users = $counts"
}

function Show-Summary {
  Write-Head "Instalación completada"
  Write-Host "  Para jugar, abre:  launch.bat" -ForegroundColor White
  Write-Host "  Cuenta premium:   macninja / ninja1234" -ForegroundColor White
  Write-Host "  Panel admin:       https://ninjasage.test/admin  (admin@admin.test / admin)" -ForegroundColor White
  Write-Host "  Detener:           stop.bat" -ForegroundColor White
  Write-Host ""
  Write-Host "  Logs: runtime\logs\" -ForegroundColor DarkGray
  Write-Host "  Si Windows Defender pregunta, permite el acceso a la red local." -ForegroundColor DarkGray
}

Ensure-Directories
Start-Transcript -Path (Join-Path $script:LogsDir "setup.log") -Append | Out-Null
try {
  Write-Head "NINJA SAGA · instalación para Windows"
  Write-Host "  Carpeta: $script:Root" -ForegroundColor DarkGray
  Assert-Adminless
  if ($script:Root.Length -gt 120) {
    Write-Warn "La ruta es larga. Si algo falla, mueve el proyecto a C:\NinjaSaga."
  }
  $drive = (Get-Item -LiteralPath $script:Root).PSDrive.Name
  $free = (Get-PSDrive -Name $drive).Free
  if ($free -lt 1GB) { throw "Necesitas al menos 1 GB libre en $drive`:." }

  Write-Head "1/5 · Herramientas portables"
  $script:PhpExe = Install-Php
  Install-MariaDb
  Install-Node

  Write-Head "2/5 · Servidor y dependencias"
  Ensure-Vendor

  Write-Head "3/5 · Archivos del juego"
  Deploy-GameFiles
  Configure-Env
  Write-Ok "Archivos y .env preparados."

  Write-Head "4/5 · Base de datos"
  Initialize-Database

  Write-Head "5/5 · Verificación"
  $index = Join-Path $script:PublicDir "index.php"
  if (-not (Test-Path -LiteralPath $index)) { throw "No se encontró public/index.php." }
  $client = Join-Path $script:PublicDir "client\NinjaSage.swf"
  if (-not (Test-Path -LiteralPath $client)) { throw "No se desplegó el cliente parcheado." }
  Ensure-Tls
  Set-Content -LiteralPath $script:SetupMarker -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Encoding ASCII
  Write-Ok "Instalación verificada."

  Show-Summary

  if (-not $NoLaunch) {
    Write-Host ""
    Write-Step "Abriendo el juego ..."
    & (Join-Path $script:RuntimeDir "launch-windows.ps1")
  }
} catch {
  Write-Host ""
  Write-Err $_.Exception.Message
  Write-Host ""
  Write-Host "  Revisa el log completo en: runtime\logs\setup.log" -ForegroundColor Yellow
  exit 1
} finally {
  Stop-Transcript | Out-Null
}
