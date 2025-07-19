#!/bin/bash

# PROXY GENERATOR PANEL - INSTALADOR COMPLETO
# Versão 3.0 - Instalação Automática com Execução IPv6 + 3proxy
# por Luan Alves

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PANEL_REPO="https://github.com/luannsr12/proxy_generator/raw/main"
LOG_FILE="/var/log/proxy_panel_install.log"
DEBIAN_FRONTEND=noninteractive

log() {
  echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

install_pkg() {
  for pkg in "$@"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
      log "Instalando $pkg..."
      apt-get install -yq "$pkg" >> "$LOG_FILE" 2>&1 || {
        log "${YELLOW}Tentando novamente com update..."
        apt-get update -yq >> "$LOG_FILE" 2>&1
        apt-get install -yq "$pkg" >> "$LOG_FILE" 2>&1 || {
          log "${RED}Falha crítica ao instalar $pkg${NC}"
          return 1
        }
      }
    fi
  done
  return 0
}

critical() {
  if [ $? -ne 0 ]; then
    log "${RED}ERRO: $1${NC}"
    log "Consulte o log: $LOG_FILE"
    exit 1
  fi
}

# Banner inicial
echo -e "${GREEN}"
cat << "EOF"
 ███████████  ███████████      ███████    █████ █████ █████ █████    ███████████    █████████   ██████   █████ ██████████ █████      
░░███░░░░░███░░███░░░░░███   ███░░░░░███ ░░███ ░░███ ░░███ ░░███    ░░███░░░░░███  ███░░░░░███ ░░██████ ░░███ ░░███░░░░░█░░███       
 ░███    ░███ ░███    ░███  ███     ░░███ ░░███ ███   ░░███ ███      ░███    ░███ ░███    ░███  ░███░███ ░███  ░███  █ ░  ░███       
 ░██████████  ░██████████  ░███      ░███  ░░█████     ░░█████       ░██████████  ░███████████  ░███░░███░███  ░██████    ░███       
 ░███░░░░░░   ░███░░░░░███ ░███      ░███   ███░███     ░░███        ░███░░░░░░   ░███░░░░░███  ░███ ░░██████  ░███░░█    ░███       
 ░███         ░███    ░███ ░░███     ███   ███ ░░███     ░███        ░███         ░███    ░███  ░███  ░░█████  ░███ ░   █ ░███      █
 █████        █████   █████ ░░░███████░   █████ █████    █████       █████        █████   █████ █████  ░░█████ ██████████ ███████████
░░░░░        ░░░░░   ░░░░░    ░░░░░░░    ░░░░░ ░░░░░    ░░░░░       ░░░░░        ░░░░░   ░░░░░ ░░░░░    ░░░░░ ░░░░░░░░░░ ░░░░░░░░░░░ 
                                                                                                                                     
                                                                                                                                     
                                                                                                                                      
EOF
echo -e "${NC}"

# 1. Atualizar sistema
log "${YELLOW}[1/8] Atualizando sistema...${NC}"
apt-get update -yq >> "$LOG_FILE" 2>&1
critical "Falha no apt-get update"
apt-get upgrade -yq >> "$LOG_FILE" 2>&1
critical "Falha no apt-get upgrade"

# 2. Instalar dependências
log "${YELLOW}[2/8] Instalando pacotes...${NC}"
install_pkg curl wget unzip zip git build-essential gcc make net-tools \
iproute2 ufw software-properties-common apt-transport-https \
ca-certificates gnupg-agent apache2 php libapache2-mod-php \
php-cli php-common php-mbstring php-xml php-curl php-zip
critical "Falha ao instalar pacotes"

# 3. Configurar Apache
log "${YELLOW}[3/8] Configurando Apache...${NC}"
cat > /etc/apache2/sites-available/000-default.conf << 'EOL'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL

a2enmod rewrite >> "$LOG_FILE" 2>&1
systemctl restart apache2 >> "$LOG_FILE" 2>&1
critical "Falha ao reiniciar Apache"

# 4. Instalar painel
log "${YELLOW}[4/8] Instalando painel web...${NC}"
wget -q --show-progress -O /tmp/panel.zip "$PANEL_REPO/panel.zip"
critical "Falha ao baixar painel"

unzip -q -o /tmp/panel.zip -d /var/www/html/
critical "Falha ao extrair painel"

chown -R www-data:www-data /var/www/html >> "$LOG_FILE" 2>&1
chmod -R 755 /var/www/html >> "$LOG_FILE" 2>&1

# 4.1 Detectar e salvar IPv6
log "${YELLOW}[4.1] Detectando bloco IPv6...${NC}"
ipv6_block=$(ip -6 addr show scope global | grep -oP 'inet6 \K[0-9a-f:]+' | grep '::' | head -n1)
if [[ -n "$ipv6_block" ]]; then
  echo "$ipv6_block" > /var/www/html/block_ipv6.txt
  log "${GREEN}Bloco IPv6 detectado e salvo: $ipv6_block${NC}"
else
  log "${RED}Nenhum bloco IPv6 detectado. Configure via painel manualmente.${NC}"
fi

# 5. Instalar e configurar 3proxy
log "${YELLOW}[5/8] Baixando e executando install_proxy.sh...${NC}"
wget -q --show-progress -O /tmp/install_proxy.sh "$PANEL_REPO/install_proxy.sh"
critical "Falha ao baixar install_proxy.sh"

chmod +x /tmp/install_proxy.sh
/tmp/install_proxy.sh >> "$LOG_FILE" 2>&1
critical "Falha ao executar install_proxy.sh"

# 6. Configurar serviço systemd
log "${YELLOW}[6/8] Configurando serviço do painel...${NC}"
cat > /etc/systemd/system/panel-proxy.service << 'EOL'
[Unit]
Description=Proxy Generator Panel Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=panel-proxy

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload >> "$LOG_FILE" 2>&1
systemctl enable panel-proxy >> "$LOG_FILE" 2>&1
systemctl start panel-proxy >> "$LOG_FILE" 2>&1
critical "Falha ao iniciar serviço"

# 7. Firewall
log "${YELLOW}[7/8] Configurando firewall (UFW)...${NC}"
ufw allow 80/tcp >> "$LOG_FILE" 2>&1
ufw allow 22/tcp >> "$LOG_FILE" 2>&1
ufw allow 30000:31000/tcp >> "$LOG_FILE" 2>&1
echo "y" | ufw enable >> "$LOG_FILE" 2>&1
critical "Falha ao configurar UFW"

# 8. Fim
log "${YELLOW}[8/8] Finalizando...${NC}"
IP=$(curl -s ifconfig.me)
rm -f /tmp/panel.zip /tmp/install_proxy.sh

echo -e "${GREEN}"
cat << "EOF"
 ███████████  ███████████      ███████    █████ █████ █████ █████    ███████████    █████████   ██████   █████ ██████████ █████      
░░███░░░░░███░░███░░░░░███   ███░░░░░███ ░░███ ░░███ ░░███ ░░███    ░░███░░░░░███  ███░░░░░███ ░░██████ ░░███ ░░███░░░░░█░░███       
 ░███    ░███ ░███    ░███  ███     ░░███ ░░███ ███   ░░███ ███      ░███    ░███ ░███    ░███  ░███░███ ░███  ░███  █ ░  ░███       
 ░██████████  ░██████████  ░███      ░███  ░░█████     ░░█████       ░██████████  ░███████████  ░███░░███░███  ░██████    ░███       
 ░███░░░░░░   ░███░░░░░███ ░███      ░███   ███░███     ░░███        ░███░░░░░░   ░███░░░░░███  ░███ ░░██████  ░███░░█    ░███       
 ░███         ░███    ░███ ░░███     ███   ███ ░░███     ░███        ░███         ░███    ░███  ░███  ░░█████  ░███ ░   █ ░███      █
 █████        █████   █████ ░░░███████░   █████ █████    █████       █████        █████   █████ █████  ░░█████ ██████████ ███████████
░░░░░        ░░░░░   ░░░░░    ░░░░░░░    ░░░░░ ░░░░░    ░░░░░       ░░░░░        ░░░░░   ░░░░░ ░░░░░    ░░░░░ ░░░░░░░░░░ ░░░░░░░░░░░ 
EOF
echo -e "${NC}"

log "${GREEN}INSTALAÇÃO COMPLETA!${NC}"
log "Painel: ${YELLOW}http://$IP/${NC}"
log "Config IPv6: ${YELLOW}http://$IP/ipv6.php${NC}"
log "Gerenciar 3proxy: ${YELLOW}systemctl status panel-proxy${NC}"
log "Logs: ${YELLOW}tail -f $LOG_FILE${NC}"

echo -e "\n${YELLOW}=== INSTALAR NOVAMENTE ===${NC}"
echo -e "curl -sSL $PANEL_REPO/setup.sh | bash"
