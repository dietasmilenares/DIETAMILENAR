#!/bin/bash
# =============================================================================
#  SOCIALPROOF ENGINE — INSTALADOR OFICIAL v1.0.0
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
header()     { echo ""; draw_line "━" "$CYAN"; echo -e "  ${BOLD}${CYAN}$1${NC}"; draw_line "━" "$CYAN"; }
log_status() { echo -e "  ${GREEN}[✔]${NC} $1"; }
log_warn()   { echo -e "  ${YELLOW}[⚠]${NC} $1"; }
log_error()  { echo -e "  ${RED}[✘]${NC} $1"; exit 1; }

# --- 3. VERIFICAÇÕES DE AMBIENTE ---
[[ ${EUID:-999} -eq 0 ]] || log_error "Execute como root: sudo bash install-socialproof.sh"

# --- 4. BUSCA PELO SOCIALPROOF.ZIP ---
log_status "Buscando arquivo 'socialproof.zip' no sistema..."
ZIP_FILE=$(find /home/ubuntu -name "socialproof.zip" -print -quit)

if [[ -z "$ZIP_FILE" ]]; then
    log_error "Arquivo 'socialproof.zip' não encontrado em /home/ubuntu"
fi

log_status "Arquivo encontrado em: $ZIP_FILE"
TEMP_EXTRACT_DIR="/tmp/socialproof-extract"
INSTALL_DIR="/var/www/socialproof"

log_status "Extraindo socialproof.zip..."
rm -rf "$TEMP_EXTRACT_DIR"
mkdir -p "$TEMP_EXTRACT_DIR"
unzip -q "$ZIP_FILE" -d "$TEMP_EXTRACT_DIR"

PROJECT_SRC="$TEMP_EXTRACT_DIR"
APP_USER="www-data"
APP_GROUP="www-data"
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
#  TELA 1: BANNER INICIAL
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
DB_NAME="socialproof"
log_status "Banco de dados: ${DB_NAME} (padrão fixo)"
read -rp "  Usuário MySQL [sp_user]: " DB_USER; DB_USER=${DB_USER:-sp_user}
read -rsp "  Senha MySQL (oculta) [root]: " DB_PASS; echo; DB_PASS=${DB_PASS:-root}

# =============================================================================
#  EXECUÇÃO DAS ETAPAS
# =============================================================================
clear
header "ETAPA 1 — DEPENDÊNCIAS"
apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  ca-certificates gnupg curl git unzip rsync nginx \
  mariadb-server openssl \
  php php-mbstring php-zip php-gd php-json php-curl php-mysql php-fpm >/dev/null

# Detecta versão do PHP e socket fpm
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.3")
PHP_FPM_SOCK="/var/run/php/php${PHP_VERSION}-fpm.sock"
systemctl enable "php${PHP_VERSION}-fpm" --quiet 2>/dev/null || true
systemctl start  "php${PHP_VERSION}-fpm"          2>/dev/null || true
log_status "PHP ${PHP_VERSION} configurado — socket: $PHP_FPM_SOCK"

header "ETAPA 2 — CONFIGURANDO MYSQL"
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'  IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
log_status "Banco '${DB_NAME}' e usuário '${DB_USER}' configurados"

header "ETAPA 3 — MOVENDO ARQUIVOS"
mkdir -p "$INSTALL_DIR"
rsync -a --delete --exclude='.git' --exclude='DataBaseFULL' "$PROJECT_SRC/" "$INSTALL_DIR/"
chown -R "$APP_USER":"$APP_GROUP" "$INSTALL_DIR"
log_status "Arquivos copiados para $INSTALL_DIR"

header "ETAPA 4 — GERANDO CONFIG.PHP"
mkdir -p "$INSTALL_DIR/includes"
cat > "$INSTALL_DIR/includes/config.php" <<SPCONF
<?php
// config.php — gerado pelo instalador

define('APP_VERSION', '2.0.0');
define('CLAUDE_MODEL', 'claude-opus-4-5');

date_default_timezone_set('America/Sao_Paulo');

define('DB_HOST', '127.0.0.1');
define('DB_PORT', '3306');
define('DB_NAME', '${DB_NAME}');
define('DB_USER', '${DB_USER}');
define('DB_PASS', '${DB_PASS}');

class DB {
    private static \$instance = null;

    public static function conn(): PDO {
        if (self::\$instance === null) {
            try {
                self::\$instance = new PDO(
                    'mysql:host=' . DB_HOST . ';port=' . DB_PORT . ';dbname=' . DB_NAME . ';charset=utf8mb4',
                    DB_USER, DB_PASS,
                    [
                        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                        PDO::ATTR_EMULATE_PREPARES   => false,
                        PDO::ATTR_TIMEOUT            => 10,
                    ]
                );
                self::\$instance->exec("SET time_zone = '-03:00'");
            } catch (PDOException \$e) {
                http_response_code(500);
                header('Content-Type: application/json; charset=utf-8');
                die(json_encode(['error' => 'Database connection failed', 'details' => \$e->getMessage()], JSON_UNESCAPED_UNICODE));
            }
        }
        return self::\$instance;
    }

    public static function fetch(string \$sql, array \$params = []): ?array {
        \$stmt = self::conn()->prepare(\$sql);
        \$stmt->execute(\$params);
        return \$stmt->fetch() ?: null;
    }

    public static function fetchAll(string \$sql, array \$params = []): array {
        \$stmt = self::conn()->prepare(\$sql);
        \$stmt->execute(\$params);
        return \$stmt->fetchAll();
    }

    public static function insert(string \$sql, array \$params = []): string {
        \$stmt = self::conn()->prepare(\$sql);
        \$stmt->execute(\$params);
        return self::conn()->lastInsertId();
    }

    public static function query(string \$sql, array \$params = []): bool {
        \$stmt = self::conn()->prepare(\$sql);
        return \$stmt->execute(\$params);
    }

    public static function execute(string \$sql, array \$params = []): bool {
        return self::query(\$sql, \$params);
    }
}

function getSetting(string \$key): string {
    try {
        \$row = DB::fetch('SELECT \`value\` FROM settings WHERE \`key\` = ?', [\$key]);
        return \$row ? (string)\$row['value'] : '';
    } catch (Exception \$e) { return ''; }
}

function setSetting(string \$key, string \$value): void {
    DB::query(
        'INSERT INTO settings (\`key\`, \`value\`) VALUES (?,?) ON DUPLICATE KEY UPDATE \`value\`=?, updated_at=NOW()',
        [\$key, \$value, \$value]
    );
}

function jsonResponse(array \$data, int \$code = 200): void {
    http_response_code(\$code);
    header('Content-Type: application/json; charset=utf-8');
    header('Access-Control-Allow-Origin: *');
    echo json_encode(\$data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function generateSlug(string \$text): string {
    \$text = mb_strtolower(\$text, 'UTF-8');
    \$from = ['á','à','ã','â','ä','é','è','ê','ë','í','ì','î','ï','ó','ò','õ','ô','ö','ú','ù','û','ü','ç','ñ'];
    \$to   = ['a','a','a','a','a','e','e','e','e','i','i','i','i','o','o','o','o','o','u','u','u','u','c','n'];
    \$text = str_replace(\$from, \$to, \$text);
    \$text = preg_replace('/[^a-z0-9\s-]/', '', \$text);
    \$text = preg_replace('/[\s-]+/', '-', \$text);
    return trim(\$text, '-');
}

function avatarUrl(string \$seed): string {
    return 'https://api.dicebear.com/7.x/avataaars/svg?seed=' . urlencode(\$seed)
         . '&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf';
}
SPCONF

chmod 640 "$INSTALL_DIR/includes/config.php"
log_status "config.php gerado em $INSTALL_DIR/includes/config.php"

header "ETAPA 5 — IMPORTANDO BANCO"
SP_SQL=$(find "$INSTALL_DIR" -maxdepth 4 -iname "dbsp_atual.sql" | head -1)
if [[ -z "$SP_SQL" ]]; then
  SP_SQL=$(find "$INSTALL_DIR" -maxdepth 4 -iname "*.sql" | head -1)
fi
if [[ -n "$SP_SQL" ]]; then
  mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SP_SQL" 2>/dev/null \
    && log_status "Schema importado: $(basename "$SP_SQL")" \
    || log_warn "Schema já importado ou erro parcial"
else
  log_warn "Nenhum .sql encontrado — importe manualmente:"
  echo -e "      mysql -u ${DB_USER} -p ${DB_NAME} < /caminho/dbsp_atual.sql"
fi

header "ETAPA 6 — PERMISSÕES"
chown -R "$APP_USER":"$APP_GROUP" "$INSTALL_DIR"
find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
chmod 640 "$INSTALL_DIR/includes/config.php"
log_status "Permissões configuradas"

header "ETAPA 7 — CONFIGURANDO NGINX"
cat > "/etc/nginx/sites-available/socialproof" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size 110M;

    access_log /var/log/nginx/socialproof.access.log;
    error_log  /var/log/nginx/socialproof.error.log;

    root ${INSTALL_DIR};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass unix:${PHP_FPM_SOCK};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location ~ /\.(ht|git) { deny all; }
    location ~ /includes/  { deny all; }
}
NGINX

ln -sf "/etc/nginx/sites-available/socialproof" "/etc/nginx/sites-enabled/"
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx
log_status "Nginx configurado na porta 80"

# =============================================================================
#  RESUMO FINAL
# =============================================================================
clear
echo -e "${BGDARK}${GOLD}${BOLD}"
draw_line "═" "$GOLD" "$BGDARK"
center_print "SOCIALPROOF — INSTALADO COM SUCESSO" "${BGDARK}${GOLD}"
draw_line "═" "$GOLD" "$BGDARK"
echo -e "${NC}"
echo -e "  ${BOLD}URL:${NC}          http://${DOMAIN}"
echo -e "  ${BOLD}Widget:${NC}       http://${DOMAIN}/widget/index.php"
echo -e "  ${BOLD}Diretório:${NC}    $INSTALL_DIR"
echo -e "  ${BOLD}Config:${NC}       $INSTALL_DIR/includes/config.php"
echo -e "  ${BOLD}Banco:${NC}        $DB_NAME"
echo -e "  ${BOLD}Usuário DB:${NC}   $DB_USER"
echo -e "  ${BOLD}Log install:${NC}  $LOG_FILE"
echo ""
echo -e "  ${BOLD}Comandos úteis:${NC}"
echo -e "  ${CYAN}systemctl status nginx${NC}                        → Status Nginx"
echo -e "  ${CYAN}systemctl status php${PHP_VERSION}-fpm${NC}                → Status PHP"
echo -e "  ${CYAN}systemctl reload nginx${NC}                        → Recarregar Nginx"
echo -e "  ${CYAN}tail -f /var/log/nginx/socialproof.error.log${NC}  → Logs de erro"
echo -e "  ${CYAN}mysql -u ${DB_USER} -p ${DB_NAME}${NC}             → Acessar banco"
echo ""
log_status "Instalação concluída em $(date)"
