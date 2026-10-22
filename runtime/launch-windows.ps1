param(
  [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

. "$PSScriptRoot\windows-common.ps1"

function Show-Banner {
  Write-Host ""
  Write-Host "  NINJA SAGA · servidor local" -ForegroundColor Yellow
  Write-Host "  --------------------------" -ForegroundColor DarkYellow
}

function Assert-Ready {
  $php = Get-PhpExe
  if (-not $php) { throw "No encontré PHP. Ejecuta setup.bat primero." }
  $node = Get-NodeExe
  if (-not $node) { throw "No encontré Node.js. Ejecuta setup.bat primero." }
  $db = Get-MariaDbTools
  if (-not $db) { throw "No encontré MariaDB. Ejecuta setup.bat primero." }
  if (-not (Test-Path -LiteralPath (Join-Path $script:LaravelDir ".env"))) {
    throw "Falta ns-server\Database\Laragon\ninjasage\.env. Ejecuta setup.bat primero."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $script:RuntimeDir "mysql\mysql"))) {
    throw "La base de datos no está inicializada. Ejecuta setup.bat primero."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $script:PublicDir "game_data"))) {
    throw "Faltan los datos del juego (public\game_data). Vuelve a descargar el proyecto."
  }
}

function Open-GameBrowser {
  $browser = Get-ChromeExe
  if (-not $browser) {
    Write-Warn "No encontré Chrome ni Edge. Abre manualmente https://$script:GameHost/play"
    return
  }
  $profile = Join-Path $script:RuntimeDir "chrome-profile"
  if (-not (Test-Path -LiteralPath $profile)) { New-Item -ItemType Directory -Force -Path $profile | Out-Null }
  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $url = "https://$script:GameHost/play?l=$stamp"
  $rules = "MAP $script:GameHost 127.0.0.1:$script:EdgePort,MAP ninjasage.id 127.0.0.1:$script:EdgePort,MAP ns-assets.ninjasage.id 127.0.0.1:$script:EdgePort,MAP www.ninjasage.id 127.0.0.1:$script:EdgePort"
  $argLine = @(
    "--user-data-dir=`"$profile`"",
    "--ignore-certificate-errors",
    "--host-resolver-rules=`"$rules`"",
    "--autoplay-policy=no-user-gesture-required",
    "--ignore-gpu-blocklist",
    "--test-type",
    "--no-first-run",
    "--no-default-browser-check",
    "--window-size=1440,900",
    "--app=`"$url`""
  ) -join " "
  try {
    Start-Process -FilePath $browser -ArgumentList $argLine -WorkingDirectory $script:Root | Out-Null
    Write-Ok "Abriendo Ninja Saga en el navegador..."
  } catch {
    Write-Warn "No se pudo abrir el navegador: $($_.Exception.Message)"
    Write-Host "  Abre manualmente: $url" -ForegroundColor Yellow
  }
}

Ensure-Directories
try {
  Show-Banner
  Assert-Ready

  Deploy-GameFiles
  Start-LocalMariaDb | Out-Null
  Start-LocalLaravel | Out-Null
  Start-LocalEdge | Out-Null

  Write-Host ""
  Write-Host "  Listo: https://$script:GameHost/play" -ForegroundColor Green
  Write-Host "  Cuenta de prueba:  macninja / ninja1234" -ForegroundColor White
  Write-Host "  Panel admin:       https://$script:GameHost/admin  (admin@admin.test / admin)" -ForegroundColor DarkGray
  Write-Host "  Detener servicios:  stop.bat" -ForegroundColor DarkGray
  Write-Host ""

  if (-not $NoBrowser) { Open-GameBrowser }
  Write-Host "  Puedes cerrar esta ventana; los servicios siguen en segundo plano." -ForegroundColor DarkGray
  Write-Host ""
} catch {
  Write-Host ""
  Write-Err $_.Exception.Message
  Write-Host ""
  Write-Host "  Logs: runtime\logs\" -ForegroundColor Yellow
  exit 1
}
