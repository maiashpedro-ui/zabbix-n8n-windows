# ghost-hosts-report.ps1
# Relatorio de hosts fantasmas: CPU e memoria com uso muito baixo
# Uso: .\ghost-hosts-report.ps1 -ZabbixUrl "https://..." -ApiToken "..." [-CpuThreshold 5] [-MemThreshold 20] [-ExportCsv]

param(
    [string]$ZabbixUrl    = $env:ZABBIX_URL,
    [string]$ApiToken     = $env:ZABBIX_API_TOKEN,
    [double]$CpuThreshold = 5,    # % CPU — abaixo disso é fantasma
    [double]$MemThreshold = 20,   # % Memoria usada — abaixo disso é fantasma
    [int]   $PeriodHours  = 24,   # Periodo de analise em horas
    [switch]$ExportCsv
)

if (-not $ZabbixUrl -or -not $ApiToken) {
    Write-Error "Informe -ZabbixUrl e -ApiToken, ou defina as variaveis ZABBIX_URL e ZABBIX_API_TOKEN."
    exit 1
}

$ApiUrl  = "$ZabbixUrl/api_jsonrpc.php"
$Headers = @{ "Content-Type" = "application/json"; "Authorization" = "Bearer $ApiToken" }

function Invoke-Zabbix($Body) {
    $response = Invoke-RestMethod -Uri $ApiUrl -Method POST -Headers $Headers -Body ($Body | ConvertTo-Json -Depth 10)
    if ($response.error) { throw "Zabbix API erro: $($response.error.data)" }
    return $response.result
}

Write-Host "Buscando hosts monitorados..." -ForegroundColor Cyan

# Busca todos os hosts habilitados
$hosts = Invoke-Zabbix @{
    jsonrpc = "2.0"; id = 1; method = "host.get"
    params  = @{
        output     = @("hostid", "host", "name")
        monitored_hosts = $true
        filter     = @{ status = 0 }
    }
}

Write-Host "Total de hosts: $($hosts.Count)" -ForegroundColor Cyan

$timeFrom = [int][double]::Parse((Get-Date).AddHours(-$PeriodHours).ToUniversalTime().Subtract([datetime]"1970-01-01").TotalSeconds)

$results = @()

foreach ($h in $hosts) {
    # Busca item de CPU
    $cpuItem = Invoke-Zabbix @{
        jsonrpc = "2.0"; id = 2; method = "item.get"
        params  = @{
            output   = @("itemid", "lastvalue", "key_")
            hostids  = $h.hostid
            search   = @{ key_ = "system.cpu.util" }
            sortfield = "key_"
            limit    = 1
        }
    }

    # Busca item de memoria disponivel
    $memItem = Invoke-Zabbix @{
        jsonrpc = "2.0"; id = 3; method = "item.get"
        params  = @{
            output   = @("itemid", "lastvalue", "key_")
            hostids  = $h.hostid
            search   = @{ key_ = "vm.memory.utilization" }
            sortfield = "key_"
            limit    = 1
        }
    }

    # Fallback: vm.memory.size[pused]
    if (-not $memItem -or $memItem.Count -eq 0) {
        $memItem = Invoke-Zabbix @{
            jsonrpc = "2.0"; id = 4; method = "item.get"
            params  = @{
                output   = @("itemid", "lastvalue", "key_")
                hostids  = $h.hostid
                search   = @{ key_ = "vm.memory.size[pused]" }
                limit    = 1
            }
        }
    }

    $cpuVal = if ($cpuItem -and $cpuItem.Count -gt 0) { [math]::Round([double]$cpuItem[0].lastvalue, 1) } else { $null }
    $memVal = if ($memItem -and $memItem.Count -gt 0) { [math]::Round([double]$memItem[0].lastvalue, 1) } else { $null }

    $isGhost = ($cpuVal -ne $null -and $cpuVal -lt $CpuThreshold) -and
               ($memVal -ne $null -and $memVal -lt $MemThreshold)

    $results += [PSCustomObject]@{
        Host      = $h.name
        Hostname  = $h.host
        CPU_pct   = if ($cpuVal -ne $null) { "$cpuVal%" } else { "N/A" }
        Mem_pct   = if ($memVal -ne $null) { "$memVal%" } else { "N/A" }
        Fantasma  = if ($isGhost) { "SIM" } else { "nao" }
    }
}

$ghosts = $results | Where-Object { $_.Fantasma -eq "SIM" }
$noData  = $results | Where-Object { $_.CPU_pct -eq "N/A" -or $_.Mem_pct -eq "N/A" }

Write-Host ""
Write-Host "======================================================" -ForegroundColor Yellow
Write-Host "  HOSTS FANTASMAS (CPU < $CpuThreshold% e Mem < $MemThreshold%)" -ForegroundColor Yellow
Write-Host "  Periodo analisado: ultimas $PeriodHours horas" -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Yellow

if ($ghosts.Count -eq 0) {
    Write-Host "Nenhum host fantasma encontrado." -ForegroundColor Green
} else {
    $ghosts | Format-Table Host, Hostname, CPU_pct, Mem_pct -AutoSize
    Write-Host "Total: $($ghosts.Count) host(s) fantasma(s)" -ForegroundColor Red
}

if ($noData.Count -gt 0) {
    Write-Host ""
    Write-Host "Hosts sem dados de CPU/Memoria (agente inativo ou item nao configurado):" -ForegroundColor DarkYellow
    $noData | Format-Table Host, Hostname, CPU_pct, Mem_pct -AutoSize
}

Write-Host ""
Write-Host "Resumo geral de todos os hosts:" -ForegroundColor Cyan
$results | Sort-Object { [double]($_.CPU_pct -replace '%','') } | Format-Table Host, CPU_pct, Mem_pct, Fantasma -AutoSize

if ($ExportCsv) {
    $csvPath = "ghost-hosts-$(Get-Date -Format 'yyyy-MM-dd_HHmm').csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exportado para: $csvPath" -ForegroundColor Green
}
