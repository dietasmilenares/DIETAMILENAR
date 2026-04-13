#!/bin/bash
# =============================================================================
#  SaaS DIETA MILENAR — INSTALADOR OFICIAL v1.2.6 (PROD HARDENED - FIX)
#  Suporte: Ubuntu 20.04+ / Debian 11+ | Modo: Idempotente
# =============================================================================

set -euo pipefail
IFS=$'\n\t'
umask 022

# --- CONFIGURAÇÃO DE LOGS ---
LOG_FILE="/var/log/dieta-milenar-install.log"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "--- Início da Instalação: $(date) ---" >> "$LOG_FILE"

# --- 1. CORES E ESTILOS ---
GOLD='\033[38;5;220m'; BGDARK='\033[48;5;232m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'

# --- 2. CONFIGURAÇÃO DE LARGURA RESPONSIVA ---
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
[[ $TERM_WIDTH -lt 20 ]] && TERM_WIDTH=40

# --- 3. FUNÇÕES DE LAYOUT ---
draw_line() {
    local char=$1; local color=$2; local bg=${3:-}
    echo -ne "${bg}${color}${BOLD}  "
    for ((i=1; i<=$((TERM_WIDTH - 4)); i++)); do echo -n "$char"; done
    echo -e "${NC}"
}

center_print() {
    local text="$1"; local color="$2"
    local pad=$(( (TERM_WIDTH - ${#text}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf "%*s%b%s%b\n" "$pad" "" "$color" "$text" "$NC"
}

header() {
    echo ""
    draw_line "━" "$CYAN"
    echo -e "  ${BOLD}${CYAN}$1${NC}"
    draw_line "━" "$CYAN"
}

log_status() { echo -e "  ${GREEN}[✔]${NC} $1"; }
log_warn()   { echo -e "  ${YELLOW}[⚠]${NC} $1"; }
log_error()  { echo -e "  ${RED}[✘]${NC} $1"; exit 1; }

# --- 4. HELPERS DE PRODUÇÃO ---
on_err() { log_error "Falha na linha $1 (cmd: $2)"; }
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1 || log_error "Comando ausente: $1"; }

is_valid_db_ident() { [[ "$1" =~ ^[A-Za-z0-9_]{1,32}$ ]]; }
is_valid_domain()   { [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }
is_valid_ipv4()     { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

sql_escape_literal() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\'\'}"
  printf "%s" "$s"
}

curl_ip() {
  curl -4 -fsS --max-time 3 --retry 2 "$1" 2>/dev/null | grep -oE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || true
}

# --- 5. VERIFICAÇÕES DE AMBIENTE ---
[[ ${EUID:-999} -eq 0 ]] || log_error "Execute como root: sudo bash install.sh"

install -d -m 0755 /run/lock
exec 9>/run/lock/dieta-milenar-install.lock
flock -n 9 || log_error "Instalador já está rodando (lock /run/lock/dieta-milenar-install.lock)"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_SRC="$REPO_DIR/DietaMilelar"
SOCIALPROOF_SRC="$REPO_DIR/SocialProof"
INSTALL_DIR="/var/www/dieta-milenar"
SOCIALPROOF_DIR="/var/www/socialproof"

# Fallback se a pasta tiver nome diferente no repositório
if [[ ! -d "$PROJECT_SRC" ]]; then
    PROJECT_SRC=$(find "$REPO_DIR" -maxdepth 1 -type d -name "Dieta*" | head -n 1)
fi

[[ -d "$PROJECT_SRC" ]] || log_error "Pasta do projeto não encontrada em $REPO_DIR"

APP_PORT=3000
APP_USER="dieta"
APP_GROUP="dieta"
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
#  TELA 1: CHECKLIST INICIAL
# =============================================================================
clear
echo -e "${BGDARK}${GOLD}${BOLD}"
draw_line "═" "$GOLD" "$BGDARK"
center_print "DIETA MILENAR — INSTALAÇÃO v1.2.6" "${BGDARK}${GOLD}"
draw_line "═" "$GOLD" "$BGDARK"
echo -e "${NC}"

require_cmd curl
require_cmd openssl

echo -e "  ${DIM}Detectando IP público...${NC}"
PUBLIC_IP=""

IP_SERVICES=(
  "https://api.ipify.org"
  "https://ipecho.net/plain"
  "https://checkip.amazonaws.com"
)

for svc in "${IP_SERVICES[@]}"; do
  PUBLIC_IP="$(curl_ip "$svc")"
  if is_valid_ipv4 "$PUBLIC_IP"; then
    break
  fi
  PUBLIC_IP=""
done

if [[ -z "$PUBLIC_IP" ]]; then
  log_warn "Falha ao detectar IP público via web. Usando IP local (fallback)."
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  is_valid_ipv4 "$PUBLIC_IP" || log_error "Não foi possível resolver nenhum IP IPv4 válido."
fi

echo -e "  ${GREEN}[✔]${NC} IP: ${CYAN}${BOLD}${PUBLIC_IP}${NC}\n"

# =============================================================================
#  TELA 2: ETAPA 0 — INPUTS
# =============================================================================
header "ETAPA 0 — CONFIGURAÇÃO DO SISTEMA"

read -rp "  Deseja usar um domínio? [s/N]: " USE_DOMAIN
USE_DOMAIN=${USE_DOMAIN:-n}
DOMAIN="$PUBLIC_IP"
USE_SSL=false

if [[ "$USE_DOMAIN" =~ ^[sS]$ ]]; then
    read -rp "  Digite o domínio (ex: meusite.com): " DOMAIN_RAW
    DOMAIN_RAW="$(echo "$DOMAIN_RAW" | tr -d '[:space:]' | sed -E 's#^https?://##; s#/.*$##')"
    DOMAIN="$DOMAIN_RAW"
    USE_SSL=true
    read -rp "  E-mail para SSL: " LE_EMAIL
fi

read -rp "  Nome do banco [dieta_milenar]: " DB_NAME; DB_NAME=${DB_NAME:-dieta_milenar}
read -rp "  Usuário MySQL [dieta_user]: " DB_USER; DB_USER=${DB_USER:-dieta_user}
read -rsp "  Senha MySQL [root]: " DB_PASS; echo; DB_PASS=${DB_PASS:-root}
read -rp "  Stripe Key [Enter = pular]: " STRIPE_KEY; STRIPE_KEY=${STRIPE_KEY:-sk_test_PLACEHOLDER}
read -rp "  JWT Secret [Enter = gerar]: " JWT_SECRET; JWT_SECRET=${JWT_SECRET:-$(openssl rand -hex 32)}
read -rp "  Instalar phpMyAdmin? [S/n]: " INSTALL_PMA; INSTALL_PMA=${INSTALL_PMA:-s}

# =============================================================================
#  TELA 4: EXECUÇÃO
# =============================================================================
clear

header "ETAPA 0.5 — CONFIGURANDO SWAP (2GB)"
SWAP_FILE="/swapfile"
if [[ ! -f "$SWAP_FILE" ]]; then
    fallocate -l 2G "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1M count=2048 status=none
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
    swapon "$SWAP_FILE"
    grep -q "$SWAP_FILE" /etc/fstab || echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

header "ETAPA 1 — DEPENDÊNCIAS"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates gnupg curl git unzip rsync \
  nginx mariadb-server openssl build-essential \
  php php-fpm php-mysql php-mbstring php-zip php-gd php-curl >/dev/null

# Node.js 20
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update -qq && apt-get install -y -qq nodejs >/dev/null

if ! id -u "$APP_USER" >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/"$APP_USER" --create-home --shell /bin/bash --user-group "$APP_USER"
fi
npm install -g pm2 --silent
PM2_BIN=$(command -v pm2)

header "ETAPA 2 — CONFIGURANDO MYSQL"
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
DB_PASS_ESC="$(sql_escape_literal "$DB_PASS")"
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`socialproof\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS_ESC}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`socialproof\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

header "ETAPA 4 — MOVENDO ARQUIVOS"
install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$INSTALL_DIR"
rsync -a --delete --exclude='node_modules' --exclude='.git' "$PROJECT_SRC/" "$INSTALL_DIR/"
chown -R "$APP_USER":"$APP_GROUP" "$INSTALL_DIR"

header "ETAPA 5 — GERANDO .ENV"
cat > "$INSTALL_DIR/.env" <<ENV
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
JWT_SECRET=${JWT_SECRET}
STRIPE_SECRET_KEY=${STRIPE_KEY}
PORT=${APP_PORT}
NODE_ENV=production
ENV

header "ETAPA 6 — BUILD"
cd "$INSTALL_DIR"
# Instala dependências
runuser -l "$APP_USER" -c "cd $INSTALL_DIR && npm install --silent"
# Roda o build (Vite)
runuser -l "$APP_USER" -c "cd $INSTALL_DIR && npm run build --silent"

# LOGICA DE CORREÇÃO DO SERVER: Se existir server.ts mas não existir o build do server em dist
if [[ -f "server.ts" && ! -f "dist/server.js" ]]; then
    log_status "Compilando servidor TypeScript..."
    runuser -l "$APP_USER" -c "cd $INSTALL_DIR && npx esbuild server.ts --bundle --platform=node --format=cjs --outfile=dist/server.js --external:fsevents" || true
fi

header "ETAPA 7 — IMPORTANDO SQL"
SQL_FILE="$(find "$INSTALL_DIR" -maxdepth 2 -type f -name "*.sql" | head -n 1)"
if [[ -n "$SQL_FILE" ]]; then
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_FILE" || true
fi

header "ETAPA 9 — CONFIGURANDO PM2"
# DETECÇÃO DINÂMICA DO SCRIPT:
if [[ -f "$INSTALL_DIR/dist/server.js" ]]; then
    FINAL_SCRIPT="dist/server.js"
elif [[ -f "$INSTALL_DIR/server.js" ]]; then
    FINAL_SCRIPT="server.js"
else
    FINAL_SCRIPT="index.js" # Ultima tentativa
fi

cat > "$INSTALL_DIR/ecosystem.config.cjs" <<EOF
module.exports = {
  apps: [{
    name: 'dieta-milenar',
    script: '${FINAL_SCRIPT}',
    cwd: '${INSTALL_DIR}',
    env: { NODE_ENV: 'production' }
  }]
};
EOF

runuser -l "$APP_USER" -c "pm2 delete dieta-milenar --silent || true"
runuser -l "$APP_USER" -c "pm2 start $INSTALL_DIR/ecosystem.config.cjs"
runuser -l "$APP_USER" -c "pm2 save --silent"

header "ETAPA 10 — CONFIGURANDO NGINX"
PHP_FPM_SOCK=$(find /run/php/ -type s -name "php*-fpm.sock" | head -1)
cat > "/etc/nginx/sites-available/dieta-milenar" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

ln -sf "/etc/nginx/sites-available/dieta-milenar" "/etc/nginx/sites-enabled/"
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

log_status "Instalação concluída com sucesso!"
echo -e "\n  Acesse: http://${DOMAIN}"