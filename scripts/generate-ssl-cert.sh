#!/bin/bash
# Gera certificado SSL autoassinado para o nginx
# Execute no servidor onde o docker-compose roda

CERT_DIR="$(dirname "$0")/../nginx/ssl"
mkdir -p "$CERT_DIR"

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$CERT_DIR/n8n.key" \
  -out "$CERT_DIR/n8n.crt" \
  -subj "/C=BR/ST=ES/L=Vitoria/O=TI/OU=Automacao/CN=n8n-zabbix" \
  -addext "subjectAltName=IP:$(hostname -I | awk '{print $1}')"

chmod 600 "$CERT_DIR/n8n.key"
echo "Certificado gerado em $CERT_DIR"
echo "Adicione o arquivo n8n.crt como CA confiável no servidor Zabbix para evitar erros SSL"
