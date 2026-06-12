#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Agente HTTP leve para reiniciar serviços Windows via n8n.
.DESCRIPTION
    Abre um listener HTTP na porta configurada. O n8n envia um POST com o
    nome do serviço e o agente executa Start-Service localmente.
    Deve ser iniciado como um serviço (via NSSM ou Task Scheduler).
.PARAMETER Port
    Porta HTTP em que o agente escuta (padrão: 8881).
.PARAMETER SecretKey
    Chave de autenticação. Deve coincidir com WIN_AGENT_KEY no n8n.
.EXAMPLE
    .\windows-service-agent.ps1 -Port 8881 -SecretKey "troque-por-chave-segura"
#>
param(
    [int]$Port = 8881,
    [string]$SecretKey = "CHANGE_ME"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [hashtable]$Body
    )
    $json = $Body | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}

# Iniciar listener
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:$Port/")

try {
    $listener.Start()
    Write-Log "Agente iniciado em http://+:$Port/"
} catch {
    Write-Log "Erro ao iniciar listener: $($_.Exception.Message)" "ERROR"
    Write-Log "Execute como Administrador e verifique se a porta $Port está livre." "ERROR"
    exit 1
}

Write-Log "Aguardando requisições..."

while ($listener.IsListening) {
    try {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response
        $clientIp = $request.RemoteEndPoint.Address.ToString()

        Write-Log "[$clientIp] $($request.HttpMethod) $($request.Url.PathAndQuery)"

        # Apenas POST em /restart
        if ($request.HttpMethod -ne "POST" -or $request.Url.LocalPath -ne "/restart") {
            Send-Response -Response $response -StatusCode 404 -Body @{ status = "error"; message = "Not found" }
            continue
        }

        # Validar Authorization header
        $authHeader = $request.Headers["Authorization"]
        if ($authHeader -ne "Bearer $SecretKey") {
            Write-Log "[$clientIp] Autenticação inválida." "WARN"
            Send-Response -Response $response -StatusCode 401 -Body @{ status = "error"; message = "Unauthorized" }
            continue
        }

        # Ler body
        $reader = [System.IO.StreamReader]::new($request.InputStream, [System.Text.Encoding]::UTF8)
        $rawBody = $reader.ReadToEnd()
        $body = $rawBody | ConvertFrom-Json

        $serviceName = $body.service_name
        if (-not $serviceName) {
            Send-Response -Response $response -StatusCode 400 -Body @{ status = "error"; message = "service_name obrigatorio" }
            continue
        }

        Write-Log "Reiniciando serviço: '$serviceName'"

        # Verificar se o serviço existe
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Log "Serviço '$serviceName' não encontrado." "WARN"
            Send-Response -Response $response -StatusCode 404 -Body @{
                status  = "error"
                message = "Servico nao encontrado: $serviceName"
                service = $serviceName
            }
            continue
        }

        # Reiniciar
        Start-Service -Name $serviceName -ErrorAction Stop
        Start-Sleep -Seconds 2
        $statusAfter = (Get-Service -Name $serviceName).Status.ToString()

        Write-Log "Serviço '$serviceName' — status: $statusAfter"

        Send-Response -Response $response -StatusCode 200 -Body @{
            status       = "success"
            service_name = $serviceName
            state        = $statusAfter
            host         = $env:COMPUTERNAME
        }

    } catch {
        Write-Log "Erro ao processar requisição: $($_.Exception.Message)" "ERROR"
        try {
            Send-Response -Response $context.Response -StatusCode 500 -Body @{
                status  = "error"
                message = $_.Exception.Message
            }
        } catch { }
    }
}
