#!/bin/bash
# =============================================================================
#  SaaS DIETA MILENAR — INSTALADOR OFICIAL v1.2.5 (PROD HARDENED - ZIP SEARCH)
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

# --- 2. FUNÇÕES DE LAYOUT ---
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
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
header() { echo ""; draw_line "━" "$CYAN"; echo -e "  ${BOLD}${CYAN}$1${NC}"; draw_line "━" "$CYAN"; }
log_status() { echo -e "  ${GREEN}[✔]${NC} $1"; }
log_warn()   { echo -e "  ${YELLOW}[⚠]${NC} $1"; }
log_error()  { echo -e "  ${RED}[✘]${NC} $1"; exit 1; }

# --- 3. VERIFICAÇÕES DE AMBIENTE ---
[[ ${EUID:-999} -eq 0 ]] || log_error "Execute como root: sudo bash install.sh"

# --- 4. BUSCA PELO PROJETO.ZIP ---
log_status "Buscando arquivo 'projeto.zip' no sistema..."
ZIP_FILE=$(find /home/ubuntu -name "projeto.zip" -print -quit)

if [[ -z "$ZIP_FILE" ]]; then
    log_error "Arquivo 'projeto.zip' não encontrado em /home/ubuntu"
fi

log_status "Arquivo encontrado em: $ZIP_FILE"
TEMP_EXTRACT_DIR="/tmp/dieta-milenar-extract"
INSTALL_DIR="/var/www/dieta-milenar"

log_status "Extraindo projeto.zip..."
rm -rf "$TEMP_EXTRACT_DIR"
mkdir -p "$TEMP_EXTRACT_DIR"
unzip -q "$ZIP_FILE" -d "$TEMP_EXTRACT_DIR"

PROJECT_SRC="$TEMP_EXTRACT_DIR"
APP_USER="dieta"
APP_GROUP="dieta"
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
#  TELA 1: CHECKLIST INICIAL
# =============================================================================
clear
echo -e "${BGDARK}${GOLD}${BOLD}"
draw_line "═" "$GOLD" "$BGDARK"
center_print "DIETA MILENAR — INSTALAÇÃO v1.2.5" "${BGDARK}${GOLD}"
draw_line "═" "$GOLD" "$BGDARK"
echo -e "${NC}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || log_error "Comando ausente: $1"; }
require_cmd curl
require_cmd openssl

echo -e "  ${DIM}Detectando IP público...${NC}"
PUBLIC_IP=""
IP_SERVICES=("https://api.ipify.org" "https://ipecho.net/plain" "https://checkip.amazonaws.com")
for svc in "${IP_SERVICES[@]}"; do
  PUBLIC_IP="$(curl -4 -fsS --max-time 3 "$svc" 2>/dev/null || true)"
  [[ "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && break
  PUBLIC_IP=""
done
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
echo -e "  ${GREEN}[✔]${NC} IP: ${CYAN}${BOLD}${PUBLIC_IP}${NC}\n"

# =============================================================================
#  TELA 2: ETAPA 0 — INPUTS
# =============================================================================
header "ETAPA 0 — CONFIGURAÇÃO DO SISTEMA"
read -rp "  Deseja usar um domínio? [s/N]: " USE_DOMAIN
USE_DOMAIN=${USE_DOMAIN:-n}
DOMAIN="$PUBLIC_IP"
if [[ "$USE_DOMAIN" =~ ^[sS]$ ]]; then
    read -rp "  Digite o domínio (ex: meusite.com): " DOMAIN
fi
read -rp "  Nome do banco [dieta_milenar]: " DB_NAME; DB_NAME=${DB_NAME:-dieta_milenar}
read -rp "  Usuário MySQL [dieta_user]: " DB_USER; DB_USER=${DB_USER:-dieta_user}
read -rsp "  Senha MySQL (oculta) [root]: " DB_PASS; echo; DB_PASS=${DB_PASS:-root}
read -rp "  Stripe Secret Key [Enter = pular]: " STRIPE_KEY; STRIPE_KEY=${STRIPE_KEY:-sk_test_PLACEHOLDER}
read -rp "  JWT Secret [Enter = gerar]: " JWT_SECRET; JWT_SECRET=${JWT_SECRET:-$(openssl rand -hex 32)}

# =============================================================================
#  TELA 4: EXECUÇÃO DAS ETAPAS REAIS
# =============================================================================
clear
header "ETAPA 1 — DEPENDÊNCIAS"
apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  ca-certificates gnupg curl git unzip rsync nginx mariadb-server openssl build-essential >/dev/null

# Instalar Node.js 20
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update -qq && apt-get install -y -qq nodejs >/dev/null
if ! id -u "$APP_USER" >/dev/null 2>&1; then useradd --system --home-dir /var/lib/"$APP_USER" --create-home --shell /bin/bash --user-group "$APP_USER"; fi
npm install -g pm2 --silent
PM2_BIN=$(command -v pm2)

header "ETAPA 2 — CONFIGURANDO MYSQL"
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

header "ETAPA 4 — MOVENDO ARQUIVOS"
install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$INSTALL_DIR"
rsync -a --delete --exclude='node_modules' --exclude='.git' --exclude='dist' "$PROJECT_SRC/" "$INSTALL_DIR/"
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
PORT=3000
NODE_ENV=production
ENV

header "ETAPA 6 — CONFIGURANDO CHAT WIDGET"
CHATW="$INSTALL_DIR/src/components/ChatWidget.tsx"
if [[ -f "$CHATW" ]]; then
  NEW_URL="http://${DOMAIN}/socialproof/widget/index.php?room=dieta-faraonica"
  # URL antiga a ser substituída
  esc_from='https://socialproof-production\.up\.railway\.app/widget/index\.php\?room=dieta-faraonica'
  esc_to="$(printf '%s' "$NEW_URL" | sed -e 's/[\/&]/\\&/g')"
  sed -i -E "s#${esc_from}#${esc_to}#g" "$CHATW" || true
  log_status "Chat Widget configurado para: $NEW_URL"
fi

header "ETAPA 7 — BUILD"
cd "$INSTALL_DIR"
runuser -l "$APP_USER" -c "cd $INSTALL_DIR && npm install --silent && npm run build --silent"

header "ETAPA 8 — CONFIGURANDO PM2"
cat > "$INSTALL_DIR/ecosystem.config.cjs" <<EOF
module.exports = {
  apps: [{
    name: 'dieta-milenar',
    script: 'dist/server.js',
    interpreter: 'node',
    cwd: '${INSTALL_DIR}',
    env_production: { NODE_ENV: 'production' }
  }]
};
EOF
runuser -l "$APP_USER" -c "pm2 start $INSTALL_DIR/ecosystem.config.cjs --env production"
runuser -l "$APP_USER" -c "pm2 save --silent"

header "ETAPA 9 — CONFIGURANDO NGINX"
cat > "/etc/nginx/sites-available/dieta-milenar" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX
ln -sf "/etc/nginx/sites-available/dieta-milenar" "/etc/nginx/sites-enabled/"
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

log_status "Instalação concluída!"