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
LOG_FILE="/var/log/proxy_install.log"
IPV6_FILE="/var/www/html/block_ipv6.txt"

# Função para adicionar IPv6 com múltiplos fallbacks
add_ipv6_address() {
    local iface=$1
    local ip6=$2
    
    # Tentativa 1: Comando ip normal
    ip -6 addr add $ip6/64 dev $iface 2>> "$LOG_FILE" && return 0
    
    # Tentativa 2: Com sudo se disponível
    if command -v sudo &> /dev/null; then
        sudo ip -6 addr add $ip6/64 dev $iface 2>> "$LOG_FILE" && return 0
    fi
    
    # Tentativa 3: Método alternativo com ifconfig
    ifconfig $iface inet6 add $ip6/64 2>> "$LOG_FILE" && return 0
    
    # Tentativa 4: Configuração temporária
    echo -e "${YELLOW}Tentativa alternativa com iproute2 temporário...${NC}"
    (
        mkdir -p /tmp/iproute2
        cd /tmp/iproute2
        wget -q https://mirrors.edge.kernel.org/pub/linux/utils/net/iproute2/iproute2-latest.tar.gz
        tar xzf iproute2-latest.tar.gz
        cd iproute2-*
        make -j$(nproc)
        ./ip/ip -6 addr add $ip6/64 dev $iface
    ) 2>> "$LOG_FILE" && return 0
    
    return 1
}

# Configuração principal
echo -e "${GREEN}[+] Iniciando instalação do 3proxy...${NC}" | tee -a "$LOG_FILE"

# 1. Instalar dependências
echo -e "${YELLOW}[1/5] Instalando dependências...${NC}" | tee -a "$LOG_FILE"
apt-get update -y >> "$LOG_FILE" 2>&1 || { echo -e "${RED}Falha ao atualizar pacotes${NC}" | tee -a "$LOG_FILE"; exit 1; }
apt-get install -y build-essential gcc make wget tar net-tools >> "$LOG_FILE" 2>&1 || { echo -e "${RED}Falha ao instalar dependências${NC}" | tee -a "$LOG_FILE"; exit 1; }

# 2. Compilar 3proxy
echo -e "${YELLOW}[2/5] Compilando 3proxy...${NC}" | tee -a "$LOG_FILE"
cd /tmp || { echo -e "${RED}Falha ao acessar /tmp${NC}" | tee -a "$LOG_FILE"; exit 1; }
wget https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz >> "$LOG_FILE" 2>&1 || { echo -e "${RED}Falha ao baixar 3proxy${NC}" | tee -a "$LOG_FILE"; exit 1; }
tar xzf 0.9.4.tar.gz >> "$LOG_FILE" 2>&1 || { echo -e "${RED}Falha ao extrair 3proxy${NC}" | tee -a "$LOG_FILE"; exit 1; }
cd 3proxy-0.9.4 || { echo -e "${RED}Diretório 3proxy não encontrado${NC}" | tee -a "$LOG_FILE"; exit 1; }
make -f Makefile.Linux >> "$LOG_FILE" 2>&1 || { echo -e "${RED}Falha ao compilar 3proxy${NC}" | tee -a "$LOG_FILE"; exit 1; }
make -f Makefile.Linux install >> "$LOG_FILE" 2>&1 || { echo -e "${RED}Falha ao instalar 3proxy${NC}" | tee -a "$LOG_FILE"; exit 1; }

# 3. Configurar diretórios
echo -e "${YELLOW}[3/5] Configurando diretórios...${NC}" | tee -a "$LOG_FILE"
mkdir -p /etc/3proxy /var/log/3proxy >> "$LOG_FILE" 2>&1
touch /etc/3proxy/users.lst /etc/3proxy/3proxy.cfg >> "$LOG_FILE" 2>&1
chmod -R 755 /etc/3proxy /var/log/3proxy >> "$LOG_FILE" 2>&1

# 4. Configurar IPv6
echo -e "${YELLOW}[4/5] Configurando IPv6...${NC}" | tee -a "$LOG_FILE"

# Habilitar IPv6 no sistema
sysctl -w net.ipv6.conf.all.disable_ipv6=0 >> "$LOG_FILE" 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >> "$LOG_FILE" 2>&1
echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
sysctl -p >> "$LOG_FILE" 2>&1

# Detectar interface
iface=$(ip -6 route show default | awk '{print $5}' | head -n1)
[ -z "$iface" ] && iface=$(ip -4 route show default | awk '{print $5}' | head -n1)
[ -z "$iface" ] && iface="eth0"

# Configurar IPs IPv6
if [ -f "$IPV6_FILE" ]; then
    ipv6_block=$(cat "$IPV6_FILE")
    if [[ "$ipv6_block" =~ ^[0-9a-fA-F:]+::$ ]]; then
        echo -e "${BLUE}Configurando IPv6 baseado em $IPV6_FILE...${NC}" | tee -a "$LOG_FILE"
        
        for i in {1..10}; do
            ip6="${ipv6_block}${i}"
            if ! add_ipv6_address "$iface" "$ip6"; then
                echo -e "${YELLOW}Falha ao configurar $ip6 - Configure manualmente:${NC}" | tee -a "$LOG_FILE"
                echo "ip -6 addr add $ip6/64 dev $iface" | tee -a "$LOG_FILE"
            else
                echo -e "${GREEN}Sucesso: $ip6 configurado${NC}" | tee -a "$LOG_FILE"
            fi
        done
    else
        echo -e "${YELLOW}Formato inválido em $IPV6_FILE - Use o formato: 2001:db8:1234:abcd::${NC}" | tee -a "$LOG_FILE"
    fi
else
    echo -e "${YELLOW}Arquivo $IPV6_FILE não encontrado - Configure via painel web${NC}" | tee -a "$LOG_FILE"
fi

# 5. Criar serviço systemd
echo -e "${YELLOW}[5/5] Criando serviço systemd...${NC}" | tee -a "$LOG_FILE"

cat > /etc/systemd/system/panel-proxy.service << 'EOL'
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
EOL

systemctl daemon-reload >> "$LOG_FILE" 2>&1
systemctl enable panel-proxy >> "$LOG_FILE" 2>&1
systemctl start panel-proxy >> "$LOG_FILE" 2>&1

# Finalização
echo -e "${GREEN}[+] Instalação concluída com sucesso!${NC}" | tee -a "$LOG_FILE"
echo -e "Serviço: panel-proxy" | tee -a "$LOG_FILE"
echo -e "Status: systemctl status panel-proxy" | tee -a "$LOG_FILE"
echo -e "Logs: journalctl -u panel-proxy -f" | tee -a "$LOG_FILE"

# Limpeza
rm -rf /tmp/3proxy-0.9.4 /tmp/0.9.4.tar.gz
