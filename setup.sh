#!/bin/bash

# PROXY GENERATOR PANEL
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

echo -e "${GREEN}Iniciando instalação do Proxy Generator Panel...${NC}"

# Atualização
log "Atualizando pacotes do sistema..."
apt-get update -yq >> "$LOG_FILE" 2>&1
apt-get upgrade -yq >> "$LOG_FILE" 2>&1

# Dependências
log "Instalando dependências..."
install_pkg curl wget unzip zip git apache2 php libapache2-mod-php php-cli php-common php-mbstring php-xml php-curl php-zip squid apache2-utils ufw sudo

# Apache root
log "Configurando Apache para rodar como root..."
sed -i 's/User www-data/User root/' /etc/apache2/apache2.conf
sed -i 's/Group www-data/Group root/' /etc/apache2/apache2.conf
a2enmod rewrite >> "$LOG_FILE" 2>&1
systemctl restart apache2 >> "$LOG_FILE" 2>&1
critical "Falha ao reiniciar Apache"

# Painel
log "Baixando painel web..."
wget -q --show-progress -O /tmp/panel.zip "$PANEL_REPO/panel.zip"
unzip -q -o /tmp/panel.zip -d /var/www/html/
rm -f /tmp/panel.zip

log "Ajustando permissões..."
chmod -R 755 /var/www/html
chown -R root:root /var/www/html
chmod +x /var/www/html/*.php

# Criar pasta de logs com permissões para o PHP
log "Criando diretório de logs com permissões corretas..."
mkdir -p /var/www/html/logs
chown -R www-data:www-data /var/www/html/logs
chmod -R 755 /var/www/html/logs

# Permissão para o Apache reiniciar o Squid via sudo
log "Adicionando permissão no sudoers para restartar squid..."
echo "www-data ALL=NOPASSWD: /bin/systemctl restart squid" > /etc/sudoers.d/99-squid-restart
chmod 440 /etc/sudoers.d/99-squid-restart

# IPv6 opcional
ipv6_block=$(ip -6 addr show scope global | grep -oP 'inet6 \K[0-9a-fA-F:]+(?=::)' | head -n1)
if [[ -n "$ipv6_block" ]]; then
  echo "${ipv6_block}::" > /var/www/html/block_ipv6.txt
  log "IPv6 detectado e salvo: ${ipv6_block}::"
else
  log "Nenhum IPv6 global detectado."
fi

# Script de instalação do Squid (versão dinâmica)
log "Baixando e executando install_proxy.sh com suporte a múltiplas portas..."
wget -q --show-progress -O /tmp/install_proxy.sh "$PANEL_REPO/install_proxy.sh"
chmod +x /tmp/install_proxy.sh
bash /tmp/install_proxy.sh 10000
critical "Falha ao executar install_proxy.sh"

# Firewall
log "Liberando portas do Apache e SSH no firewall..."
ufw allow 80/tcp >> "$LOG_FILE" 2>&1
ufw allow 22/tcp >> "$LOG_FILE" 2>&1
yes | ufw enable >> "$LOG_FILE" 2>&1

# Conclusão
IP=$(curl -s ifconfig.me)

echo -e "${GREEN}Instalação concluída com sucesso!${NC}"
log "Painel disponível em: http://$IP/"
log "Configuração IPv6: http://$IP/ipv6.php"
log "Para gerar proxies: http://$IP/gerar.php?qtd=10"
log "Status do Squid: systemctl status squid"
log "Log de instalação: $LOG_FILE"
