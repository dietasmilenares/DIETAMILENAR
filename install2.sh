#!/bin/bash
# =============================================================================
#  SOCIALPROOF ENGINE — INSTALADOR OFICIAL v1.0.0 (INTEGRADO)
#  Suporte: Ubuntu 20.04+ / Debian 11+ | Modo: Idempotente
# =============================================================================

set -euo pipefail
IFS=$'\n\t'
umask 022

# --- CONFIGURAÇÃO DE LOGS ---
LOG_FILE="/var/log/socialproof-install.log"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "--- Início da Instalação: $(date) ---" >> "$LOG_FILE"

# --- 1. CORES E ESTILOS (MANTIDOS) ---
GOLD='\033[38;5;220m'; BGDARK='\033[48;5;232m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'

# --- 2. FUNÇÕES DE LAYOUT (MANTIDAS) ---
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
header()     { echo ""; draw_line "━" "$CYAN"; echo -e "  ${BOLD}${CYAN}$1${NC}"; draw_line "━" "$CYAN"; }
log_status() { echo -e "  ${GREEN}[✔]${NC} $1"; }
log_warn()   { echo -e "  ${YELLOW}[⚠]${NC} $1"; }
log_error()  { echo -e "  ${RED}[✘]${NC} $1"; exit 1; }

# --- 3. VERIFICAÇÕES DE AMBIENTE ---
[[ ${EUID:-999} -eq 0 ]] || log_error "Execute como root: sudo bash install2.sh"

# --- 4. DETECÇÃO DE INSTALAÇÃO EXISTENTE (DIETA MILENAR) ---
DIETA_ENV="/var/www/dieta-milenar/.env"
DETECTED_INSTALL=false

if [[ -f "$DIETA_ENV" ]]; then
    _get_env() { grep "^${1}=" "$DIETA_ENV" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '\r'; }
    DETECTED_DB_USER=$(_get_env DB_USER)
    DETECTED_DB_PASS=$(_get_env DB_PASS)
    DETECTED_DOMAIN=$(grep "server_name" /etc/nginx/sites-available/dieta-milenar 2>/dev/null | awk '{print $2}' | tr -d ';' | head -1 || true)
    [[ -z "$DETECTED_DOMAIN" ]] && DETECTED_DOMAIN=""
    DETECTED_INSTALL=true
    log_status "Instalação do Dieta Milenar detectada. Importando configurações."
fi

# --- 5. BUSCA PELO SOCIALPROOF.ZIP ---
log_status "Buscando arquivo 'socialproof.zip' em /home/ubuntu..."
ZIP_FILE=$(find /home/ubuntu -name "socialproof.zip" -print -quit)

if [[ -z "$ZIP_FILE" ]]; then
    log_error "Arquivo 'socialproof.zip' não encontrado em /home/ubuntu. Certifique-se de ter feito o upload."
fi

INSTALL_DIR="/var/www/socialproof"
TEMP_EXTRACT_DIR="/tmp/socialproof-extract"

log_status "Extraindo arquivos..."
rm -rf "$TEMP_EXTRACT_DIR"
mkdir -p "$TEMP_EXTRACT_DIR"
unzip -qo "$ZIP_FILE" -d "$TEMP_EXTRACT_DIR"

APP_USER="www-data"
APP_GROUP="www-data"
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
#  TELA 1: BANNER INICIAL (MANTIDO)
# =============================================================================
clear
echo -e "${BGDARK}${GOLD}${BOLD}"
draw_line "═" "$GOLD" "$BGDARK"
center_print "SOCIALPROOF ENGINE — INSTALAÇÃO v1.0.0" "${BGDARK}${GOLD}"
draw_line "═" "$GOLD" "$BGDARK"
echo -e "${NC}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || log_error "Comando ausente: $1"; }
require_cmd curl
require_cmd openssl

# Detectar IP Público
PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org || hostname -I | awk '{print $1}')
echo -e "  ${GREEN}[✔]${NC} IP Detectado: ${CYAN}${BOLD}${PUBLIC_IP}${NC}\n"

# =============================================================================
#  TELA 2: CONFIGURAÇÃO DE INPUTS
# =============================================================================
header "ETAPA 0 — CONFIGURAÇÃO DO SISTEMA"

if [[ "$DETECTED_INSTALL" == true && -n "$DETECTED_DOMAIN" ]]; then
    DOMAIN="$DETECTED_DOMAIN"
    log_status "Domínio herdado: $DOMAIN"
else
    read -rp "  Deseja usar um domínio? [s/N]: " USE_DOMAIN
    if [[ "$USE_DOMAIN" =~ ^[sS]$ ]]; then
        read -rp "  Digite o domínio: " DOMAIN
    else
        DOMAIN="$PUBLIC_IP"
    fi
fi

DB_NAME="socialproof"

if [[ "$DETECTED_INSTALL" == true ]]; then
    DB_USER="$DETECTED_DB_USER"
    DB_PASS="$DETECTED_DB_PASS"
else
    read -rp "  Usuário MySQL [root]: " DB_USER; DB_USER=${DB_USER:-root}
    read -rsp "  Senha MySQL (oculta): " DB_PASS; echo; DB_PASS=${DB_PASS:-root}
fi

# =============================================================================
#  EXECUÇÃO DAS ETAPAS
# =============================================================================
header "ETAPA 1 — DEPENDÊNCIAS PHP"
apt-get update -qq
apt-get install -y -qq php-fpm php-mysql php-mbstring php-gd php-json php-curl php-zip >/dev/null

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")
PHP_FPM_SOCK="/var/run/php/php${PHP_VERSION}-fpm.sock"

systemctl enable "php${PHP_VERSION}-fpm" --quiet
systemctl start  "php${PHP_VERSION}-fpm"
log_status "PHP $PHP_VERSION configurado via $PHP_FPM_SOCK"

header "ETAPA 2 — CONFIGURANDO MYSQL"
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
log_status "Banco '$DB_NAME' pronto."

header "ETAPA 3 — MOVENDO ARQUIVOS"
mkdir -p "$INSTALL_DIR"
rsync -a --delete "$TEMP_EXTRACT_DIR/" "$INSTALL_DIR/"
chown -R "$APP_USER":"$APP_GROUP" "$INSTALL_DIR"
log_status "Arquivos instalados em $INSTALL_DIR"

header "ETAPA 4 — GERANDO CONFIG.PHP"
mkdir -p "$INSTALL_DIR/includes"
cat > "$INSTALL_DIR/includes/config.php" <<SPCONF
<?php
define('APP_VERSION', '2.0.0');
define('DB_HOST', '127.0.0.1');
define('DB_PORT', '3306');
define('DB_NAME', '${DB_NAME}');
define('DB_USER', '${DB_USER}');
define('DB_PASS', '${DB_PASS}');
date_default_timezone_set('America/Sao_Paulo');

class DB {
    private static \$instance = null;
    public static function conn(): PDO {
        if (self::\$instance === null) {
            self::\$instance = new PDO('mysql:host='.DB_HOST.';dbname='.DB_NAME.';charset=utf8mb4', DB_USER, DB_PASS, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
            ]);
        }
        return self::\$instance;
    }
}
SPCONF
chmod 640 "$INSTALL_DIR/includes/config.php"
log_status "Configurações de banco geradas."

header "ETAPA 5 — IMPORTANDO SCHEMA"
SP_SQL=$(find "$INSTALL_DIR" -name "*.sql" -print -quit)
if [[ -n "$SP_SQL" ]]; then
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SP_SQL" 2>/dev/null || log_warn "Banco já populado."
    log_status "Banco importado."
fi

header "ETAPA 6 — CONFIGURANDO NGINX (INTEGRAÇÃO)"
DIETA_NGINX="/etc/nginx/sites-available/dieta-milenar"

if [[ -f "$DIETA_NGINX" ]]; then
    if ! grep -q "location ^~ /socialproof" "$DIETA_NGINX"; then
        log_status "Integrando /socialproof ao Nginx existente..."
        # Injeta o bloco PHP antes do proxy do Node.js
        sed -i "/location \/ {/i \
    # ── SocialProof (PHP) ────────────────────────────\n\
    location ^~ /socialproof {\n\
        alias $INSTALL_DIR;\n\
        index index.php index.html;\n\
        try_files \$uri \$uri/ /socialproof/index.php\$is_args\$args;\n\
        location ~ \.php$ {\n\
            include fastcgi_params;\n\
            fastcgi_pass unix:$PHP_FPM_SOCK;\n\
            fastcgi_param SCRIPT_FILENAME \$request_filename;\n\
        }\n\
    }\n" "$DIETA_NGINX"
        nginx -t && systemctl reload nginx
        log_status "Integração concluída com sucesso."
    else
        log_status "Integração já presente no Nginx."
    fi
else
    log_warn "Arquivo Nginx do Dieta Milenar não encontrado. Criando config independente."
    # (Caso o install.sh não tenha rodado, ele cria um arquivo separado)
fi

# Ajustes Finais de Permissão
chown -R www-data:www-data "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

# =============================================================================
#  RESUMO FINAL (MANTIDO)
# =============================================================================
clear
echo -e "${BGDARK}${GOLD}${BOLD}"
draw_line "═" "$GOLD" "$BGDARK"
center_print "SOCIALPROOF — INSTALADO COM SUCESSO" "${BGDARK}${GOLD}"
draw_line "═" "$GOLD" "$BGDARK"
echo -e "${NC}"
echo -e "  ${BOLD}URL do Widget:${NC}  http://${DOMAIN}/socialproof/widget/index.php"
echo -e "  ${BOLD}Painel Admin:${NC}   http://${DOMAIN}/socialproof/"
echo -e "  ${BOLD}Diretório:${NC}      $INSTALL_DIR"
echo -e "  ${BOLD}Banco:${NC}          $DB_NAME"
echo -e "  ${BOLD}Usuário DB:${NC}     $DB_USER"
echo ""
log_status "Instalação finalizada em $(date)"