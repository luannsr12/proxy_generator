#!/bin/bash

# INSTALADOR SQUID
# Luan Alves

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/var/log/squid_install.log"
PASSWD_FILE="/etc/squid/passwd"
PORT_START=30000     # Porta inicial
PORT_QTD=2000        # Quantidade de portas desejadas (modifique conforme necessário)
PORT_END=$((PORT_START + PORT_QTD - 1))

# Verifica root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Este script deve ser executado como root.${NC}" | tee -a "$LOG_FILE"
  exit 1
fi

echo -e "${GREEN}[+] Iniciando instalação do Squid...${NC}" | tee -a "$LOG_FILE"

# 1. Instalar dependências
echo -e "${YELLOW}[1/3] Instalando pacotes necessários...${NC}" | tee -a "$LOG_FILE"
apt-get update -y >>"$LOG_FILE" 2>&1
apt-get install -y squid apache2-utils >>"$LOG_FILE" 2>&1 || {
  echo -e "${RED}Erro: falha ao instalar dependências.${NC}" | tee -a "$LOG_FILE"
  exit 1
}

# 2. Gerar squid.conf dinâmico
echo -e "${YELLOW}[2/3] Configurando Squid com $PORT_QTD portas ($PORT_START-$PORT_END)...${NC}" | tee -a "$LOG_FILE"

{
  echo "auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASSWD_FILE"
  echo "auth_param basic realm Proxy"
  echo "acl authenticated proxy_auth REQUIRED"
  echo "http_access allow authenticated"
  echo "http_access deny all"
  for ((port=PORT_START; port<=PORT_END; port++)); do
    echo "http_port $port"
  done
} > /etc/squid/squid.conf

# 3. Criar arquivo de senhas
touch "$PASSWD_FILE"
chmod 640 "$PASSWD_FILE"
chown proxy:proxy "$PASSWD_FILE"

# 4. Abrir portas no firewall e iniciar serviço
echo -e "${YELLOW}[3/3] Liberando portas no firewall e iniciando Squid...${NC}" | tee -a "$LOG_FILE"
ufw allow ${PORT_START}:${PORT_END}/tcp >>"$LOG_FILE" 2>&1

systemctl enable squid >>"$LOG_FILE" 2>&1
systemctl restart squid >>"$LOG_FILE" 2>&1 || {
  echo -e "${RED}Erro: falha ao iniciar Squid. Verifique o log em $LOG_FILE.${NC}" | tee -a "$LOG_FILE"
  exit 1
}

echo -e "${GREEN}[✓] Squid instalado com sucesso nas portas $PORT_START até $PORT_END.${NC}" | tee -a "$LOG_FILE"
echo -e "${BLUE}Arquivo de senhas: $PASSWD_FILE${NC}" | tee -a "$LOG_FILE"
echo -e "${BLUE}Use 'systemctl status squid' para verificar o serviço.${NC}" | tee -a "$LOG_FILE"
