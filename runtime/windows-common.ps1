# Shared helpers for the Windows launcher / installer.
# Windows PowerShell 5.1 compatible (no ternary, no ??, no -SkipCertificateCheck).

$script:RuntimeDir = $PSScriptRoot
$script:Root = Split-Path -Parent $PSScriptRoot
$script:LaravelDir = Join-Path $script:Root "ns-server\Database\Laragon\ninjasage"
$script:PublicDir = Join-Path $script:LaravelDir "public"
$script:ClientDir = Join-Path $script:Root "ns-server\Custom Client\NS Custom Client V1"
$script:LogsDir = Join-Path $script:RuntimeDir "logs"
$script:PidsDir = Join-Path $script:RuntimeDir "pids"
$script:BinDir = Join-Path $script:RuntimeDir "bin"

$script:MariaDbPort = 3307
$script:LaravelPort = 8000
$script:EdgePort = 8443
$script:GameHost = "ninjasage.test"

$script:AssetDirs = @(
  "items", "pets", "materials", "npcs", "enemy", "swfpanels",
  "mission", "essentials", "consumables", "sounds"
)

function Write-Head {
  param([string]$Text)
  Write-Host ""
  Write-Host "  $Text" -ForegroundColor Yellow
  Write-Host ("  " + ("-" * $Text.Length)) -ForegroundColor DarkYellow
}

function Write-Step { param([string]$Text) Write-Host "  -> $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  OK  $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  !!  $Text" -ForegroundColor Yellow }
function Write-Err  { param([string]$Text) Write-Host "  XX  $Text" -ForegroundColor Red }

function Test-Port {
  param([int]$Port, [string]$HostName = "127.0.0.1", [int]$TimeoutMs = 350)
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
    $client.EndConnect($iar)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Wait-Port {
  param([int]$Port, [int]$Seconds = 25, [System.Diagnostics.Process]$Process = $null)
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Port -Port $Port) { return $true }
    if ($null -ne $Process -and $Process.HasExited) { return $false }
    Start-Sleep -Milliseconds 250
  }
  return (Test-Port -Port $Port)
}

function Wait-Http {
  param([string]$Url, [int]$Seconds = 15)
  $oldCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
  try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
      try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -lt 500) { return $true }
      } catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -lt 500) { return $true }
      }
      Start-Sleep -Milliseconds 300
    }
    return $false
  } finally {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $oldCallback
  }
}

# Uses the bundled Windows curl.exe instead of a PowerShell certificate
# callback.  A scriptblock callback can run on a thread without a runspace in
# Windows PowerShell 5.1 and fail even when the HTTPS edge is healthy.
function Test-EdgeHttps {
  param([int]$Port = $script:EdgePort, [int]$TimeoutSeconds = 5)
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) { return $true }  # no curl: the open port is our best signal
  $code = & $curl.Source --silent --show-error --insecure --output NUL --write-out "%{http_code}" --max-time $TimeoutSeconds "https://127.0.0.1:$Port/amf" 2>$null
  if ($LASTEXITCODE -ne 0) { return $false }
  return ("$code" -match '^[1-5][0-9][0-9]$')
}

function Find-FirstPath {
  param([string[]]$Paths)
  foreach ($p in $Paths) {
    if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
  }
  return $null
}

function Get-PhpExe {
  $candidates = @(
    (Join-Path $script:BinDir "php\php.exe"),
    (Join-Path $script:Root "runtime\bin\php\php.exe")
  )
  $cmd = Get-Command php.exe -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }
  $laragon = "C:\laragon\bin\php"
  if (Test-Path -LiteralPath $laragon) {
    Get-ChildItem -LiteralPath $laragon -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      ForEach-Object { $candidates += (Join-Path $_.FullName "php.exe") }
  }
  $candidates += @(
    "C:\xampp\php\php.exe",
    "C:\php\php.exe"
  )
  return (Find-FirstPath -Paths $candidates)
}

function Get-NodeExe {
  $candidates = @(
    (Join-Path $script:BinDir "node.exe"),
    (Join-Path $script:Root "runtime\bin\node.exe")
  )
  $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }
  $candidates += @(
    (Join-Path $env:ProgramFiles "nodejs\node.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "nodejs\node.exe")
  )
  return (Find-FirstPath -Paths $candidates)
}

function Get-MariaDbTools {
  $serverCandidates = @(
    (Join-Path $script:BinDir "mariadb\bin\mariadbd.exe"),
    (Join-Path $script:Root "runtime\bin\mariadb\bin\mariadbd.exe")
  )
  $cmd = Get-Command mariadbd.exe -ErrorAction SilentlyContinue
  if ($cmd) { $serverCandidates += $cmd.Source }
  $cmd = Get-Command mysqld.exe -ErrorAction SilentlyContinue
  if ($cmd) { $serverCandidates += $cmd.Source }
  foreach ($base in @("C:\laragon\bin\mariadb", "C:\laragon\bin\mysql")) {
    if (Test-Path -LiteralPath $base) {
      Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
          $serverCandidates += (Join-Path $_.FullName "bin\mariadbd.exe")
          $serverCandidates += (Join-Path $_.FullName "bin\mysqld.exe")
        }
    }
  }
  $serverCandidates += @(
    "C:\xampp\mysql\bin\mysqld.exe",
    "C:\Program Files\MariaDB 11.4\bin\mariadbd.exe",
    "C:\Program Files\MariaDB 11.8\bin\mariadbd.exe",
    "C:\Program Files\MariaDB 12.0\bin\mariadbd.exe"
  )
  $server = Find-FirstPath -Paths $serverCandidates
  if (-not $server) { return $null }

  $bin = Split-Path -Parent $server
  $admin = Find-FirstPath -Paths @(
    (Join-Path $bin "mariadb-admin.exe"),
    (Join-Path $bin "mysqladmin.exe")
  )
  $client = Find-FirstPath -Paths @(
    (Join-Path $bin "mariadb.exe"),
    (Join-Path $bin "mysql.exe")
  )
  $install = Find-FirstPath -Paths @(
    (Join-Path $bin "mariadb-install-db.exe"),
    (Join-Path $bin "mysql_install_db.exe")
  )
  return [pscustomobject]@{
    Server  = $server
    Admin   = $admin
    Client  = $client
    Install = $install
    BinDir  = $bin
  }
}

function Get-ChromeExe {
  $candidates = @(
    (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
    (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe"),
    (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe")
  )
  return (Find-FirstPath -Paths $candidates)
}

function Ensure-Junction {
  param([string]$Link, [string]$Target)
  if (Test-Path -LiteralPath $Link -PathType Container) {
    $item = Get-Item -LiteralPath $Link -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
    return $true  # already a real directory (copied fallback)
  }
  if (Test-Path -LiteralPath $Link) {
    Remove-Item -LiteralPath $Link -Force -Recurse -ErrorAction SilentlyContinue
  }
  $parent = Split-Path -Parent $Link
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  & cmd.exe /c "mklink /J `"$Link`" `"$Target`"" 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { return $true }

  Write-Warn "No se pudo crear un enlace en $Link; copiando la carpeta (ocupa más espacio)."
  try {
    Copy-Item -LiteralPath $Target -Destination $Link -Recurse -Force -ErrorAction Stop
    return $true
  } catch {
    Write-Warn "No se pudo copiar $Target -> $Link : $($_.Exception.Message)"
    return $false
  }
}

function Copy-IfChanged {
  param([string]$Source, [string]$Destination)
  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return }
  $copy = $true
  if (Test-Path -LiteralPath $Destination -PathType Leaf) {
    $a = Get-Item -LiteralPath $Source
    $b = Get-Item -LiteralPath $Destination
    if ($a.Length -eq $b.Length) { $copy = $false }
  }
  if ($copy) {
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
  }
}

function Copy-TreeIfMissing {
  param([string]$Source, [string]$Destination, [string]$Probe)
  if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
  if ($Probe -and (Test-Path -LiteralPath $Probe -PathType Leaf)) { return }
  if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  }
  Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

function Deploy-GameFiles {
  $patched = Join-Path $script:RuntimeDir "NinjaSage_patched3.swf"
  $client = Join-Path $script:PublicDir "client\NinjaSage.swf"
  if (-not (Test-Path -LiteralPath $patched)) {
    throw "Falta runtime\NinjaSage_patched3.swf (cliente parcheado)."
  }
  Copy-IfChanged -Source $patched -Destination $client

  Copy-IfChanged -Source (Join-Path $script:Root "arcade\play.html") -Destination (Join-Path $script:PublicDir "play.html")
  Copy-IfChanged -Source (Join-Path $script:Root "arcade\bg.jpg") -Destination (Join-Path $script:PublicDir "arcade\bg.jpg")

  $fontsSrc = Join-Path $script:RuntimeDir "assets\fonts"
  $fontsDst = Join-Path $script:PublicDir "fonts"
  if (Test-Path -LiteralPath $fontsSrc) {
    if (-not (Test-Path -LiteralPath $fontsDst)) { New-Item -ItemType Directory -Force -Path $fontsDst | Out-Null }
    Get-ChildItem -LiteralPath $fontsSrc -File | ForEach-Object {
      Copy-IfChanged -Source $_.FullName -Destination (Join-Path $fontsDst $_.Name)
    }
  }

  $tmpSrc = Join-Path $script:RuntimeDir "assets\tmp"
  if (Test-Path -LiteralPath $tmpSrc) {
    $tmpDst = Join-Path $script:PublicDir "tmp"
    if (-not (Test-Path -LiteralPath $tmpDst)) { New-Item -ItemType Directory -Force -Path $tmpDst | Out-Null }
    Get-ChildItem -LiteralPath $tmpSrc -File | ForEach-Object {
      Copy-IfChanged -Source $_.FullName -Destination (Join-Path $tmpDst $_.Name)
    }
  }

  Copy-TreeIfMissing `
    -Source (Join-Path $script:Root "tools\ruffle-web") `
    -Destination (Join-Path $script:PublicDir "tools\ruffle-web") `
    -Probe (Join-Path $script:PublicDir "tools\ruffle-web\ruffle.js")

  if (Test-Path -LiteralPath $script:ClientDir -PathType Container) {
    foreach ($name in $script:AssetDirs) {
      $src = Join-Path $script:ClientDir $name
      $dst = Join-Path $script:PublicDir $name
      if (Test-Path -LiteralPath $src -PathType Container) {
        if (-not (Test-Path -LiteralPath $dst)) {
          [void](Ensure-Junction -Link $dst -Target $src)
        }
      }
    }
  }

  # Compatibility with artisan commands that still read storage/app/private/game_data.
  $storageGameData = Join-Path $script:LaravelDir "storage\app\private\game_data"
  $publicGameData = Join-Path $script:PublicDir "game_data"
  if ((Test-Path -LiteralPath $publicGameData -PathType Container) -and (-not (Test-Path -LiteralPath $storageGameData))) {
    [void](Ensure-Junction -Link $storageGameData -Target $publicGameData)
  }
}

function Set-EnvValue {
  param([string]$Path, [string]$Key, [string]$Value)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $escaped = [regex]::Escape($Key)
  $lines = @(Get-Content -LiteralPath $Path)
  $found = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    if ($line -match "^\s*$escaped\s*=") {
      $out.Add("$Key=$Value")
      $found = $true
    } else {
      $out.Add($line)
    }
  }
  if (-not $found) { $out.Add("$Key=$Value") }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($Path, $out, $utf8)
}

function Format-EnvPath {
  param([string]$Path)
  $p = $Path.Replace("\", "/")
  return '"' + $p + '"'
}

function Write-PidFile {
  param([string]$Name, [int]$ProcessId)
  if (-not (Test-Path -LiteralPath $script:PidsDir)) {
    New-Item -ItemType Directory -Force -Path $script:PidsDir | Out-Null
  }
  Set-Content -LiteralPath (Join-Path $script:PidsDir "$Name.pid") -Value $ProcessId -Encoding ASCII
}

function Read-PidFile {
  param([string]$Name)
  $p = Join-Path $script:PidsDir "$Name.pid"
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return [int](Get-Content -LiteralPath $p -Raw).Trim() } catch { return $null }
}

function Test-ProcessAlive {
  param([int]$ProcessId)
  if (-not $ProcessId) { return $false }
  return [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Stop-ProcessTree {
  param([int]$ProcessId)
  if (-not $ProcessId) { return }
  & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
}

function Start-BackgroundProcess {
  param(
    [string]$FilePath,
    [string]$Arguments,
    [string]$WorkingDirectory,
    [string]$StdOut,
    [string]$StdErr
  )
  $parent = Split-Path -Parent $StdOut
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
    -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr
  return $p
}

function Start-LocalMariaDb {
  param([switch]$Quiet)
  $db = Get-MariaDbTools
  if (-not $db) {
    throw "No encontré MariaDB. Ejecuta setup.bat o instala MariaDB."
  }
  if (Test-Port -Port $script:MariaDbPort) {
    if ($db.Admin) {
      & $db.Admin --host=127.0.0.1 --port=$script:MariaDbPort -uroot ping 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "El puerto $script:MariaDbPort está ocupado por otro programa. Ciérralo y vuelve a intentar."
      }
    }
    if (-not $Quiet) { Write-Ok "MariaDB ya está escuchando en :$($script:MariaDbPort)" }
    return $db
  }
  $datadir = Join-Path $script:RuntimeDir "mysql"
  if (-not (Test-Path -LiteralPath (Join-Path $datadir "mysql"))) {
    throw "La base de datos no está inicializada. Ejecuta setup.bat primero."
  }
  if (-not (Test-Path -LiteralPath $script:LogsDir)) {
    New-Item -ItemType Directory -Force -Path $script:LogsDir | Out-Null
  }
  $argLine = @(
    "--datadir=`"$datadir`"",
    "--port=$script:MariaDbPort",
    "--bind-address=127.0.0.1",
    "--pid-file=`"$(Join-Path $script:RuntimeDir 'mysql.pid')`"",
    "--log-error=`"$(Join-Path $script:LogsDir 'mariadb.err')`""
  ) -join " "
  $stdout = Join-Path $script:LogsDir "mariadb-console.log"
  $stderr = Join-Path $script:LogsDir "mariadb-console.err.log"
  $p = Start-BackgroundProcess -FilePath $db.Server -Arguments $argLine -WorkingDirectory $script:Root -StdOut $stdout -StdErr $stderr
  Write-PidFile -Name "mariadb" -ProcessId $p.Id
  if (-not (Wait-Port -Port $script:MariaDbPort -Seconds 30 -Process $p)) {
    $tail = ""
    $errFile = Join-Path $script:LogsDir "mariadb.err"
    if (Test-Path -LiteralPath $errFile) { $tail = (Get-Content -LiteralPath $errFile -Tail 25) -join "`n" }
    throw "MariaDB no arrancó.`n$tail"
  }
  if (-not $Quiet) { Write-Ok "MariaDB iniciada en :$($script:MariaDbPort)" }
  return $db
}

function Start-LocalLaravel {
  param([switch]$Quiet)
  if (Test-Port -Port $script:LaravelPort) {
    if (-not $Quiet) { Write-Ok "Laravel ya está escuchando en :$($script:LaravelPort)" }
    return
  }
  $php = Get-PhpExe
  if (-not $php) { throw "No encontré PHP. Ejecuta setup.bat." }
  $autoload = Join-Path $script:LaravelDir "vendor\autoload.php"
  if (-not (Test-Path -LiteralPath $autoload)) { throw "Faltan las dependencias de Laravel (vendor/). Ejecuta setup.bat." }
  if (-not (Test-Path -LiteralPath $script:LogsDir)) {
    New-Item -ItemType Directory -Force -Path $script:LogsDir | Out-Null
  }
  $argLine = "artisan serve --host=127.0.0.1 --port=$script:LaravelPort"
  $stdout = Join-Path $script:LogsDir "laravel-console.log"
  $stderr = Join-Path $script:LogsDir "laravel-console.err.log"
  $p = Start-BackgroundProcess -FilePath $php -Arguments $argLine -WorkingDirectory $script:LaravelDir -StdOut $stdout -StdErr $stderr
  Write-PidFile -Name "laravel" -ProcessId $p.Id
  if (-not (Wait-Port -Port $script:LaravelPort -Seconds 30 -Process $p)) {
    throw "Laravel no arrancó. Revisa runtime\logs\laravel-console.log"
  }
  if (-not $Quiet) { Write-Ok "Laravel iniciado en :$($script:LaravelPort)" }
}

function Ensure-Tls {
  $cert = Join-Path $script:RuntimeDir "tls\cert.pem"
  $key = Join-Path $script:RuntimeDir "tls\key.pem"
  if ((Test-Path -LiteralPath $cert) -and (Test-Path -LiteralPath $key)) { return }

  $php = Get-PhpExe
  $generator = Join-Path $script:RuntimeDir "tls\generate.php"
  if (-not $php -or -not (Test-Path -LiteralPath $generator)) {
    throw "Falta el certificado TLS local y no se pudo generar. Ejecuta setup.bat."
  }
  $tlsDir = Split-Path -Parent $cert
  if (-not (Test-Path -LiteralPath $tlsDir)) {
    New-Item -ItemType Directory -Force -Path $tlsDir | Out-Null
  }
  Write-Step "Generando certificado TLS local ..."
  $cnf = Join-Path (Split-Path -Parent $php) "extras\ssl\openssl.cnf"
  $oldConf = $env:OPENSSL_CONF
  if (Test-Path -LiteralPath $cnf) { $env:OPENSSL_CONF = $cnf }
  try {
    & $php $generator $script:GameHost
    if ($LASTEXITCODE -ne 0) {
      throw "No se pudo generar el certificado TLS (código $LASTEXITCODE)."
    }
  } finally {
    if ($null -eq $oldConf) {
      Remove-Item Env:\OPENSSL_CONF -ErrorAction SilentlyContinue
    } else {
      $env:OPENSSL_CONF = $oldConf
    }
  }
  if (-not (Test-Path -LiteralPath $cert) -or -not (Test-Path -LiteralPath $key)) {
    throw "El generador de certificados no creó cert.pem y key.pem."
  }
  Write-Ok "Certificado TLS local generado."
}

function Start-LocalEdge {
  param([switch]$Quiet)
  if (Test-Port -Port $script:EdgePort) {
    if (-not (Test-EdgeHttps)) {
      throw "El puerto $script:EdgePort está ocupado por otro programa. Ciérralo y vuelve a intentar."
    }
    if (-not $Quiet) { Write-Ok "Edge HTTPS ya está escuchando en :$($script:EdgePort)" }
    return
  }
  $node = Get-NodeExe
  if (-not $node) { throw "No encontré Node.js. Ejecuta setup.bat." }
  Ensure-Tls
  $cert = Join-Path $script:RuntimeDir "tls\cert.pem"
  $key = Join-Path $script:RuntimeDir "tls\key.pem"
  if (-not (Test-Path -LiteralPath $cert) -or -not (Test-Path -LiteralPath $key)) {
    throw "Faltan runtime\tls\cert.pem y key.pem. Vuelve a descargar el proyecto."
  }
  if (-not (Test-Path -LiteralPath $script:LogsDir)) {
    New-Item -ItemType Directory -Force -Path $script:LogsDir | Out-Null
  }
  $env:EDGE_PORT = "$script:EdgePort"
  $env:UPSTREAM_PORT = "$script:LaravelPort"
  try {
    $stdout = Join-Path $script:LogsDir "edge-console.log"
    $stderr = Join-Path $script:LogsDir "edge-console.err.log"
    $p = Start-BackgroundProcess -FilePath $node -Arguments "`"$(Join-Path $script:RuntimeDir 'proxy.js')`"" -WorkingDirectory $script:Root -StdOut $stdout -StdErr $stderr
  } finally {
    Remove-Item Env:\EDGE_PORT -ErrorAction SilentlyContinue
    Remove-Item Env:\UPSTREAM_PORT -ErrorAction SilentlyContinue
  }
  Write-PidFile -Name "edge" -ProcessId $p.Id
  if (-not (Wait-Port -Port $script:EdgePort -Seconds 20 -Process $p)) {
    throw "El proxy HTTPS no arrancó. Revisa runtime\logs\edge-console.log"
  }
  if (-not (Test-EdgeHttps)) {
    throw "El proxy HTTPS no responde. Revisa runtime\logs\edge-console.log"
  }
  if (-not $Quiet) { Write-Ok "Edge HTTPS iniciado en https://$script:GameHost`:$script:EdgePort" }
}

function Stop-LocalServices {
  Write-Step "Deteniendo servicios locales..."
  $db = Get-MariaDbTools
  if ($db -and $db.Admin -and (Test-Port -Port $script:MariaDbPort)) {
    & $db.Admin --host=127.0.0.1 --port=$script:MariaDbPort -uroot shutdown 2>&1 | Out-Null
  }
  foreach ($name in @("edge", "laravel", "mariadb")) {
    $pidValue = Read-PidFile -Name $name
    if ($pidValue -and (Test-ProcessAlive -ProcessId $pidValue)) {
      Stop-ProcessTree -ProcessId $pidValue
    }
    $pidFile = Join-Path $script:PidsDir "$name.pid"
    if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
  }
  Start-Sleep -Milliseconds 800
  Write-Ok "Servicios detenidos. (El navegador puede seguir abierto; ciérralo o recarga.)"
}
