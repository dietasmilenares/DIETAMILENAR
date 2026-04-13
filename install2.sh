#!/bin/bash
# =============================================================================
#  SOCIALPROOF ENGINE — INSTALADOR OFICIAL v1.1.0
#  INTEGRAÇÃO SEGURA: /var/www/html/socialproof (PORTA 80)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'
umask 022

# --- CONFIGURAÇÃO DE LOGS ---
LOG_FILE="/var/log/socialproof-install.log"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- 1. CORES E ESTILOS ---
GOLD='\033[38;5;220m'; BGDARK='\033[48;5;232m'; BOLD='\033[1m'; NC='\033[0m'
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'

# --- 2. FUNÇÕES DE LAYOUT ---
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
draw_line() {
    local char=$1; local color=$2
    echo -ne "${color}${BOLD}  "
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

# --- 3. VERIFICAÇÕES INICIAIS ---
[[ ${EUID:-999} -eq 0 ]] || log_error "Execute como root: sudo bash install2.sh"

# --- 4. DETECÇÃO DE INSTALAÇÃO EXISTENTE (HERANÇA DO INSTALL.SH) ---
DIETA_ENV="/var/www/dieta-milenar/.env"
DIETA_NGINX="/etc/nginx/sites-available/dieta-milenar"
DETECTED_INSTALL=false

if [[ -f "$DIETA_ENV" ]]; then
    _get_env() { grep "^${1}=" "$DIETA_ENV" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '\r'; }
    DB_USER=$(_get_env DB_USER)
    DB_PASS=$(_get_env DB_PASS)
    DOMAIN=$(grep "server_name" "$DIETA_NGINX" 2>/dev/null | awk '{print $2}' | tr -d ';' | head -1 || echo "localhost")
    DETECTED_INSTALL=true
    log_status "Configurações detectadas do Dieta Milenar (DB: $DB_USER | Domínio: $DOMAIN)"
else
    # Fallback caso o install.sh não tenha sido rodado ainda
    header "CONFIGURAÇÃO MANUAL (INSTALL.SH NÃO DETECTADO)"
    read -rp "  Domínio/IP: " DOMAIN
    read -rp "  Usuário MySQL [dieta_user]: " DB_USER; DB_USER=${DB_USER:-dieta_user}
    read -rsp "  Senha MySQL: " DB_PASS; echo; DB_PASS=${DB_PASS:-root}
fi

# --- 5. BUSCA E PREPARAÇÃO DOS ARQUIVOS ---
log_status "Buscando 'socialproof.zip'..."
ZIP_FILE=$(find /home/ubuntu -name "socialproof.zip" -print -quit)
[[ -z "$ZIP_FILE" ]] && log_error "'socialproof.zip' não encontrado em /home/ubuntu"

INSTALL_DIR="/var/www/html/socialproof"
TEMP_EXTRACT_DIR="/tmp/socialproof-extract"

rm -rf "$TEMP_EXTRACT_DIR" "$INSTALL_DIR"
mkdir -p "$TEMP_EXTRACT_DIR" "$INSTALL_DIR"
unzip -qo "$ZIP_FILE" -d "$TEMP_EXTRACT_DIR"

# =============================================================================
#  EXECUÇÃO
# =============================================================================
clear
center_print "SOCIALPROOF — INTEGRAÇÃO PORTA 80" "$GOLD"

header "ETAPA 1 — DEPENDÊNCIAS (PHP)"
# O install.sh instala Nginx e MariaDB. O install2.sh instala o PHP necessário para o Social Proof.
apt-get update -qq
apt-get install -y -qq php-fpm php-mysql php-mbstring php-gd php-json php-curl php-zip unzip >/dev/null

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")
PHP_FPM_SOCK=$(find /run/php/ -name "php${PHP_VERSION}-fpm.sock" | head -1 || echo "/var/run/php/php${PHP_VERSION}-fpm.sock")

systemctl enable "php${PHP_VERSION}-fpm" --quiet
systemctl start  "php${PHP_VERSION}-fpm"
log_status "PHP-FPM $PHP_VERSION ativo."

header "ETAPA 2 — BANCO DE DADOS"
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`socialproof\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`socialproof\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
log_status "Banco 'socialproof' configurado."

header "ETAPA 3 — INSTALAÇÃO DOS ARQUIVOS"
rsync -a "$TEMP_EXTRACT_DIR/" "$INSTALL_DIR/"
chown -R www-data:www-data "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"
log_status "Arquivos movidos para $INSTALL_DIR"

header "ETAPA 4 — CONFIGURAÇÃO DO ENGINE"
mkdir -p "$INSTALL_DIR/includes"
cat > "$INSTALL_DIR/includes/config.php" <<SPCONF
<?php
define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'socialproof');
define('DB_USER', '${DB_USER}');
define('DB_PASS', '${DB_PASS}');
SPCONF
chown www-data:www-data "$INSTALL_DIR/includes/config.php"
chmod 640 "$INSTALL_DIR/includes/config.php"

# --- IMPORTAÇÃO DO BANCO DE DADOS (ATUALIZADO) ---
SPECIFIC_SQL="$INSTALL_DIR/DataBaseFULL/Dieta-Faraonica-Data-Base-Completa_2.sql"

if [[ -f "$SPECIFIC_SQL" ]]; then
    log_status "Importando banco de dados: Dieta-Faraonica-Data-Base-Completa_2.sql"
    mysql -u "$DB_USER" -p"$DB_PASS" "socialproof" < "$SPECIFIC_SQL" 2>/dev/null || log_warn "Erro na importação do SQL específico."
else
    log_warn "Arquivo específico não encontrado em $SPECIFIC_SQL, tentando busca genérica..."
    SP_SQL=$(find "$INSTALL_DIR" -name "*.sql" -print -quit)
    if [[ -n "$SP_SQL" ]]; then
        mysql -u "$DB_USER" -p"$DB_PASS" "socialproof" < "$SP_SQL" 2>/dev/null || log_warn "Aviso na importação do SQL genérico."
    fi
fi

header "ETAPA 5 — INTEGRAÇÃO NGINX (PORTA 80)"
if [[ -f "$DIETA_NGINX" ]]; then
    # Verifica se a regra já existe para não duplicar
    if ! grep -q "location ^~ /socialproof" "$DIETA_NGINX"; then
        log_status "Injetando regra SocialProof no Nginx da aplicação principal..."
        
        # Cria um arquivo temporário para a nova configuração
        sed -i "/location \/ {/i \
    # ── SocialProof Engine (PHP) ─────────────────────\n\
    location ^~ /socialproof {\n\
        alias $INSTALL_DIR/;\n\
        index index.php index.html;\n\
        try_files \$uri \$uri/ /socialproof/index.php\$is_args\$args;\n\
\n\
        location ~ ^/socialproof/(.+\\.php)$ {\n\
            include fastcgi_params;\n\
            fastcgi_pass unix:$PHP_FPM_SOCK;\n\
            fastcgi_param SCRIPT_FILENAME \$request_filename;\n\
        }\n\
    }\n" "$DIETA_NGINX"

        nginx -t && systemctl reload nginx
        log_status "Integração Nginx concluída com sucesso."
    else
        log_warn "Integração já detectada no Nginx. Ignorando injeção."
    fi
else
    log_error "Arquivo Nginx do install.sh não encontrado em $DIETA_NGINX"
fi

# =============================================================================
#  RESUMO FINAL
# =============================================================================
clear
draw_line "═" "$GOLD"
center_print "INSTALAÇÃO SOCIALPROOF CONCLUÍDA" "$GOLD"
draw_line "═" "$GOLD"
echo -e "  ${BOLD}Status:${NC}        Integrado à Porta 80"
echo -e "  ${BOLD}URL Painel:${NC}    http://${DOMAIN}/socialproof/"
echo -e "  ${BOLD}URL Widget:${NC}    http://${DOMAIN}/socialproof/widget/index.php"
echo -e "  ${BOLD}Diretório:${NC}     $INSTALL_DIR"
echo -e "  ${BOLD}Socket PHP:${NC}    $PHP_FPM_SOCK"
draw_line "━" "$CYAN"