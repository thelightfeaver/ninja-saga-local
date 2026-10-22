$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

. "$PSScriptRoot\windows-common.ps1"

try {
  Stop-LocalServices
} catch {
  Write-Err $_.Exception.Message
  exit 1
}
