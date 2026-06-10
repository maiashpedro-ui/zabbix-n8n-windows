# n8n + Zabbix — Remediação Automática de Serviços Windows

Automação que detecta serviços Windows parados via Zabbix e executa remediação automática (reinicialização) via n8n + SSH/PowerShell, sem intervenção manual.

## Fluxo

```
Zabbix 7.x                      n8n (Docker)                   Windows Server
───────────                      ────────────                   ──────────────
Trigger disparado   ──Webhook──► Recebe alerta
(serviço parado)                 ↓
                                 É PROBLEMA?  ──Sim──► SSH → Start-Service
                                 ↓                     ↓
                                 RECUPERAÇÃO?          Sucesso? ──Sim──► Comentário no Zabbix
                                 Loga evento           ↓
                                                       Não ──► Comentário + Teams (escalada)
```

## Pré-requisitos

| Componente | Requisito |
|---|---|
| Zabbix Server | 7.x instalado e monitorando os hosts |
| Docker + Docker Compose | Para rodar o n8n |
| Windows Servers | OpenSSH Server instalado (script fornecido) |
| Rede | n8n alcança porta 22 dos Windows Servers |

## Início Rápido

### 1. Preparar o ambiente

```powershell
# Clone ou copie este repositório
cd "C:\path\to\zabbix-n8n-windows"

# Copie e edite as variáveis de ambiente
cp .env.example .env
notepad .env
```

Edite `.env` e preencha obrigatoriamente:
- `WEBHOOK_URL` — IP/hostname do servidor onde o n8n rodará (acessível pelo Zabbix)
- `POSTGRES_PASSWORD` e `N8N_BASIC_AUTH_PASSWORD` — senhas seguras
- `ZABBIX_URL` e `ZABBIX_API_TOKEN` — para comentar eventos automaticamente

### 2. Subir o n8n

```powershell
docker compose up -d
docker compose ps   # verifique se ambos os containers estão healthy
```

Acesse a interface em `http://localhost:5678` com as credenciais definidas em `.env`.

### 3. Gerar chave SSH no servidor do n8n

```bash
# Execute dentro do container n8n (ou no servidor host)
docker compose exec n8n ssh-keygen -t ed25519 -C "n8n-zabbix" -f /home/node/.n8n/n8n_ed25519 -N ""
docker compose exec n8n cat /home/node/.n8n/n8n_ed25519.pub
```

Copie o conteúdo da chave pública.

### 4. Configurar OpenSSH nos Windows Servers

Execute em **cada servidor Windows** como Administrador:

```powershell
# Substitua o conteúdo da chave pela copiada no passo anterior
.\scripts\enable-openssh.ps1 -AuthorizedKey "ssh-ed25519 AAAA... n8n-zabbix"
```

### 5. Configurar credencial SSH no n8n

1. Acesse **n8n → Settings → Credentials → Add Credential**
2. Tipo: **SSH**
3. Nome: `Windows Servers SSH`
4. Authentication: **Private Key**
5. Cole o conteúdo da chave privada (`n8n_ed25519`)
6. Username: `administrator` (ou o usuário configurado)

### 6. Importar o workflow no n8n

1. Acesse **n8n → Workflows → Import from File**
2. Selecione `workflows/zabbix-windows-remediation.json`
3. Abra o node **SSH — Reiniciar Serviço** e selecione a credencial criada
4. Ative o workflow (toggle no canto superior direito)
5. Copie a URL do webhook exibida no node **Webhook Zabbix**

### 7. Configurar o Zabbix

Siga as instruções em [zabbix-config/README.md](zabbix-config/README.md):
1. Importar o Media Type (`media-type-n8n-webhook.xml`)
2. Atualizar a URL do n8n no Media Type
3. Associar o Media Type ao usuário
4. Importar a Action (`action-service-remediation.xml`)

### 8. Testar

```powershell
# Simula um trigger do Zabbix (substitua o IP pelo de um Windows Server real)
.\scripts\test-webhook.ps1 -HostIp "192.168.1.50" -ServiceName "service.info[Spooler,state]"
```

Verifique nos logs do n8n se a execução ocorreu e no servidor Windows se o serviço foi reiniciado.

## Estrutura do Projeto

```
zabbix-n8n-windows/
├── docker-compose.yml              # n8n + PostgreSQL
├── .env.example                    # Template de variáveis
├── .gitignore
├── workflows/
│   └── zabbix-windows-remediation.json   # Workflow principal
├── zabbix-config/
│   ├── media-type-n8n-webhook.xml        # Media Type (importar no Zabbix)
│   ├── action-service-remediation.xml    # Action (importar no Zabbix)
│   └── README.md                         # Guia passo a passo do Zabbix
├── scripts/
│   ├── enable-openssh.ps1                # Habilita SSH nos Windows Servers
│   └── test-webhook.ps1                  # Testa o webhook sem Zabbix real
└── README.md
```

## Payload Zabbix → n8n

O Media Type envia este JSON para o n8n:

```json
{
  "host":         "WIN-SERVER-01",
  "ip":           "192.168.1.50",
  "trigger_name": "Serviço Spooler parado em WIN-SERVER-01",
  "trigger_id":   "12345",
  "service_name": "service.info[Spooler,state]",
  "event_id":     "67890",
  "event_type":   "PROBLEM",
  "severity":     "Average",
  "timestamp":    "2026-06-10 10:30:00",
  "event_tags":   "[]"
}
```

O n8n extrai o nome do serviço do campo `service_name` (ex: `Spooler` de `service.info[Spooler,state]`).

## Adicionando Mais Serviços

Não é necessário modificar o workflow. Qualquer trigger do Zabbix que:
1. Tenha `service_name` no formato `service.info[NomeDoServico,state]`
2. Seja enviado via o Media Type configurado

...será tratado automaticamente. O n8n extrai o nome do serviço e executa `Start-Service`.

## Segurança

- O usuário SSH deve ter permissão mínima para reiniciar serviços via PowerShell
- Considere criar um usuário dedicado com JEA (Just Enough Administration) em ambientes de produção
- O arquivo `.env` está no `.gitignore` — nunca commite credenciais
- Restrinja o acesso ao endpoint webhook por IP no firewall ou via proxy reverso com HTTPS
