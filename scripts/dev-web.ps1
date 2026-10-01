# dev-web.ps1 — sobe API + frontend em modo desenvolvimento (Windows/PowerShell).
# API: 127.0.0.1:8123 (api/lbapi.py) | Frontend: http://localhost:5173 (Vite, proxy /api)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$dataDir = if ($env:LBAPI_DATA_DIR) { $env:LBAPI_DATA_DIR } else { ".\data" }
$port = if ($env:LBAPI_PORT) { $env:LBAPI_PORT } else { "8123" }

if (-not (Test-Path $dataDir)) {
  Write-Host "[dev-web] inicializando dados em $dataDir..."
  & ".\bin\lb-init.exe" $dataDir | Out-Null
}

$health = $false
try { Invoke-RestMethod "http://127.0.0.1:$port/api/v1/health" -TimeoutSec 2 | Out-Null; $health = $true } catch {}

if (-not $health) {
  Write-Host "[dev-web] subindo API em 127.0.0.1:$port ..."
  $env:LBAPI_DATA_DIR = $dataDir
  $env:LBAPI_PORT = $port
  Start-Process python -ArgumentList "api/lbapi.py" -WindowStyle Minimized
  Start-Sleep 2
} else {
  Write-Host "[dev-web] API já rodando em 127.0.0.1:$port"
}

Write-Host "[dev-web] subindo Vite em http://localhost:5173 ..."
Set-Location web
npm run dev
