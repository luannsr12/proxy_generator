#!/bin/bash

# INSTALADOR SQUID COM MÚLTIPLAS PORTAS
# Luan Alves
# Instala Squid com autenticação em várias portas para uso com painel PHP

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/var/log/squid_install.log"

# Garante execução como root
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

# 2. Configurar Squid com múltiplas portas
echo -e "${YELLOW}[2/3] Configurando Squid com 1000 portas (3128-4127)...${NC}" | tee -a "$LOG_FILE"
cat > /etc/squid/squid.conf << 'EOF'
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
EOF

# Adicionar 1000 portas (3128 a 4127)
for port in {3128..4127}; do
  echo "http_port $port" >> /etc/squid/squid.conf
done

# Criar arquivo de senhas vazio
touch /etc/squid/passwd
chmod 640 /etc/squid/passwd
chown proxy:proxy /etc/squid/passwd

# 3. Abrir portas no firewall e iniciar serviço
echo -e "${YELLOW}[3/3] Configurando firewall e iniciando Squid...${NC}" | tee -a "$LOG_FILE"
ufw allow 3128:4127/tcp >>"$LOG_FILE" 2>&1
systemctl enable squid >>"$LOG_FILE" 2>&1
systemctl restart squid >>"$LOG_FILE" 2>&1 || {
  echo -e "${RED}Erro: falha ao iniciar Squid. Verifique logs em $LOG_FILE.${NC}" | tee -a "$LOG_FILE"
  exit 1
}

echo -e "${GREEN}[✓] Instalação concluída. Squid rodando nas portas 3128 a 4127.${NC}" | tee -a "$LOG_FILE"
echo -e "${BLUE}Arquivo de senhas (/etc/squid/passwd) pronto para uso com painel PHP.${NC}" | tee -a "$LOG_FILE"
echo -e "${BLUE}Use 'systemctl status squid' para verificar o serviço.${NC}" | tee -a "$LOG_FILE"
