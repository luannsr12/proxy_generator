#!/bin/bash

# INSTALADOR AUTOMÁTICO 3PROXY PARA PAINEL DE PROXIES
# Versão 2.0
# Luan Alves

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variáveis
LOG_FILE="/var/log/3proxy_install.log"

# Função para tratamento de erros
critical() {
  echo -e "${RED}[ERRO] $1${NC}" | tee -a "$LOG_FILE"
  exit 1
}

# Início da instalação
echo -e "${GREEN}[+] Iniciando instalação do 3proxy...${NC}" | tee -a "$LOG_FILE"

# 1. Instalar dependências de compilação
echo -e "${YELLOW}[1/5] Instalando dependências...${NC}" | tee -a "$LOG_FILE"
apt-get update -y >> "$LOG_FILE" 2>&1 || critical "Falha ao atualizar pacotes"
apt-get install -y build-essential gcc make wget tar >> "$LOG_FILE" 2>&1 || critical "Falha ao instalar dependências"

# 2. Baixar e compilar 3proxy
echo -e "${YELLOW}[2/5] Compilando 3proxy...${NC}" | tee -a "$LOG_FILE"
cd /tmp || critical "Não pode acessar /tmp"
wget https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz >> "$LOG_FILE" 2>&1 || critical "Falha ao baixar 3proxy"
tar xzf 0.9.4.tar.gz >> "$LOG_FILE" 2>&1 || critical "Falha ao extrair 3proxy"
cd 3proxy-0.9.4 || critical "Não pode acessar diretório 3proxy"
make -f Makefile.Linux >> "$LOG_FILE" 2>&1 || critical "Falha ao compilar 3proxy"
make -f Makefile.Linux install >> "$LOG_FILE" 2>&1 || critical "Falha ao instalar 3proxy"

# 3. Criar estrutura de diretórios
echo -e "${YELLOW}[3/5] Configurando diretórios...${NC}" | tee -a "$LOG_FILE"
mkdir -p /etc/3proxy /var/log/3proxy /usr/local/etc/3proxy >> "$LOG_FILE" 2>&1
touch /etc/3proxy/users.lst /etc/3proxy/3proxy.cfg >> "$LOG_FILE" 2>&1
chmod -R 777 /etc/3proxy /var/log/3proxy >> "$LOG_FILE" 2>&1

# 4. Configurar IPv6
echo -e "${YELLOW}[4/5] Habilitando IPv6...${NC}" | tee -a "$LOG_FILE"
sysctl -w net.ipv6.conf.all.disable_ipv6=0 >> "$LOG_FILE" 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >> "$LOG_FILE" 2>&1
echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
sysctl -p >> "$LOG_FILE" 2>&1

# 5. Criar arquivo de bloco IPv6 padrão
echo -e "${YELLOW}[5/5] Criando configuração inicial...${NC}" | tee -a "$LOG_FILE"
touch /var/www/html/block_ipv6.txt
chmod 666 /var/www/html/block_ipv6.txt

# Finalização
echo -e "${GREEN}[+] 3proxy instalado com sucesso!${NC}" | tee -a "$LOG_FILE"
echo -e "Configure seu bloco IPv6 em: ${YELLOW}/var/www/html/block_ipv6.txt${NC}" | tee -a "$LOG_FILE"
echo -e "Log completo disponível em: ${YELLOW}$LOG_FILE${NC}" | tee -a "$LOG_FILE"

# Limpeza
rm -rf /tmp/3proxy-0.9.4 /tmp/0.9.4.tar.gz >> "$LOG_FILE" 2>&1
