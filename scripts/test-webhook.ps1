<#
.SYNOPSIS
    Simula um trigger do Zabbix enviando um webhook para o n8n.
.DESCRIPTION
    Útil para testar o workflow n8n sem precisar de um evento real do Zabbix.
    Envia um payload idêntico ao que o Media Type do Zabbix enviaria.
.PARAMETER N8nUrl
    URL do webhook do n8n. Padrão: http://localhost:5678/webhook/zabbix-alert
.PARAMETER HostName
    Nome do host simulado.
.PARAMETER HostIp
    IP do host simulado (deve ser acessível via SSH pelo n8n).
.PARAMETER ServiceName
    Nome do serviço Windows a ser testado (ex: wuauserv, spooler, W32Time).
.PARAMETER EventType
    Tipo do evento: PROBLEM ou OK (recuperação).
.PARAMETER EventId
    ID fictício do evento Zabbix.
.EXAMPLE
    .\test-webhook.ps1 -HostIp "192.168.1.50" -ServiceName "Spooler"
.EXAMPLE
    .\test-webhook.ps1 -HostIp "192.168.1.50" -ServiceName "Spooler" -EventType "OK"
#>
param(
    [string]$N8nUrl      = "http://localhost:5678/webhook/zabbix-alert",
    [string]$HostName    = "WIN-SERVER-TEST",
    [string]$HostIp      = "127.0.0.1",
    [string]$ServiceName = "service.info[Spooler,state]",
    [ValidateSet("PROBLEM","OK")]
    [string]$EventType   = "PROBLEM",
    [string]$Severity    = "Average",
    [string]$EventId     = "99999"
)

$payload = @{
    host         = $HostName
    ip           = $HostIp
    trigger_name = "Serviço $ServiceName parado em $HostName"
    trigger_id   = "12345"
    service_name = $ServiceName
    event_id     = $EventId
    event_type   = $EventType
    severity     = $Severity
    timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    event_tags   = "[]"
} | ConvertTo-Json

Write-Host "=== Teste de Webhook n8n/Zabbix ===" -ForegroundColor Cyan
Write-Host "URL:        $N8nUrl" -ForegroundColor White
Write-Host "Host:       $HostName ($HostIp)" -ForegroundColor White
Write-Host "Serviço:    $ServiceName" -ForegroundColor White
Write-Host "Evento:     $EventType" -ForegroundColor White
Write-Host ""
Write-Host "Payload enviado:" -ForegroundColor Yellow
Write-Host $payload
Write-Host ""

try {
    $response = Invoke-RestMethod `
        -Uri $N8nUrl `
        -Method POST `
        -Body $payload `
        -ContentType "application/json" `
        -TimeoutSec 30

    Write-Host "[OK] Resposta do n8n:" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 5
} catch {
    Write-Host "[ERRO] Falha ao enviar webhook:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Verifique se o n8n está rodando: docker compose ps" -ForegroundColor Yellow
    Write-Host "Verifique se o workflow está ativo na interface do n8n." -ForegroundColor Yellow
}
