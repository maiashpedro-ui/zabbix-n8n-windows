#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Instala o windows-service-agent como serviço Windows (via NSSM ou Task Scheduler).
.DESCRIPTION
    Dois modos:
      -Mode NSSM        : usa NSSM (Not-a-Service Service Manager) — recomendado
      -Mode TaskScheduler: cria uma Scheduled Task que inicia no boot — sem restart
.PARAMETER Mode
    "NSSM" ou "TaskScheduler" (padrão: TaskScheduler)
.PARAMETER Port
    Porta do agente (padrão: 8881)
.PARAMETER SecretKey
    Chave de autenticação — deve coincidir com WIN_AGENT_KEY no .env do n8n
.PARAMETER AgentPath
    Caminho completo para windows-service-agent.ps1
.EXAMPLE
    .\install-service-agent.ps1 -SecretKey "minha-chave-secreta" -Mode TaskScheduler
#>
param(
    [ValidateSet("NSSM", "TaskScheduler")]
    [string]$Mode = "TaskScheduler",

    [int]$Port = 8881,

    [Parameter(Mandatory)]
    [string]$SecretKey,

    [string]$AgentPath = "$PSScriptRoot\windows-service-agent.ps1"
)

$ServiceName = "n8n-ServiceAgent"
$LogPath     = "C:\ProgramData\n8n-agent\agent.log"

Write-Host "=== Instalando n8n Windows Service Agent ===" -ForegroundColor Cyan

# Garantir que o script existe
if (-not (Test-Path $AgentPath)) {
    Write-Error "Script nao encontrado: $AgentPath"
    exit 1
}

# Criar diretório de log
New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null

# Adicionar regra de firewall
$fwRule = Get-NetFirewallRule -Name "n8n-ServiceAgent-$Port" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule `
        -Name "n8n-ServiceAgent-$Port" `
        -DisplayName "n8n Service Agent (porta $Port)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow | Out-Null
    Write-Host "[OK] Regra de firewall criada para porta $Port" -ForegroundColor Green
} else {
    Write-Host "[OK] Regra de firewall já existe." -ForegroundColor Green
}

if ($Mode -eq "TaskScheduler") {
    # ----- Task Scheduler -----
    Write-Host "[...] Criando Scheduled Task '$ServiceName'..." -ForegroundColor Yellow

    $psArgs = "-NonInteractive -ExecutionPolicy Bypass -File `"$AgentPath`" -Port $Port -SecretKey `"$SecretKey`""
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArgs
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -RestartOnIdle -ExecutionTimeLimit (New-TimeSpan -Hours 0) -MultipleInstances IgnoreNew

    # Remover se já existir
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false -ErrorAction SilentlyContinue

    Register-ScheduledTask `
        -TaskName  $ServiceName `
        -Action    $action `
        -Trigger   $trigger `
        -Principal $principal `
        -Settings  $settings `
        -Description "Agente HTTP para reiniciar servicos Windows via n8n" | Out-Null

    # Iniciar AGORA (sem precisar reiniciar)
    Start-ScheduledTask -TaskName $ServiceName
    Start-Sleep -Seconds 3

    $state = (Get-ScheduledTask -TaskName $ServiceName).State
    Write-Host "[OK] Task '$ServiceName' criada e iniciada — estado: $state" -ForegroundColor Green

} else {
    # ----- NSSM -----
    $nssmPath = (Get-Command nssm -ErrorAction SilentlyContinue)?.Source
    if (-not $nssmPath) {
        Write-Error "NSSM nao encontrado no PATH. Baixe em https://nssm.cc/ ou use -Mode TaskScheduler"
        exit 1
    }

    Write-Host "[...] Instalando serviço NSSM '$ServiceName'..." -ForegroundColor Yellow
    & nssm stop    $ServiceName 2>$null
    & nssm remove  $ServiceName confirm 2>$null
    & nssm install $ServiceName "powershell.exe" "-NonInteractive -ExecutionPolicy Bypass -File `"$AgentPath`" -Port $Port -SecretKey `"$SecretKey`""
    & nssm set     $ServiceName AppStdout $LogPath
    & nssm set     $ServiceName AppStderr $LogPath
    & nssm set     $ServiceName Start SERVICE_AUTO_START
    & nssm start   $ServiceName
    Write-Host "[OK] Serviço NSSM '$ServiceName' instalado e iniciado." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Instalação concluída ===" -ForegroundColor Green
Write-Host "Agente escutando em  : http://0.0.0.0:$Port/restart" -ForegroundColor Cyan
Write-Host "Chave configurada    : $SecretKey" -ForegroundColor Cyan
Write-Host "Log                  : $LogPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Teste rápido (execute no servidor n8n/Ubuntu):" -ForegroundColor Yellow
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress
Write-Host "  curl -s -X POST http://${ip}:${Port}/restart \\" -ForegroundColor Gray
Write-Host "    -H 'Authorization: Bearer $SecretKey' \\" -ForegroundColor Gray
Write-Host "    -H 'Content-Type: application/json' \\" -ForegroundColor Gray
Write-Host "    -d '{\"service_name\":\"Spooler\"}'" -ForegroundColor Gray
