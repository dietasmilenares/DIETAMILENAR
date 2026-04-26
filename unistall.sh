#!/usr/bin/env bash
# =============================================================================
# DIETA MILENAR — UNINSTALL ENTERPRISE / ROLLBACK SEGURO DE STACK
# Objetivo: remover somente o que pertence à stack do install.sh sem apagar
# configurações genéricas do sistema por padrão.
#
# Modos:
#   padrão                -> rollback seguro da stack
#   --purge-shared-packages -> também purga nginx/mariadb/php/nodejs/certbot/pm2
#   --remove-swap           -> remove /swapfile criado pelo installer, se compatível
#   --delete-certs          -> remove certificados Let's Encrypt do vhost detectado
#   --dry-run               -> simula sem alterar
#   --yes                   -> não pede confirmação
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="Dieta Milenar"
APP_SLUG="dieta-milenar"
APP_USER="dieta"
APP_GROUP="dieta"
APP_HOME="/var/lib/${APP_USER}"
INSTALL_DIR="/var/www/dieta-milenar"
SOCIALPROOF_DIR="/var/www/socialproof"
PHPMYADMIN_DIR="/var/www/phpmyadmin"
LOG_DIR="/var/log/dieta-milenar"
INSTALL_LOG="/var/log/dieta-milenar-install.log"
NGINX_SITE_AVAIL="/etc/nginx/sites-available/${APP_SLUG}"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/${APP_SLUG}"
PM2_SERVICE="pm2-${APP_USER}"
TEMP_EXTRACT_DIR="/tmp/dieta-milenar-extract"
NODESOURCE_LIST="/etc/apt/sources.list.d/nodesource.list"
NODESOURCE_KEY="/etc/apt/keyrings/nodesource.gpg"
SWAP_FILE="/swapfile"
BIN_MENU="/usr/local/bin/menu.sh"
START_WRAPPER="/usr/local/bin/start"
PROFILE_ALIAS_FILE="/etc/profile.d/dieta-milenar-start.sh"

DRY_RUN=0
PURGE_SHARED_PACKAGES=0
REMOVE_SWAP=0
DELETE_CERTS=0
ASSUME_YES=0

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'

info()    { echo -e "${C_CYAN}[•]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}[✔]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
fail()    { echo -e "${C_RED}[✘]${C_RESET} $*"; exit 1; }

on_err() {
  echo -e "${C_RED}[✘]${C_RESET} Falha na linha $1 (cmd: $2)"
  exit 1
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

run() {
  if (( DRY_RUN )); then
    echo "+ $*"
  else
    eval "$@"
  fi
}

usage() {
  cat <<USAGE
Uso: sudo bash unistall.sh [opções]

Opções:
  --purge-shared-packages  Purga nginx/mariadb/php/nodejs/certbot/pm2 também.
  --remove-swap            Remove /swapfile e reverte vm.swappiness=10 se aplicado.
  --delete-certs           Remove certificados Let's Encrypt do vhost detectado.
  --dry-run                Simula sem alterar nada.
  --yes                    Não pede confirmação.
  -h, --help               Mostra esta ajuda.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --purge-shared-packages) PURGE_SHARED_PACKAGES=1 ;;
    --remove-swap) REMOVE_SWAP=1 ;;
    --delete-certs) DELETE_CERTS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Opção inválida: $arg" ;;
  esac
done

[[ ${EUID:-999} -eq 0 ]] || fail "Execute como root: sudo bash unistall.sh"

install -d -m 0755 /run/lock
exec 9>/run/lock/dieta-milenar-uninstall.lock
flock -n 9 || fail "Outro uninstall já está em execução."

TERM_WIDTH=$(tput cols 2>/dev/null || echo 100)
(( TERM_WIDTH < 80 )) && TERM_WIDTH=80
printf '%b\n' "${C_BOLD}${C_CYAN}$(printf '%*s' "$TERM_WIDTH" '' | tr ' ' '=')${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}DIETA MILENAR — UNINSTALL / ROLLBACK SEGURO${C_RESET}"
printf '%b\n' "${C_BOLD}${C_CYAN}$(printf '%*s' "$TERM_WIDTH" '' | tr ' ' '=')${C_RESET}"

resolve_db_bin() {
  DB_BIN="$(command -v mariadb || command -v mysql || true)"
}

resolve_pm2_bin() {
  PM2_BIN="$(command -v pm2 || true)"
  if [[ -z "$PM2_BIN" ]]; then
    PM2_BIN="$(find /usr/lib/node_modules/pm2/bin /usr/local/lib/node_modules/pm2/bin -type f -name pm2 2>/dev/null | head -1 || true)"
  fi
}

parse_env_if_present() {
  DB_NAME="dieta_milenar"
  DB_USER="dieta_user"
  DB_PASS=""
  DOMAIN_LIST=""

  if [[ -f "$INSTALL_DIR/.env" ]]; then
    DB_NAME="$(awk -F= '/^DB_NAME=/{print substr($0, index($0,$2))}' "$INSTALL_DIR/.env" | tail -1 | sed 's/^ *//;s/ *$//')"
    DB_USER="$(awk -F= '/^DB_USER=/{print substr($0, index($0,$2))}' "$INSTALL_DIR/.env" | tail -1 | sed 's/^ *//;s/ *$//')"
    DB_PASS="$(awk -F= '/^DB_PASS=/{print substr($0, index($0,$2))}' "$INSTALL_DIR/.env" | tail -1)"
  fi

  if [[ -f "$NGINX_SITE_AVAIL" ]]; then
    DOMAIN_LIST="$(awk '/^[[:space:]]*server_name[[:space:]]+/ {
      for (i=2;i<=NF;i++) {
        gsub(/;/, "", $i)
        if ($i != "_" && $i != "localhost" && $i !~ /^\$/) print $i
      }
    }' "$NGINX_SITE_AVAIL" | sed '/^www\./d' | sort -u | xargs 2>/dev/null || true)"
  fi
}

confirm() {
  cat <<MSG

Ações do modo padrão:
- parar/remover processo PM2 da stack
- remover app, socialproof, phpMyAdmin, logs e vhost Nginx da stack
- remover bancos da stack (${DB_NAME} e socialproof) e usuário MySQL (${DB_USER})
- remover usuário/grupo dedicados da stack (${APP_USER}:${APP_GROUP})
- remover repositório NodeSource criado pelo installer
- restaurar site default do Nginx se existir

NÃO remove por padrão:
- pacotes compartilhados do sistema (nginx, mariadb, php, nodejs, certbot)
- swap do sistema
- certificados Let's Encrypt

Flags extras atuais:
- purge_shared_packages=${PURGE_SHARED_PACKAGES}
- remove_swap=${REMOVE_SWAP}
- delete_certs=${DELETE_CERTS}
- dry_run=${DRY_RUN}
MSG

  if (( ASSUME_YES || DRY_RUN )); then
    return 0
  fi

  read -r -p "Continuar? [y/N]: " ans
  [[ "$ans" =~ ^[yYsS]$ ]] || fail "Abortado."
}

stop_pm2_stack() {
  resolve_pm2_bin

  if systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${PM2_SERVICE}.service"; then
    info "Parando serviço systemd ${PM2_SERVICE}..."
    run "systemctl disable --now '${PM2_SERVICE}' >/dev/null 2>&1 || true"
  fi

  if [[ -n "${PM2_BIN:-}" && -x "${PM2_BIN:-/nonexistent}" ]] && id -u "$APP_USER" >/dev/null 2>&1; then
    info "Parando processo PM2 ${APP_SLUG}..."
    run "runuser -l '$APP_USER' -c '\"$PM2_BIN\" stop \"$APP_SLUG\" >/dev/null 2>&1 || true'"
    run "runuser -l '$APP_USER' -c '\"$PM2_BIN\" delete \"$APP_SLUG\" >/dev/null 2>&1 || true'"
    run "runuser -l '$APP_USER' -c '\"$PM2_BIN\" save --force >/dev/null 2>&1 || true'"
  fi

  if [[ -f "/etc/systemd/system/${PM2_SERVICE}.service" ]]; then
    info "Removendo unit file do PM2..."
    run "rm -f '/etc/systemd/system/${PM2_SERVICE}.service'"
    run "systemctl daemon-reload"
  fi
}

cleanup_nginx_stack() {
  if [[ -L "$NGINX_SITE_ENABLED" || -f "$NGINX_SITE_ENABLED" ]]; then
    info "Removendo symlink do vhost Nginx da stack..."
    run "rm -f '$NGINX_SITE_ENABLED'"
  fi

  if [[ -f "$NGINX_SITE_AVAIL" ]]; then
    info "Removendo configuração Nginx da stack..."
    run "rm -f '$NGINX_SITE_AVAIL'"
  fi

  if [[ -f /etc/nginx/sites-available/default && ! -e /etc/nginx/sites-enabled/default ]]; then
    info "Restaurando site default do Nginx..."
    run "ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default"
  fi

  if command -v nginx >/dev/null 2>&1; then
    info "Validando e recarregando Nginx..."
    if (( DRY_RUN )); then
      echo "+ nginx -t && systemctl reload nginx || systemctl restart nginx"
    else
      if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
      else
        warn "nginx -t falhou após limpeza. Verifique outros vhosts do servidor."
      fi
    fi
  fi
}

cleanup_certs() {
  (( DELETE_CERTS )) || return 0
  [[ -n "${DOMAIN_LIST:-}" ]] || { warn "Nenhum domínio detectado para remover certificados."; return 0; }

  if ! command -v certbot >/dev/null 2>&1; then
    warn "certbot não encontrado; certificados não removidos."
    return 0
  fi

  for domain in $DOMAIN_LIST; do
    [[ -n "$domain" ]] || continue
    info "Removendo certificado Let's Encrypt: $domain"
    run "certbot delete --cert-name '$domain' --non-interactive >/dev/null 2>&1 || true"
  done
}

cleanup_files() {
  local path
  for path in "$INSTALL_DIR" "$SOCIALPROOF_DIR" "$PHPMYADMIN_DIR" "$LOG_DIR" "$INSTALL_LOG" "$TEMP_EXTRACT_DIR" "$BIN_MENU" "$START_WRAPPER" "$PROFILE_ALIAS_FILE"; do
    if [[ -e "$path" ]]; then
      info "Removendo: $path"
      run "rm -rf '$path'"
    fi
  done

  remove_start_alias_block() {
    local rc_file="$1"
    [[ -f "$rc_file" ]] || return 0
    if (( DRY_RUN )); then
      echo "+ sed -i '/# START_ALIAS_DIETA_MILENAR/,/# END_START_ALIAS_DIETA_MILENAR/d' '$rc_file'"
    else
      sed -i '/# START_ALIAS_DIETA_MILENAR/,/# END_START_ALIAS_DIETA_MILENAR/d' "$rc_file"
    fi
  }

  remove_start_alias_block /root/.bashrc
  remove_start_alias_block /root/.profile
  remove_start_alias_block /home/ubuntu/.bashrc
  remove_start_alias_block /home/ubuntu/.profile
}

cleanup_database() {
  resolve_db_bin
  [[ -n "${DB_BIN:-}" ]] || { warn "Cliente MariaDB/MySQL não encontrado; pulando limpeza de banco."; return 0; }

  if ! "$DB_BIN" --protocol=socket -u root -e 'SELECT 1' >/dev/null 2>&1; then
    warn "Sem acesso root via socket no MariaDB/MySQL; pulando limpeza de banco."
    return 0
  fi

  info "Removendo bancos e usuário MySQL da stack..."
  local db_name_esc db_user_esc
  db_name_esc="${DB_NAME//\`/}"
  db_user_esc="${DB_USER//\'/}"

  if (( DRY_RUN )); then
    cat <<SQL
+ ${DB_BIN} --protocol=socket -u root <<'EOSQL'
DROP DATABASE IF EXISTS \`${db_name_esc}\`;
DROP DATABASE IF EXISTS \`socialproof\`;
DROP USER IF EXISTS '${db_user_esc}'@'localhost';
DROP USER IF EXISTS '${db_user_esc}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOSQL
SQL
  else
    "$DB_BIN" --protocol=socket -u root <<EOSQL
DROP DATABASE IF EXISTS \`${db_name_esc}\`;
DROP DATABASE IF EXISTS \`socialproof\`;
DROP USER IF EXISTS '${db_user_esc}'@'localhost';
DROP USER IF EXISTS '${db_user_esc}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOSQL
  fi
}

cleanup_user_group() {
  if getent group "$APP_GROUP" >/dev/null 2>&1 && id -u www-data >/dev/null 2>&1; then
    info "Removendo www-data do grupo ${APP_GROUP}..."
    run "gpasswd -d www-data '$APP_GROUP' >/dev/null 2>&1 || true"
  fi

  if id -u "$APP_USER" >/dev/null 2>&1; then
    info "Removendo usuário dedicado ${APP_USER}..."
    run "userdel -r '$APP_USER' >/dev/null 2>&1 || userdel '$APP_USER' >/dev/null 2>&1 || true"
  fi

  if getent group "$APP_GROUP" >/dev/null 2>&1; then
    info "Removendo grupo dedicado ${APP_GROUP}..."
    run "groupdel '$APP_GROUP' >/dev/null 2>&1 || true"
  fi

  if [[ -d "$APP_HOME" ]]; then
    info "Removendo home residual: $APP_HOME"
    run "rm -rf '$APP_HOME'"
  fi
}

cleanup_nodesource() {
  if [[ -f "$NODESOURCE_LIST" ]]; then
    info "Removendo repositório NodeSource da stack..."
    run "rm -f '$NODESOURCE_LIST'"
  fi
  if [[ -f "$NODESOURCE_KEY" ]]; then
    info "Removendo keyring NodeSource da stack..."
    run "rm -f '$NODESOURCE_KEY'"
  fi
  if (( ! DRY_RUN )); then
    apt-get update -qq >/dev/null 2>&1 || true
  fi
}

cleanup_swap() {
  (( REMOVE_SWAP )) || return 0

  if [[ -f "$SWAP_FILE" ]]; then
    info "Removendo swapfile da stack..."
    if (( DRY_RUN )); then
      echo "+ swapoff '$SWAP_FILE' || true"
      echo "+ sed -i '\|^$SWAP_FILE none swap sw 0 0$|d' /etc/fstab"
      echo "+ sed -i '/^vm\.swappiness=10$/d' /etc/sysctl.conf"
      echo "+ rm -f '$SWAP_FILE'"
    else
      swapoff "$SWAP_FILE" >/dev/null 2>&1 || true
      sed -i "\|^$SWAP_FILE none swap sw 0 0$|d" /etc/fstab
      sed -i '/^vm\.swappiness=10$/d' /etc/sysctl.conf
      rm -f "$SWAP_FILE"
      sysctl -p >/dev/null 2>&1 || true
    fi
  else
    warn "Swapfile não encontrado; nada para remover."
  fi
}

purge_shared_packages() {
  (( PURGE_SHARED_PACKAGES )) || return 0

  info "Purgando pacotes compartilhados da stack..."

  if [[ -n "${PM2_BIN:-}" && -x "${PM2_BIN:-/nonexistent}" ]] && command -v npm >/dev/null 2>&1; then
    run "npm uninstall -g pm2 >/dev/null 2>&1 || true"
  fi

  local pkgs=(
    nginx
    nginx-common
    mariadb-server
    mariadb-client
    php
    php-fpm
    php-mysql
    php-mbstring
    php-zip
    php-gd
    php-curl
    nodejs
    certbot
    python3-certbot-nginx
  )

  local installed=()
  local pkg
  for pkg in "${pkgs[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      installed+=("$pkg")
    fi
  done

  if (( ${#installed[@]} > 0 )); then
    run "apt-get autoremove --purge -y ${installed[*]} >/dev/null 2>&1 || true"
  else
    warn "Nenhum pacote compartilhado da lista estava instalado."
  fi
}

final_summary() {
  echo
  printf '%b\n' "${C_BOLD}${C_GREEN}$(printf '%*s' "$TERM_WIDTH" '' | tr ' ' '=')${C_RESET}"
  echo -e "${C_BOLD}${C_GREEN}ROLLBACK DA STACK CONCLUÍDO${C_RESET}"
  printf '%b\n' "${C_BOLD}${C_GREEN}$(printf '%*s' "$TERM_WIDTH" '' | tr ' ' '=')${C_RESET}"
  echo "- removido: app, socialproof, phpMyAdmin, vhost Nginx, PM2 da stack, logs, bancos e usuário dedicados"
  echo "- preservado por padrão: pacotes compartilhados, swap, certificados"
  echo "- flags usadas: purge=${PURGE_SHARED_PACKAGES}, swap=${REMOVE_SWAP}, certs=${DELETE_CERTS}, dry_run=${DRY_RUN}"
}

parse_env_if_present
confirm
stop_pm2_stack
cleanup_nginx_stack
cleanup_certs
cleanup_database
cleanup_files
cleanup_user_group
cleanup_nodesource
cleanup_swap
purge_shared_packages
final_summary
