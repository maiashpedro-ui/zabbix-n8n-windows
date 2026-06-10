#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Habilita OpenSSH Server no Windows Server para integração com n8n.
.DESCRIPTION
    Instala o OpenSSH Server, configura o firewall, inicia o serviço e
    adiciona a chave pública SSH autorizada para o usuário administrador.
.PARAMETER AuthorizedKey
    Conteúdo da chave pública SSH (id_ed25519.pub ou id_rsa.pub) gerada
    no servidor onde o n8n está rodando.
.EXAMPLE
    .\enable-openssh.ps1 -AuthorizedKey "ssh-ed25519 AAAA... user@n8n-server"
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$AuthorizedKey = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== Configurando OpenSSH Server para integração n8n/Zabbix ===" -ForegroundColor Cyan

# 1. Verificar se já está instalado
$sshFeature = Get-WindowsCapability -Online -Name OpenSSH.Server* | Select-Object -First 1
if ($sshFeature.State -eq "Installed") {
    Write-Host "[OK] OpenSSH Server já instalado." -ForegroundColor Green
} else {
    Write-Host "[...] Instalando OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Write-Host "[OK] OpenSSH Server instalado." -ForegroundColor Green
}

# 2. Iniciar e configurar serviço para início automático
Write-Host "[...] Configurando serviço sshd..." -ForegroundColor Yellow
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Write-Host "[OK] Serviço sshd iniciado e configurado para início automático." -ForegroundColor Green

# 3. Configurar firewall
$fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    Write-Host "[...] Criando regra de firewall para porta 22..." -ForegroundColor Yellow
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null
    Write-Host "[OK] Regra de firewall criada." -ForegroundColor Green
} else {
    Write-Host "[OK] Regra de firewall já existe." -ForegroundColor Green
}

# 4. Definir PowerShell como shell padrão para SSH
$registryPath = "HKLM:\SOFTWARE\OpenSSH"
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}
$pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwshPath) {
    $pwshPath = (Get-Command powershell).Source
}
Set-ItemProperty -Path $registryPath -Name DefaultShell -Value $pwshPath
Write-Host "[OK] Shell padrão SSH configurado: $pwshPath" -ForegroundColor Green

# 5. Adicionar chave pública autorizada (se fornecida)
if ($AuthorizedKey -ne "") {
    # Para administradores, o arquivo fica em ProgramData (não no perfil)
    $adminKeysFile = "$env:ProgramData\ssh\administrators_authorized_keys"

    if (-not (Test-Path "$env:ProgramData\ssh")) {
        New-Item -ItemType Directory -Path "$env:ProgramData\ssh" -Force | Out-Null
    }

    # Verificar se a chave já está no arquivo
    $existingKeys = if (Test-Path $adminKeysFile) { Get-Content $adminKeysFile } else { @() }
    if ($existingKeys -notcontains $AuthorizedKey) {
        Add-Content -Path $adminKeysFile -Value $AuthorizedKey
        Write-Host "[OK] Chave pública adicionada em: $adminKeysFile" -ForegroundColor Green
    } else {
        Write-Host "[OK] Chave pública já estava no arquivo." -ForegroundColor Green
    }

    # Corrigir permissões do arquivo (obrigatório para o OpenSSH no Windows)
    icacls $adminKeysFile /inheritance:r /grant "SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)" | Out-Null
    Write-Host "[OK] Permissões do arquivo de chaves configuradas." -ForegroundColor Green
} else {
    Write-Host "[AVISO] Nenhuma chave pública fornecida. Adicione manualmente em:" -ForegroundColor Yellow
    Write-Host "        $env:ProgramData\ssh\administrators_authorized_keys" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Configuração concluída! ===" -ForegroundColor Green
Write-Host "Próximos passos:" -ForegroundColor Cyan
Write-Host "  1. Gere um par de chaves SSH no servidor do n8n:" -ForegroundColor White
Write-Host "     ssh-keygen -t ed25519 -C 'n8n-zabbix-automation'" -ForegroundColor Gray
Write-Host "  2. Copie o conteúdo de id_ed25519.pub e execute este script com -AuthorizedKey" -ForegroundColor White
Write-Host "  3. Teste a conexão do servidor n8n: ssh administrator@$(hostname)" -ForegroundColor White
Write-Host "  4. Configure a credencial SSH no n8n (Administration → Credentials)" -ForegroundColor White
