#!/bin/bash

# SETUP COMPLETO PARA PAINEL 3PROXY - MÁQUINA CRUA
# Versão Robusta 2.0 - Instala TUDO automaticamente

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variáveis
PANEL_REPO="https://github.com/seu-usuario/seu-repo/raw/main"
LOG_FILE="/var/log/proxy_panel_install.log"
DEBIAN_FRONTEND=noninteractive

# Função de log
log() {
  echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Função para verificar e instalar pacotes
install_pkg() {
  for pkg in "$@"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
      log "Instalando $pkg..."
      apt-get install -yq "$pkg" >> "$LOG_FILE" 2>&1
      if [ $? -ne 0 ]; then
        log "${RED}Falha ao instalar $pkg${NC}"
        apt-get update -yq >> "$LOG_FILE" 2>&1
        apt-get install -yq "$pkg" >> "$LOG_FILE" 2>&1 || {
          log "${RED}Erro crítico: Falha ao instalar $pkg após tentativa${NC}";
          exit 1;
        }
      fi
    else
      log "$pkg já instalado"
    fi
  done
}

# Função para verificar e tratar erros críticos
critical() {
  if [ $? -ne 0 ]; then
    log "${RED}ERRO CRÍTICO: $1${NC}"
    log "Verifique o log completo em: $LOG_FILE"
    exit 1
  fi
}

# Iniciando instalação
echo -e "${GREEN}"
cat << "EOF"
  ___  _  _ ___ ___ ___   _____ _____ ___  ___ _____ 
 | _ \| \| | _ \_ _/ __| |_   _|_   _/ _ \| _ \_   _|
 |  _/| .` |  _/| |\__ \   | |   | || (_) |   / | |  
 |_|  |_|\_|_| |___|___/   |_|   |_| \___/|_|_\ |_|  
EOF
echo -e "${NC}"

log "Iniciando instalação completa do painel de proxies..."

# 1. Atualizar sistema base
log "${YELLOW}[1/8] Atualizando sistema operacional...${NC}"
apt-get update -yq >> "$LOG_FILE" 2>&1
critical "Falha ao atualizar repositórios"
apt-get upgrade -yq >> "$LOG_FILE" 2>&1
critical "Falha ao atualizar sistema"

# 2. Instalar dependências essenciais
log "${YELLOW}[2/8] Instalando dependências básicas...${NC}"
install_pkg curl wget unzip zip git build-essential gcc make net-tools \
iproute2 ufw software-properties-common apt-transport-https ca-certificates \
gnupg-agent

# 3. Instalar e configurar Apache + PHP
log "${YELLOW}[3/8] Instalando Apache e PHP...${NC}"
install_pkg apache2 php libapache2-mod-php php-cli php-common \
php-mbstring php-xml php-curl php-zip

# Configurar Apache
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
critical "Falha ao ativar mod_rewrite"
systemctl restart apache2 >> "$LOG_FILE" 2>&1
critical "Falha ao reiniciar Apache"

# 4. Baixar e extrair painel
log "${YELLOW}[4/8] Configurando painel...${NC}"
wget -q --show-progress -O /tmp/panel.zip "$PANEL_REPO/panel.zip"
critical "Falha ao baixar painel"

unzip -q -o /tmp/panel.zip -d /var/www/html/
critical "Falha ao extrair painel"

# Corrigir permissões
chown -R www-data:www-data /var/www/html >> "$LOG_FILE" 2>&1
chmod -R 755 /var/www/html >> "$LOG_FILE" 2>&1

# 5. Instalar 3proxy
log "${YELLOW}[5/8] Instalando 3proxy...${NC}"
wget -q --show-progress -O /tmp/install_proxy.sh "$PANEL_REPO/install_proxy.sh"
critical "Falha ao baixar instalador do proxy"

chmod +x /tmp/install_proxy.sh
/tmp/install_proxy.sh >> "$LOG_FILE" 2>&1
critical "Falha durante instalação do 3proxy"

# 6. Configurar serviços automáticos
log "${YELLOW}[6/8] Configurando inicialização automática...${NC}"

# Serviço 3proxy
cat > /etc/systemd/system/3proxy.service << 'EOL'
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload >> "$LOG_FILE" 2>&1
systemctl enable 3proxy >> "$LOG_FILE" 2>&1
systemctl start 3proxy >> "$LOG_FILE" 2>&1
critical "Falha ao configurar serviço 3proxy"

# 7. Configurar firewall
log "${YELLOW}[7/8] Configurando firewall...${NC}"
ufw allow 80/tcp >> "$LOG_FILE" 2>&1
ufw allow 22/tcp >> "$LOG_FILE" 2>&1
ufw allow 30000:31000/tcp >> "$LOG_FILE" 2>&1
echo "y" | ufw enable >> "$LOG_FILE" 2>&1
critical "Falha ao configurar firewall"

# 8. Finalização
log "${YELLOW}[8/8] Finalizando instalação...${NC}"
IP=$(curl -4 -s ifconfig.me)
critical "Falha ao obter IP público"

# Limpeza
rm -f /tmp/panel.zip /tmp/install_proxy.sh >> "$LOG_FILE" 2>&1

# Relatório final
echo -e "${GREEN}"
cat << "EOF"
 ___  _  _  ___  ___   ___  _  _  ___  ___   ___  _  _  ___ 
| _ \| \| ||_ _|/ __| | _ \| \| ||_ _|/ __| | _ \| \| ||_ _|
|  _/| .` | | | \__ \ |  _/| .` | | | \__ \ |  _/| .` | | | 
|_|  |_|\_||___||___/ |_|  |_|\_||___||___/ |_|  |_|\_||___|
EOF
echo -e "${NC}"

log "${GREEN}INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
log "Painel disponível em: ${YELLOW}http://$IP/${NC}"
log "Configuração IPv6 em: ${YELLOW}http://$IP/ipv6.php${NC}"
log "Visualizar log completo: ${YELLOW}tail -f $LOG_FILE${NC}"
log "Reiniciar 3proxy: ${YELLOW}systemctl restart 3proxy${NC}"
log "Monitorar proxies: ${YELLOW}tail -f /etc/3proxy/logs/3proxy.log${NC}"

echo -e "\n${YELLOW}=== COMANDO PARA ACESSO RÁPIDO ===${NC}"
echo -e "curl -s $PANEL_REPO/setup.sh | bash"
echo -e "${YELLOW}==================================${NC}"
