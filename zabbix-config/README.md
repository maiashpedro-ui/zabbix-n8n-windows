# Configuração do Zabbix

## 1. Importar o Media Type

1. Acesse **Administration → Media Types**
2. Clique em **Import** (canto superior direito)
3. Selecione o arquivo `media-type-n8n-webhook.xml`
4. Após importar, abra o Media Type e **edite o parâmetro `n8n_url`**:
   ```
   http://SEU_IP:5678/webhook/zabbix-alert
   ```
5. Clique em **Update**

## 2. Associar o Media Type ao Usuário Admin

1. Acesse **Administration → Users**
2. Abra o usuário `Admin` (ou o usuário que receberá os alertas)
3. Aba **Media** → clique em **Add**
4. Tipo: **n8n Webhook — Windows Service Remediation**
5. Enviar para: deixe o padrão
6. Clique em **Add** → **Update**

## 3. Importar a Action

1. Acesse **Alerts → Actions → Trigger Actions**
2. Clique em **Import**
3. Selecione o arquivo `action-service-remediation.xml`
4. Revise o filtro e ajuste o **Host Group** se necessário (padrão: `Windows Servers`)

## 4. Verificar Templates de Monitoramento de Serviços

Certifique-se de que os hosts Windows têm o item de monitoramento de serviços:
- Template recomendado: **Windows by Zabbix agent**
- O item relevante é do tipo: `service.info[{SERVICE_NAME},state]`

### Criar Trigger Manual (se necessário)

Se o trigger de serviço parado ainda não existir no template:

1. Acesse o template ou host → **Triggers** → **Create Trigger**
2. Nome: `Serviço {ITEM.KEY1} parado em {HOST.NAME}`
3. Expressão:
   ```
   last(/NomeDoHost/service.info[NomeDoServico,state])<>0
   ```
4. Severidade: **Average** ou **High**
5. Tags: `component:service`

## 5. Testar o Media Type

1. Acesse o Media Type importado
2. Clique em **Test**
3. Preencha os parâmetros e clique em **Test** — deve retornar `OK`
