#!/bin/bash

# INSTALADOR 3PROXY COM SERVIÇO SYSTEMD
# Luan Alves

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis
LOG_FILE="/var/log/3proxy_install.log"
IPV6_FILE="/var/www/html/block_ipv6.txt"
SERVICE_FILE="/etc/systemd/system/panel-proxy.service"

# Funções
error() {
  echo -e "${RED}[ERRO] $1${NC}" | tee -a "$LOG_FILE"
  exit 1
}

warning() {
  echo -e "${YELLOW}[AVISO] $1${NC}" | tee -a "$LOG_FILE"
}

success() {
  echo -e "${GREEN}[SUCESSO] $1${NC}" | tee -a "$LOG_FILE"
}

info() {
  echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

create_service() {
  info "Criando serviço PANEL PROXY"
  
  cat > "$SERVICE_FILE" << 'EOL'
[Unit]
Description=Panel Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/3proxy
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=panel-proxy

[Install]
WantedBy=multi-user.target
EOL

  chmod 644 "$SERVICE_FILE"
  systemctl daemon-reload
  systemctl enable panel-proxy.service
}

get_ipv6_block() {
  local ipv6_block=$(ip -6 addr show | grep global | awk '{print $2}' | cut -d'/' -f1 | head -n1 | cut -d':' -f1-4)
  
  if [ -z "$ipv6_block" ]; then
    warning "IPv6 não detectado automaticamente"
    echo -e "${YELLOW}Digite seu bloco IPv6 (ex: 2605:a143:2271:4593::) ou Enter para pular:${NC}"
    read -r user_ipv6
    
    if [ -n "$user_ipv6" ]; then
      echo "$user_ipv6" > "$IPV6_FILE"
      echo "$user_ipv6"
    else
      warning "Continuando sem IPv6 - Configure depois em $IPV6_FILE"
      echo "::" > "$IPV6_FILE"
      echo ""
    fi
  else
    echo "${ipv6_block}::" > "$IPV6_FILE"
    echo "${ipv6_block}::"
  fi
}

configure_ipv6() {
  local iface=$1
  local ip6=$2
  
  if ip -6 addr show dev "$iface" | grep -q "$ip6"; then
    info "IPv6 $ip6 já configurado"
    return 0
  fi
  
  for cmd in "ip -6 addr add $ip6/64 dev $iface" "sudo ip -6 addr add $ip6/64 dev $iface"; do
    if eval "$cmd" 2>> "$LOG_FILE"; then
      success "IPv6 $ip6 configurado"
      return 0
    fi
  done
  
  warning "Falha ao configurar IPv6 automaticamente"
  echo -e "${YELLOW}Execute manualmente como root:"
  echo "ip -6 addr add $ip6/64 dev $iface"
  return 1
}

# Início da instalação
echo -e "${GREEN}\n>>> INSTALADOR PANEL PROXY <<<${NC}" | tee -a "$LOG_FILE"

# 1. Instalar dependências
info "1/5 - Instalando dependências..."
apt-get update -y >> "$LOG_FILE" 2>&1 || error "Falha ao atualizar pacotes"
apt-get install -y build-essential gcc make wget tar net-tools >> "$LOG_FILE" 2>&1 || error "Falha ao instalar dependências"

# 2. Compilar 3proxy
info "2/5 - Compilando 3proxy..."
cd /tmp || error "Falha ao acessar /tmp"
wget https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz >> "$LOG_FILE" 2>&1 || error "Falha ao baixar 3proxy"
tar xzf 0.9.4.tar.gz >> "$LOG_FILE" 2>&1 || error "Falha ao extrair 3proxy"
cd 3proxy-0.9.4 || error "Diretório 3proxy não encontrado"
make -f Makefile.Linux >> "$LOG_FILE" 2>&1 || error "Falha ao compilar 3proxy"
make -f Makefile.Linux install >> "$LOG_FILE" 2>&1 || error "Falha ao instalar 3proxy"

# 3. Configurar diretórios
info "3/5 - Configurando estrutura..."
mkdir -p /etc/3proxy /var/log/3proxy >> "$LOG_FILE" 2>&1
touch /etc/3proxy/users.lst /etc/3proxy/3proxy.cfg >> "$LOG_FILE" 2>&1
chmod -R 755 /etc/3proxy /var/log/3proxy >> "$LOG_FILE" 2>&1

# 4. Configuração de rede
info "4/5 - Configurando rede..."

# Habilitar IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=0 >> "$LOG_FILE" 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >> "$LOG_FILE" 2>&1
echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
sysctl -p >> "$LOG_FILE" 2>&1

# Configurar IPv6
iface=$(ip route show default | awk '{print $5}' | head -n1)
[ -z "$iface" ] && iface="eth0"

ipv6_block=$(get_ipv6_block)
if [ -n "$ipv6_block" ] && [ "$ipv6_block" != "::" ]; then
  configure_ipv6 "$iface" "${ipv6_block}1"
fi

# 5. Criar serviço PANEL PROXY
info "5/5 - Configurando serviço..."
create_service

# Finalização
echo -e "\n${GREEN}=== INSTALAÇÃO CONCLUÍDA ===${NC}" | tee -a "$LOG_FILE"
echo -e "Serviço: ${YELLOW}panel-proxy${NC}" | tee -a "$LOG_FILE"
echo -e "Comandos úteis:" | tee -a "$LOG_FILE"
echo -e "  Iniciar: ${YELLOW}systemctl start panel-proxy${NC}" | tee -a "$LOG_FILE"
echo -e "  Status: ${YELLOW}systemctl status panel-proxy${NC}" | tee -a "$LOG_FILE"
echo -e "  Logs: ${YELLOW}journalctl -u panel-proxy -f${NC}" | tee -a "$LOG_FILE"

# Limpeza
rm -rf /tmp/3proxy-0.9.4 /tmp/0.9.4.tar.gz >> "$LOG_FILE" 2>&1
