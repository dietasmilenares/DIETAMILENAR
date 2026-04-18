#!/usr/bin/env bash
# =============================================================================
# DIETA MILENAR — MENU OPERACIONAL UNIFICADO (Ubuntu 22.04+)
# Coerente com:
#   - instalador oficial (install.sh)
#   - menu.sh / menu2.sh
#   - conteúdo do Projeto.zip
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
: "${TERM:=xterm}"

# --- identidade da instalação ---
APP_NAME="Dieta Milenar"
APP_SLUG="dieta-milenar"
APP_USER="dieta"
APP_GROUP="dieta"
APP_HOME="/var/lib/${APP_USER}"
INSTALL_DIR="/var/www/dieta-milenar"
SOCIALPROOF_DIR="/var/www/socialproof"
LOG_FILE="/var/log/dieta-milenar-install.log"
APP_ENV_FILE="${INSTALL_DIR}/.env"
APP_ENV_PROD="${INSTALL_DIR}/.env.production"
APP_ENV_DEV="${INSTALL_DIR}/.env.development"
APP_PM2_NAME="dieta-milenar"
PM2_LOG_DIR="${APP_HOME}/.pm2/logs"
BACKUP_DIR="/root/backups/dieta-milenar"
DEFAULT_PORT="3000"

# --- terminal ---
TERM_WIDTH=$(tput cols 2>/dev/null || echo 100)
(( TERM_WIDTH < 80 )) && TERM_WIDTH=80

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'
C_GOLD='\033[38;5;220m'
C_BG='\033[48;5;235m'

# --- guards ---
[[ ${EUID:-999} -eq 0 ]] || {
  echo -e "${C_RED}Execute como root:${C_RESET} sudo bash $0"
  exit 1
}

# --- helpers base ---
trim() {
  local s="$*"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

repeat_char() {
  local char="$1" count="$2"
  printf '%*s' "$count" '' | tr ' ' "$char"
}

hr() {
  local char="${1:-═}" color="${2:-$C_CYAN}"
  printf '%b%s%b\n' "$color" "$(repeat_char "$char" $((TERM_WIDTH - 2)))" "$C_RESET"
}

center() {
  local text="$1"
  local raw_len=${#text}
  local pad=$(( (TERM_WIDTH - raw_len) / 2 ))
  (( pad < 0 )) && pad=0
  printf '%*s%s\n' "$pad" '' "$text"
}

box_title() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${C_BG}${C_GOLD}${C_BOLD}"
  hr "═" "$C_GOLD"
  center "${APP_NAME} — MENU OPERACIONAL"
  hr "═" "$C_GOLD"
  echo -e "${C_RESET}"
}

section() {
  local title="$1"
  echo
  printf '%b╔%s╗%b\n' "$C_CYAN" "$(repeat_char '═' $((TERM_WIDTH - 4)))" "$C_RESET"
  printf '%b║ %b%-*s%b %b║%b\n' "$C_CYAN" "$C_BOLD$C_WHITE" $((TERM_WIDTH - 6)) "$title" "$C_RESET" "$C_CYAN" "$C_RESET"
  printf '%b╚%s╝%b\n' "$C_CYAN" "$(repeat_char '═' $((TERM_WIDTH - 4)))" "$C_RESET"
}

info()    { echo -e "  ${C_CYAN}[•]${C_RESET} $*"; }
success() { echo -e "  ${C_GREEN}[✔]${C_RESET} $*"; }
warn()    { echo -e "  ${C_YELLOW}[!]${C_RESET} $*"; }
fail()    { echo -e "  ${C_RED}[✘]${C_RESET} $*"; }

pause() {
  echo
  read -r -p $'  ENTER para continuar... ' _
}

ask_option() {
  local prompt="${1:-  Opção: }"
  read -r -p "$prompt" MENU_OPT
  MENU_OPT="$(trim "$MENU_OPT")"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

run_as_app() {
  local cmd="$1"
  runuser -l "$APP_USER" -c "$cmd"
}

# --- detecção coerente com install.sh / Ubuntu 22 ---
resolve_pm2_bin() {
  PM2_BIN="$(command -v pm2 || true)"
  [[ -n "${PM2_BIN:-}" ]] || PM2_BIN="$(find /usr/lib/node_modules/pm2/bin /usr/local/lib/node_modules/pm2/bin -type f -name pm2 2>/dev/null | head -1 || true)"
  [[ -n "${PM2_BIN:-}" ]] || PM2_BIN="pm2"
}

resolve_db_bins() {
  DB_CLIENT_BIN="$(command -v mariadb || command -v mysql || true)"
  DB_DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump || true)"
}

resolve_mariadb_service() {
  if systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx 'mariadb.service'; then
    DB_SERVICE="mariadb"
  elif systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx 'mysql.service'; then
    DB_SERVICE="mysql"
  else
    DB_SERVICE="mariadb"
  fi
}

resolve_php_fpm() {
  PHP_FPM_SERVICE=""
  PHP_FPM_SOCKET=""

  PHP_FPM_SOCKET="$(find /run/php /var/run/php -maxdepth 1 -type s -name 'php*-fpm.sock' 2>/dev/null | sort -V | tail -1 || true)"
  PHP_FPM_SERVICE="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '/^php[0-9.]+-fpm\.service/ {print $1}' | sort -V | tail -1 | sed 's/\.service$//' || true)"

  if [[ -z "$PHP_FPM_SERVICE" && -n "$PHP_FPM_SOCKET" ]]; then
    PHP_FPM_SERVICE="$(basename "$PHP_FPM_SOCKET" .sock)"
  fi
}

resolve_domain() {
  APP_DOMAIN="localhost"
  local nginx_conf="/etc/nginx/sites-available/${APP_SLUG}"
  if [[ -f "$nginx_conf" ]]; then
    APP_DOMAIN="$(awk '/^[[:space:]]*server_name[[:space:]]+/ {for (i=2;i<=NF;i++) {gsub(/;|www\./, "", $i); if ($i !~ /^_|^\$/ && $i != "_" && $i != "localhost") {print $i; exit}}}' "$nginx_conf" 2>/dev/null || true)"
    APP_DOMAIN="$(trim "$APP_DOMAIN")"
    [[ -n "$APP_DOMAIN" ]] || APP_DOMAIN="localhost"
  fi
}

load_app_env() {
  APP_PORT="$DEFAULT_PORT"
  DB_HOST="127.0.0.1"
  DB_PORT="3306"
  DB_NAME="dieta_milenar"
  DB_USER="dieta_user"
  DB_PASS=""
  NODE_ENV_VALUE="production"
  STRIPE_SECRET=""

  if [[ -f "$APP_ENV_FILE" ]]; then
    APP_PORT="$(awk -F= '/^PORT=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
    DB_HOST="$(awk -F= '/^DB_HOST=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
    DB_PORT="$(awk -F= '/^DB_PORT=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
    DB_NAME="$(awk -F= '/^DB_NAME=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
    DB_USER="$(awk -F= '/^DB_USER=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
    DB_PASS="$(awk -F= '/^DB_PASS=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
    NODE_ENV_VALUE="$(awk -F= '/^NODE_ENV=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
    STRIPE_SECRET="$(awk -F= '/^STRIPE_SECRET_KEY=/{print substr($0, index($0,$2))}' "$APP_ENV_FILE" | tail -1)"
  fi

  APP_PORT="$(trim "${APP_PORT:-$DEFAULT_PORT}")"
  DB_HOST="$(trim "${DB_HOST:-127.0.0.1}")"
  DB_PORT="$(trim "${DB_PORT:-3306}")"
  DB_NAME="$(trim "${DB_NAME:-dieta_milenar}")"
  DB_USER="$(trim "${DB_USER:-dieta_user}")"
  DB_PASS="${DB_PASS:-}"
  NODE_ENV_VALUE="$(printf '%s' "${NODE_ENV_VALUE:-production}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$APP_PORT" ]] || APP_PORT="$DEFAULT_PORT"
  [[ "$NODE_ENV_VALUE" == "development" ]] || NODE_ENV_VALUE="production"
}

get_current_mode() {
  load_app_env
  printf '%s' "$NODE_ENV_VALUE"
}

mode_label() {
  local mode="${1:-$(get_current_mode)}"
  [[ "$mode" == "development" ]] && printf 'DEV' || printf 'PROD'
}

pm2_process_exists() {
  run_as_app "$PM2_BIN jlist" 2>/dev/null | grep -q '"name":"'"$APP_PM2_NAME"'"'
}

pm2_process_online() {
  run_as_app "$PM2_BIN jlist" 2>/dev/null | grep -q '"name":"'"$APP_PM2_NAME"'".*"status":"online"'
}

build_server_if_needed() {
  if [[ -f "$INSTALL_DIR/server.ts" && ! -f "$INSTALL_DIR/dist/server.js" ]]; then
    info "Compilando server.ts para dist/server.js..."
    run_as_app "cd '$INSTALL_DIR' && npx esbuild server.ts --bundle --platform=node --format=esm --packages=external --outfile=dist/server.js >/dev/null 2>&1 || npx tsc server.ts --outDir dist >/dev/null 2>&1"
  fi
}

ensure_ecosystem_file() {
  local server_script="dist/server.js"
  if [[ -f "$INSTALL_DIR/dist/server.js" ]]; then
    server_script="dist/server.js"
  elif [[ -f "$INSTALL_DIR/server.js" ]]; then
    server_script="server.js"
  fi

  cat > "$INSTALL_DIR/ecosystem.config.cjs" <<EOCFG
module.exports = {
  apps: [{
    name: '${APP_PM2_NAME}',
    script: '${server_script}',
    interpreter: 'node',
    cwd: '${INSTALL_DIR}',
    exec_mode: 'fork',
    instances: 1,
    env_production: { NODE_ENV: 'production' },
    autorestart: true,
    max_memory_restart: '512M',
    error_file: '/var/log/dieta-milenar/error.log',
    out_file: '/var/log/dieta-milenar/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss'
  }]
};
EOCFG
  chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/ecosystem.config.cjs"
}

replace_or_append_env_var() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i -E "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

restart_pm2_current_mode() {
  local mode
  mode="$(get_current_mode)"

  run_as_app "$PM2_BIN delete $APP_PM2_NAME >/dev/null 2>&1 || true"

  if [[ "$mode" == "development" ]]; then
    info "Iniciando PM2 em modo DEV..."
    run_as_app "cd '$INSTALL_DIR' && NODE_ENV=development '$PM2_BIN' start npm --name '$APP_PM2_NAME' --cwd '$INSTALL_DIR' -- run dev"
  else
    build_server_if_needed
    ensure_ecosystem_file
    info "Iniciando PM2 em modo PROD..."
    run_as_app "'$PM2_BIN' start '$INSTALL_DIR/ecosystem.config.cjs' --env production"
  fi

  run_as_app "'$PM2_BIN' save --silent" >/dev/null 2>&1 || true
}

apply_permissions_fix() {
  section "FIX — REAPLICANDO PERMISSÕES"

  install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$INSTALL_DIR"
  install -d -m 0755 -o "$APP_USER" -g "$APP_GROUP" /var/log/dieta-milenar

  if id -u "$APP_USER" >/dev/null 2>&1; then
    usermod -aG "$APP_GROUP" www-data >/dev/null 2>&1 || true
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"
  fi

  if [[ -d "$INSTALL_DIR/public" ]]; then
    chown -R www-data:www-data "$INSTALL_DIR/public"
    find "$INSTALL_DIR/public" -type d -exec chmod 0775 {} +
    find "$INSTALL_DIR/public" -type f -exec chmod 0664 {} +
    success "Permissões de public/ corrigidas."
  else
    warn "Diretório public/ não encontrado."
  fi

  if [[ -d "$INSTALL_DIR/socialmembers" ]]; then
    chown -R www-data:www-data "$INSTALL_DIR/socialmembers"
    find "$INSTALL_DIR/socialmembers" -type d -exec chmod 0775 {} +
    find "$INSTALL_DIR/socialmembers" -type f -exec chmod 0664 {} +
    success "Permissões de socialmembers/ corrigidas."
  fi

  if [[ -f "$APP_ENV_FILE" ]]; then
    chown "$APP_USER:$APP_GROUP" "$APP_ENV_FILE"
    chmod 0640 "$APP_ENV_FILE"
    success "Permissões do .env corrigidas."
  fi

  if [[ -d /var/log/dieta-milenar ]]; then
    chown -R "$APP_USER:$APP_GROUP" /var/log/dieta-milenar
    find /var/log/dieta-milenar -type d -exec chmod 0755 {} +
    find /var/log/dieta-milenar -type f -exec chmod 0644 {} +
    success "Permissões de logs corrigidas."
  fi

  success "Fix concluído."
  pause
}

service_state_label() {
  local unit="$1"
  if [[ -z "$unit" ]]; then
    printf '%bN/D%b' "$C_YELLOW" "$C_RESET"
    return
  fi
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    printf '%bonline%b' "$C_GREEN" "$C_RESET"
  else
    printf '%boffline%b' "$C_RED" "$C_RESET"
  fi
}

http_probe() {
  local url="$1"
  curl -fsS --max-time 6 "$url" -o /dev/null >/dev/null 2>&1
}

print_runtime_summary() {
  load_app_env
  resolve_domain
  resolve_php_fpm
  resolve_mariadb_service
  resolve_pm2_bin

  echo -e "  ${C_BOLD}Instalação:${C_RESET} ${INSTALL_DIR}"
  echo -e "  ${C_BOLD}Usuário app:${C_RESET} ${APP_USER}"
  echo -e "  ${C_BOLD}Modo:${C_RESET} $(mode_label "$NODE_ENV_VALUE")"
  echo -e "  ${C_BOLD}Porta app:${C_RESET} ${APP_PORT}"
  echo -e "  ${C_BOLD}Domínio:${C_RESET} ${APP_DOMAIN}"
  echo -e "  ${C_BOLD}DB host:${C_RESET} ${DB_HOST}:${DB_PORT}"
}

menu_fix() {
  while true; do
    box_title
    section "FIX"
    echo -e "  ${C_BOLD}[1]${C_RESET} Permissões"
    echo -e "  ${C_BOLD}[0]${C_RESET} Voltar"
    echo
    ask_option
    case "$MENU_OPT" in
      1) apply_permissions_fix ;;
      0) break ;;
      *) warn "Opção inválida."; pause ;;
    esac
  done
}

restart_nginx_safe() {
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || systemctl restart nginx
    success "Nginx recarregado."
  else
    fail "nginx -t falhou. Corrija a configuração antes de reiniciar."
  fi
}

restart_pm2_safe() {
  if [[ ! -d "$INSTALL_DIR" ]]; then
    fail "Instalação não encontrada em $INSTALL_DIR"
    return 1
  fi
  restart_pm2_current_mode
  if pm2_process_online; then
    success "PM2 online para ${APP_PM2_NAME}."
  else
    warn "PM2 executado, mas o processo não ficou online. Verifique os logs."
  fi
}

menu_servicos() {
  while true; do
    box_title
    section "SERVIÇOS"
    echo -e "  ${C_BOLD}[1]${C_RESET} Status geral"
    echo -e "  ${C_BOLD}[2]${C_RESET} Reiniciar tudo"
    echo -e "  ${C_BOLD}[3]${C_RESET} Reiniciar Nginx"
    echo -e "  ${C_BOLD}[4]${C_RESET} Reiniciar PM2 (${APP_NAME})"
    echo -e "  ${C_BOLD}[5]${C_RESET} Reiniciar MariaDB"
    echo -e "  ${C_BOLD}[0]${C_RESET} Voltar"
    echo
    ask_option
    case "$MENU_OPT" in
      1)
        section "STATUS GERAL"
        load_app_env
        resolve_php_fpm
        resolve_mariadb_service
        resolve_pm2_bin
        resolve_domain

        print_runtime_summary
        echo
        echo -e "  ${C_BOLD}Nginx:${C_RESET}     $(service_state_label nginx)"
        echo -e "  ${C_BOLD}MariaDB:${C_RESET}   $(service_state_label "$DB_SERVICE")"
        echo -e "  ${C_BOLD}PHP-FPM:${C_RESET}   $(service_state_label "$PHP_FPM_SERVICE") ${C_DIM}${PHP_FPM_SERVICE:-}${C_RESET}"
        if pm2_process_online; then
          echo -e "  ${C_BOLD}PM2:${C_RESET}       ${C_GREEN}online${C_RESET} (${APP_PM2_NAME})"
        elif pm2_process_exists; then
          echo -e "  ${C_BOLD}PM2:${C_RESET}       ${C_YELLOW}presente, mas não online${C_RESET}"
        else
          echo -e "  ${C_BOLD}PM2:${C_RESET}       ${C_RED}processo ausente${C_RESET}"
        fi

        echo
        if http_probe "http://127.0.0.1:${APP_PORT}"; then
          success "Aplicação responde em http://127.0.0.1:${APP_PORT}"
        else
          fail "Aplicação não respondeu em http://127.0.0.1:${APP_PORT}"
        fi
        if http_probe "http://127.0.0.1/"; then
          success "Nginx responde em http://127.0.0.1/"
        else
          warn "Nginx não respondeu em http://127.0.0.1/"
        fi
        pause
        ;;
      2)
        section "REINICIAR TUDO"
        resolve_php_fpm
        resolve_mariadb_service
        systemctl restart "$DB_SERVICE" 2>/dev/null || true
        [[ -n "$PHP_FPM_SERVICE" ]] && systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null || true
        restart_nginx_safe
        restart_pm2_safe || true
        pause
        ;;
      3)
        section "REINICIAR NGINX"
        restart_nginx_safe
        pause
        ;;
      4)
        section "REINICIAR PM2"
        restart_pm2_safe || true
        pause
        ;;
      5)
        section "REINICIAR MARIADB"
        resolve_mariadb_service
        if systemctl restart "$DB_SERVICE"; then
          success "${DB_SERVICE} reiniciado."
        else
          fail "Falha ao reiniciar ${DB_SERVICE}."
        fi
        pause
        ;;
      0) break ;;
      *) warn "Opção inválida."; pause ;;
    esac
  done
}

show_tail_file() {
  local file="$1" lines="${2:-80}"
  if [[ -f "$file" ]]; then
    tail -n "$lines" "$file"
  else
    fail "Log não encontrado: $file"
  fi
}

menu_logs() {
  while true; do
    box_title
    section "LOGS"
    echo -e "  ${C_BOLD}[1]${C_RESET} Logs ${APP_NAME} (PM2)"
    echo -e "  ${C_BOLD}[2]${C_RESET} Logs Nginx (error)"
    echo -e "  ${C_BOLD}[3]${C_RESET} Log da instalação"
    echo -e "  ${C_BOLD}[0]${C_RESET} Voltar"
    echo
    ask_option
    case "$MENU_OPT" in
      1)
        section "PM2 — ${APP_PM2_NAME}"
        resolve_pm2_bin
        if pm2_process_exists; then
          run_as_app "$PM2_BIN logs '$APP_PM2_NAME' --lines 100 --nostream" 2>/dev/null || fail "PM2 indisponível."
        else
          warn "Processo PM2 não encontrado. Tentando log file direto..."
          show_tail_file "$PM2_LOG_DIR/${APP_PM2_NAME}-out.log" 80
          show_tail_file "$PM2_LOG_DIR/${APP_PM2_NAME}-error.log" 80
        fi
        pause
        ;;
      2)
        section "NGINX — ERROR LOG"
        show_tail_file "/var/log/nginx/${APP_SLUG}.error.log" 100
        pause
        ;;
      3)
        section "LOG DA INSTALAÇÃO"
        show_tail_file "$LOG_FILE" 120
        pause
        ;;
      0) break ;;
      *) warn "Opção inválida."; pause ;;
    esac
  done
}

open_database_shell() {
  resolve_db_bins
  load_app_env

  [[ -n "$DB_CLIENT_BIN" ]] || { fail "Cliente MariaDB/MySQL não encontrado."; pause; return; }

  echo
  info "Abrindo shell SQL para ${DB_NAME} em ${DB_HOST}:${DB_PORT}..."
  MYSQL_PWD="$DB_PASS" "$DB_CLIENT_BIN" --protocol=tcp -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME"
}

backup_database() {
  resolve_db_bins
  load_app_env

  [[ -n "$DB_DUMP_BIN" ]] || { fail "Ferramenta de dump não encontrada."; pause; return; }

  install -d -m 0700 "$BACKUP_DIR"
  local outfile="$BACKUP_DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"

  info "Gerando backup..."
  if MYSQL_PWD="$DB_PASS" "$DB_DUMP_BIN" --protocol=tcp -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" > "$outfile"; then
    chmod 0600 "$outfile"
    success "Backup salvo em: $outfile"
  else
    rm -f "$outfile"
    fail "Falha ao gerar backup."
  fi
}

menu_banco() {
  while true; do
    box_title
    section "BANCO DE DADOS"
    echo -e "  ${C_BOLD}[1]${C_RESET} Acessar MySQL/MariaDB"
    echo -e "  ${C_BOLD}[2]${C_RESET} Backup do banco"
    echo -e "  ${C_BOLD}[0]${C_RESET} Voltar"
    echo
    ask_option
    case "$MENU_OPT" in
      1) open_database_shell ;;
      2) section "BACKUP DO BANCO"; backup_database; pause ;;
      0) break ;;
      *) warn "Opção inválida."; pause ;;
    esac
  done
}

check_url() {
  local url="$1"
  if curl -fsS --max-time 6 "$url" -o /dev/null >/dev/null 2>&1; then
    echo -e "  ${C_GREEN}[✔]${C_RESET} $url"
  else
    echo -e "  ${C_RED}[✘]${C_RESET} $url"
  fi
}

menu_diagnostico() {
  while true; do
    box_title
    section "DIAGNÓSTICO"
    echo -e "  ${C_BOLD}[1]${C_RESET} Verificar portas em uso"
    echo -e "  ${C_BOLD}[2]${C_RESET} Testar URLs"
    echo -e "  ${C_BOLD}[3]${C_RESET} Checar versões instaladas"
    echo -e "  ${C_BOLD}[0]${C_RESET} Voltar"
    echo
    ask_option
    case "$MENU_OPT" in
      1)
        section "PORTAS EM USO"
        ss -ltnp | awk 'NR==1 || /:(80|443|3000|3306) /'
        pause
        ;;
      2)
        section "TESTE DE URLS"
        load_app_env
        resolve_domain
        check_url "http://127.0.0.1:${APP_PORT}"
        check_url "http://127.0.0.1/"
        check_url "http://127.0.0.1/api/settings"
        if [[ -d "$SOCIALPROOF_DIR" ]]; then
          check_url "http://127.0.0.1/socialproof/"
        fi
        if [[ "$APP_DOMAIN" != "localhost" ]]; then
          check_url "http://${APP_DOMAIN}/"
        fi
        pause
        ;;
      3)
        section "VERSÕES INSTALADAS"
        resolve_pm2_bin
        resolve_db_bins
        echo -e "  ${C_BOLD}Node:${C_RESET}     $(node -v 2>/dev/null || echo 'não instalado')"
        echo -e "  ${C_BOLD}npm:${C_RESET}      $(npm -v 2>/dev/null || echo 'não instalado')"
        echo -e "  ${C_BOLD}PHP:${C_RESET}      $(php -v 2>/dev/null | head -1 || echo 'não instalado')"
        echo -e "  ${C_BOLD}Nginx:${C_RESET}    $(nginx -v 2>&1 || echo 'não instalado')"
        echo -e "  ${C_BOLD}MariaDB:${C_RESET}  $(${DB_CLIENT_BIN:-mariadb} --version 2>/dev/null || echo 'não instalado')"
        echo -e "  ${C_BOLD}PM2:${C_RESET}      $(run_as_app "$PM2_BIN -v" 2>/dev/null || echo 'não instalado')"
        pause
        ;;
      0) break ;;
      *) warn "Opção inválida."; pause ;;
    esac
  done
}

toggle_mode() {
  section "ALTERAR MODE"
  load_app_env
  resolve_pm2_bin

  [[ -d "$INSTALL_DIR" ]] || { fail "Diretório da aplicação não encontrado: $INSTALL_DIR"; pause; return; }
  [[ -f "$APP_ENV_FILE" ]] || { fail "Arquivo .env não encontrado em $APP_ENV_FILE"; pause; return; }
  [[ -d "$APP_HOME" ]] || install -d -m 0755 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME"

  local current_mode="$(get_current_mode)"

  echo -e "  ${C_BOLD}Modo atual:${C_RESET} $(mode_label "$current_mode")"
  echo

  if [[ "$current_mode" == "production" ]]; then
    cp "$APP_ENV_FILE" "$APP_ENV_PROD"
    chown "$APP_USER:$APP_GROUP" "$APP_ENV_PROD"
    chmod 0640 "$APP_ENV_PROD"
    success "Snapshot salvo: .env.production"

    if [[ -f "$APP_ENV_DEV" ]]; then
      cp "$APP_ENV_DEV" "$APP_ENV_FILE"
      success ".env.development restaurado."
    else
      cp "$APP_ENV_PROD" "$APP_ENV_FILE"
      replace_or_append_env_var "$APP_ENV_FILE" NODE_ENV development
      warn ".env.development ausente. Criado a partir do .env atual."
    fi
    replace_or_append_env_var "$APP_ENV_FILE" NODE_ENV development
    chown "$APP_USER:$APP_GROUP" "$APP_ENV_FILE"
    chmod 0640 "$APP_ENV_FILE"

    info "Instalando dependências de desenvolvimento..."
    run_as_app "cd '$INSTALL_DIR' && rm -rf node_modules"
    if [[ -f "$INSTALL_DIR/package-lock.json" ]]; then
      run_as_app "cd '$INSTALL_DIR' && npm ci --silent --cache '$APP_HOME/.npm'"
    else
      run_as_app "cd '$INSTALL_DIR' && npm install --silent --cache '$APP_HOME/.npm'"
    fi
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"

    restart_pm2_current_mode
    success "Aplicação alternada para DEV."

  else
    cp "$APP_ENV_FILE" "$APP_ENV_DEV"
    chown "$APP_USER:$APP_GROUP" "$APP_ENV_DEV"
    chmod 0640 "$APP_ENV_DEV"
    success "Snapshot salvo: .env.development"

    if [[ -f "$APP_ENV_PROD" ]]; then
      cp "$APP_ENV_PROD" "$APP_ENV_FILE"
      success ".env.production restaurado."
    else
      cp "$APP_ENV_DEV" "$APP_ENV_FILE"
      replace_or_append_env_var "$APP_ENV_FILE" NODE_ENV production
      warn ".env.production ausente. Criado a partir do .env atual."
    fi
    replace_or_append_env_var "$APP_ENV_FILE" NODE_ENV production
    chown "$APP_USER:$APP_GROUP" "$APP_ENV_FILE"
    chmod 0640 "$APP_ENV_FILE"

    info "Executando build limpo de produção..."
    run_as_app "cd '$INSTALL_DIR' && rm -rf node_modules dist"
    if [[ -f "$INSTALL_DIR/package-lock.json" ]]; then
      run_as_app "cd '$INSTALL_DIR' && npm ci --silent --cache '$APP_HOME/.npm'"
    else
      run_as_app "cd '$INSTALL_DIR' && npm install --silent --cache '$APP_HOME/.npm'"
    fi
    run_as_app "cd '$INSTALL_DIR' && npm run build --silent"

    [[ -d "$INSTALL_DIR/dist" ]] || { fail "Build falhou: dist/ não foi gerado."; pause; return; }

    build_server_if_needed
    run_as_app "cd '$INSTALL_DIR' && npm prune --omit=dev --silent" || true
    chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"

    restart_pm2_current_mode
    success "Aplicação alternada para PROD."
  fi

  echo
  success "Modo final: $(mode_label)"
  pause
}

main_menu() {
  while true; do
    box_title
    load_app_env
    resolve_domain
    echo -e "  ${C_DIM}Instalação:${C_RESET} ${INSTALL_DIR}"
    echo -e "  ${C_DIM}Modo:${C_RESET} $(mode_label)    ${C_DIM}Porta:${C_RESET} ${APP_PORT}    ${C_DIM}Domínio:${C_RESET} ${APP_DOMAIN}"
    echo
    section "MENU PRINCIPAL"
    echo -e "  ${C_BOLD}[0]${C_RESET} Fix"
    echo -e "  ${C_BOLD}[1]${C_RESET} Serviços"
    echo -e "  ${C_BOLD}[2]${C_RESET} Logs"
    echo -e "  ${C_BOLD}[3]${C_RESET} Banco de Dados"
    echo -e "  ${C_BOLD}[4]${C_RESET} Diagnóstico"
    echo -e "  ${C_BOLD}[5]${C_RESET} MODE ($(mode_label))"
    echo -e "  ${C_BOLD}[S]${C_RESET} Sair"
    echo
    ask_option
    case "${MENU_OPT^^}" in
      0) menu_fix ;;
      1) menu_servicos ;;
      2) menu_logs ;;
      3) menu_banco ;;
      4) menu_diagnostico ;;
      5) toggle_mode ;;
      S) echo; success "Saindo."; echo; break ;;
      *) warn "Opção inválida."; pause ;;
    esac
  done
}

bootstrap_checks() {
  resolve_pm2_bin
  resolve_db_bins
  resolve_mariadb_service
  resolve_php_fpm
  load_app_env
  resolve_domain
}

bootstrap_checks
main_menu
