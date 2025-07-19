#!/bin/bash

# PROXY GENERATOR PANEL - INSTALADOR FULL AUTO
# Desenvolvido por Luan Alves

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PANEL_REPO="https://raw.githubusercontent.com/luannsr12/proxy_generator/main"
LOG_FILE="/var/log/proxy_panel_install.log"
DEBIAN_FRONTEND=noninteractive

# Verifica root
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}Este script requer permissões de root.${NC}"
  if command -v sudo >/dev/null 2>&1; then
    echo -e "${CYAN}Tentando usar sudo...${NC}"
    exec sudo bash "$0" "$@"
  else
    echo -e "${RED}Erro: sudo não disponível e script não está como root.${NC}"
    exit 1
  fi
fi

log() {
  echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

install_pkg() {
  for pkg in "$@"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
      log "Instalando pacote: $pkg"
      apt-get install -yq "$pkg" >> "$LOG_FILE" 2>&1 || {
        apt-get update -yq >> "$LOG_FILE" 2>&1
        apt-get install -yq "$pkg" >> "$LOG_FILE" 2>&1 || {
          log "${RED}Falha ao instalar: $pkg${NC}"
          exit 1
        }
      }
    fi
  done
}

critical() {
  if [ $? -ne 0 ]; then
    log "${RED}ERRO: $1${NC}"
    exit 1
  fi
}

# Banner
echo -e "${GREEN}"
echo "🔧 Iniciando instalação do Proxy Generator Panel..."
echo -e "${NC}"

# 1. Atualização
log "🔄 Atualizando sistema..."
apt-get update -yq >> "$LOG_FILE" 2>&1
apt-get upgrade -yq >> "$LOG_FILE" 2>&1

# 2. Dependências
log "📦 Instalando dependências..."
install_pkg curl wget unzip zip git build-essential gcc make net-tools iproute2 \
  ufw software-properties-common apt-transport-https ca-certificates gnupg-agent \
  apache2 php libapache2-mod-php php-cli php-common php-mbstring php-xml php-curl php-zip

# 3. Apache
log "🌐 Configurando Apache..."
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

# 4. Baixar painel
log "⬇️ Baixando painel web..."
wget -q --show-progress -O /tmp/panel.zip "$PANEL_REPO/panel.zip"
unzip -q -o /tmp/panel.zip -d /var/www/html/
rm -f /tmp/panel.zip

# 4.1 Permissões
log "🔐 Ajustando permissões do painel..."
chmod -R 755 /var/www/html
chown -R www-data:www-data /var/www/html
chmod +x /var/www/html/*.php

# 4.2 Detectar e salvar IPv6
ipv6_block=$(ip -6 addr show scope global | grep -oP 'inet6 \K[0-9a-fA-F:]+(?=::)' | head -n1)
if [[ -n "$ipv6_block" ]]; then
  echo "${ipv6_block}::" > /var/www/html/block_ipv6.txt
  log "${GREEN}IPv6 detectado e salvo: ${ipv6_block}::${NC}"
else
  log "${YELLOW}Nenhum IPv6 detectado. Configure manualmente no painel.${NC}"
fi

# 5. Baixar e executar install_proxy.sh
log "⚙️ Instalando 3proxy..."
wget -q --show-progress -O /tmp/install_proxy.sh "$PANEL_REPO/install_proxy.sh"
chmod +x /tmp/install_proxy.sh
bash /tmp/install_proxy.sh
critical "Falha ao executar install_proxy.sh"

# 6. Firewall
log "🔥 Configurando firewall..."
ufw allow 80/tcp >> "$LOG_FILE" 2>&1
ufw allow 22/tcp >> "$LOG_FILE" 2>&1
ufw allow 30000:31000/tcp >> "$LOG_FILE" 2>&1
yes | ufw enable >> "$LOG_FILE" 2>&1

# 7. Conclusão
IP=$(curl -s ifconfig.me)
rm -f /tmp/install_proxy.sh

echo -e "${GREEN}"
echo "✅ Instalação concluída com sucesso!"
echo -e "${NC}"

log "Painel: http://$IP/"
log "Config IPv6: http://$IP/ipv6.php"
log "Status 3proxy: systemctl status panel-proxy"
log "Logs: tail -f $LOG_FILE"

echo -e "\n${YELLOW}⚡ Reinstalação:"
echo -e "curl -sSL $PANEL_REPO/setup.sh | bash"
echo -e "${NC}"
