#!/bin/bash

# INSTALADOR 3PROXY
# Luan Alves

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis
LOG_FILE="/var/log/panel_proxy_install.log"
IPV6_FILE="/var/www/html/block_ipv6.txt"
SERVICE_FILE="/etc/systemd/system/panel-proxy.service"

# Funções
die() {
  echo -e "${RED}[ERRO CRÍTICO] $1${NC}" | tee -a "$LOG_FILE"
  exit 1
}

warn() {
  echo -e "${YELLOW}[AVISO] $1${NC}" | tee -a "$LOG_FILE"
}

ok() {
  echo -e "${GREEN}[OK] $1${NC}" | tee -a "$LOG_FILE"
}

info() {
  echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

safe_add_ipv6() {
  local iface=$1
  local ip6=$2
  
  # Verifica formato válido
  if [[ ! "$ip6" =~ ^[0-9a-fA-F:]+::[0-9]+$ ]]; then
    warn "Formato IPv6 inválido: $ip6"
    return 1
  fi

  # Tenta adicionar com diferentes métodos
  for method in "ip -6 addr add $ip6/64 dev $iface" "ifconfig $iface inet6 add $ip6/64"; do
    if eval "$method" 2>> "$LOG_FILE"; then
      ok "IPv6 $ip6 configurado via ${method%% *}"
      return 0
    fi
  done

  # Fallback com sudo se disponível
  if command -v sudo &> /dev/null; then
    if sudo ip -6 addr add $ip6/64 dev $iface 2>> "$LOG_FILE"; then
      ok "IPv6 $ip6 configurado via sudo"
      return 0
    fi
  fi

  warn "Falha ao configurar $ip6"
  echo -e "Execute manualmente como root:"
  echo -e "  ip -6 addr add $ip6/64 dev $iface"
  return 1
}

create_service() {
  cat > "$SERVICE_FILE" << 'EOL'
[Unit]
Description=Panel Proxy Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=root
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=panel-proxy

[Install]
WantedBy=multi-user.target
EOL

  systemctl daemon-reload
  systemctl enable panel-proxy
}

# --- Instalação Principal ---
echo -e "${GREEN}\n>>> INSTALADOR PANEL PROXY <<<${NC}" | tee -a "$LOG_FILE"

# 1. Instalar dependências
info "1. Instalando dependências..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -yq || die "Falha no apt-get update"
apt-get install -yq build-essential gcc make wget tar net-tools || die "Falha ao instalar dependências"

# 2. Compilar 3proxy
info "2. Compilando 3proxy..."
(
  cd /tmp && \
  wget -q https://github.com/z3APA3A/3proxy/archive/0.9.4.tar.gz && \
  tar xzf 0.9.4.tar.gz && \
  cd 3proxy-0.9.4 && \
  make -f Makefile.Linux && \
  make -f Makefile.Linux install
) || die "Falha na instalação do 3proxy"

# 3. Configurar estrutura
info "3. Configurando diretórios..."
mkdir -p /etc/3proxy/{logs,conf} || die "Falha ao criar diretórios"
touch /etc/3proxy/{users.lst,3proxy.cfg} || die "Falha ao criar arquivos"
chmod -R 755 /etc/3proxy || die "Falha ao definir permissões"

# 4. Configurar IPv6
info "4. Configurando IPv6..."

# Habilitar suporte IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=0 || warn "Falha ao habilitar IPv6"
sysctl -w net.ipv6.conf.default.disable_ipv6=0 || warn "Falha ao habilitar IPv6 padrão"

# Configurar bloco IPv6
iface=$(ip route show default | awk '{print $5}' | head -n1)
[ -z "$iface" ] && iface="eth0"

if [ -f "$IPV6_FILE" ]; then
  ipv6_block=$(cat "$IPV6_FILE")
else
  ipv6_block=$(ip -6 addr show scope global | grep -oP 'inet6 \K[0-9a-f:]+' | head -n1 | cut -d: -f1-4)
  [ -n "$ipv6_block" ] && echo "${ipv6_block}::" > "$IPV6_FILE"
fi

if [ -n "$ipv6_block" ] && [ "$ipv6_block" != "::" ]; then
  safe_add_ipv6 "$iface" "${ipv6_block}1" || warn "IPv6 não configurado - Configure manualmente depois"
else
  warn "Nenhum bloco IPv6 detectado - Configure em $IPV6_FILE"
fi

# 5. Criar serviço
info "5. Criando serviço Panel Proxy..."
create_service || die "Falha ao criar serviço"

# Finalização
ok "\nInstalação concluída com sucesso!"
echo -e "Serviço: ${GREEN}panel-proxy${NC}"
echo -e "Comandos úteis:"
echo -e "  Iniciar: ${YELLOW}systemctl start panel-proxy${NC}"
echo -e "  Ver status: ${YELLOW}systemctl status panel-proxy${NC}"
echo -e "  Ver logs: ${YELLOW}journalctl -u panel-proxy -f${NC}"

# Limpeza
rm -rf /tmp/3proxy-0.9.4 /tmp/0.9.4.tar.gz
