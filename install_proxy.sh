#!/bin/bash

# INSTALADOR 3PROXY
# Luan Alves
# Corrigido para rodar SEM sudo (deve ser executado como root)

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/var/log/proxy_install.log"
IPV6_FILE="/var/www/html/block_ipv6.txt"

# Garante execução como root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Este script deve ser executado como root.${NC}"
  exit 1
fi

add_ipv6_address() {
  local iface=$1
  local ip6=$2

  echo -e "${BLUE}Configurando IPv6: $ip6/64 na interface $iface...${NC}" | tee -a "$LOG_FILE"
  
  ip -6 addr add "$ip6/64" dev "$iface" 2>>"$LOG_FILE" && return 0

  if command -v ifconfig &> /dev/null; then
    ifconfig "$iface" inet6 add "$ip6/64" 2>>"$LOG_FILE" && return 0
  fi

  echo -e "${YELLOW}Falha ao configurar $ip6/64. Tente manualmente.${NC}" | tee -a "$LOG_FILE"
  return 1
}

echo -e "${GREEN}[+] Iniciando instalação do 3proxy...${NC}" | tee -a "$LOG_FILE"

# 1. Dependências
echo -e "${YELLOW}[1/5] Instalando pacotes necessários...${NC}" | tee -a "$LOG_FILE"
apt-get update -y >>"$LOG_FILE" 2>&1
apt-get install -y build-essential gcc make wget tar net-tools iproute2 >>"$LOG_FILE" 2>&1 || {
  echo -e "${RED}Erro: falha ao instalar dependências.${NC}" | tee -a "$LOG_FILE"
  exit 1
}

# 2. Compilar 3proxy
echo -e "${YELLOW}[2/5] Baixando e compilando 3proxy...${NC}" | tee -a "$LOG_FILE"
cd /tmp || exit 1
wget -q https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz
tar xzf 0.9.4.tar.gz
cd 3proxy-0.9.4 || exit 1
make -f Makefile.Linux >>"$LOG_FILE" 2>&1
make -f Makefile.Linux install >>"$LOG_FILE" 2>&1

# 3. Diretórios e arquivos
echo -e "${YELLOW}[3/5] Configurando arquivos do 3proxy...${NC}" | tee -a "$LOG_FILE"
mkdir -p /etc/3proxy /var/log/3proxy
touch /etc/3proxy/users.lst /etc/3proxy/3proxy.cfg
chmod -R 755 /etc/3proxy /var/log/3proxy

# 4. IPv6
echo -e "${YELLOW}[4/5] Configurando IPv6...${NC}" | tee -a "$LOG_FILE"
sysctl -w net.ipv6.conf.all.disable_ipv6=0
sysctl -w net.ipv6.conf.default.disable_ipv6=0
echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
sysctl -p >>"$LOG_FILE" 2>&1

iface=$(ip -6 route show default | awk '{print $5}' | head -n1)
[ -z "$iface" ] && iface=$(ip -4 route show default | awk '{print $5}' | head -n1)
[ -z "$iface" ] && iface="eth0"

if [ -f "$IPV6_FILE" ]; then
  ipv6_block=$(cat "$IPV6_FILE")
  if [[ "$ipv6_block" =~ ^[0-9a-fA-F:]+::$ ]]; then
    for i in {1..10}; do
      ip6="${ipv6_block}${i}"
      add_ipv6_address "$iface" "$ip6"
    done
  else
    echo -e "${YELLOW}Bloco inválido no arquivo $IPV6_FILE.${NC}" | tee -a "$LOG_FILE"
  fi
else
  echo -e "${YELLOW}Arquivo $IPV6_FILE não encontrado. Configure pelo painel web.${NC}" | tee -a "$LOG_FILE"
fi

# 5. systemd
echo -e "${YELLOW}[5/5] Criando serviço systemd...${NC}" | tee -a "$LOG_FILE"
cat > /etc/systemd/system/panel-proxy.service << 'EOF'
[Unit]
Description=Panel Proxy Service
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
EOF

systemctl daemon-reload
systemctl enable panel-proxy
systemctl restart panel-proxy

echo -e "${GREEN}[✓] Instalação concluída.${NC}" | tee -a "$LOG_FILE"
echo -e "${CYAN}Use: systemctl status panel-proxy${NC}" | tee -a "$LOG_FILE"
