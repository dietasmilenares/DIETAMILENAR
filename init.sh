#!/usr/bin/env bash
# =============================================================================
# DIETA MILENAR — BOOTSTRAP ENTERPRISE
# Instala o menu operacional, prepara permissões do repositório e abre o menu.
# Compatível com Ubuntu 22.04+ em máquina limpa.
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

APP_NAME="Dieta Milenar"
APP_USER="dieta"
APP_GROUP="dieta"
APP_HOME="/var/lib/${APP_USER}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_SH="${REPO_DIR}/install.sh"
MENU_SH="${REPO_DIR}/menu.sh"
UNINSTALL_SH="${REPO_DIR}/unistall.sh"
BIN_MENU="/usr/local/bin/menu.sh"
START_WRAPPER="/usr/local/bin/start"
PROFILE_ALIAS_FILE="/etc/profile.d/dieta-milenar-start.sh"
MODE="${1:---menu}"

C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_CYAN='\033[0;36m'
log()   { printf '%b[INFO]%b %s\n' "$C_CYAN" "$C_RESET" "$*"; }
warn()  { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fatal() { printf '%b[ERRO]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
ok()    { printf '%b[OK]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }

on_err() { fatal "Falha na linha $1 (cmd: $2)"; }
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

[[ ${EUID:-999} -eq 0 ]] || fatal "Execute como root: sudo bash init.sh"
[[ -f "$INSTALL_SH" ]] || fatal "install.sh não encontrado em ${REPO_DIR}"
[[ -f "$MENU_SH" ]] || fatal "menu.sh não encontrado em ${REPO_DIR}"
[[ -f "$UNINSTALL_SH" ]] || warn "unistall.sh não encontrado em ${REPO_DIR}"

ADMIN_USER="${SUDO_USER:-}"
if [[ -z "$ADMIN_USER" || "$ADMIN_USER" == "root" ]] || ! id "$ADMIN_USER" >/dev/null 2>&1; then
  if id ubuntu >/dev/null 2>&1; then ADMIN_USER="ubuntu"; else ADMIN_USER="root"; fi
fi
ADMIN_HOME="$(getent passwd "$ADMIN_USER" | cut -d: -f6 || true)"; [[ -n "$ADMIN_HOME" ]] || ADMIN_HOME="/root"
ADMIN_GROUP="$(id -gn "$ADMIN_USER" 2>/dev/null || echo root)"

ensure_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "Validando pacotes base"
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y -qq --no-install-recommends sudo ca-certificates curl git unzip rsync openssl >/dev/null 2>&1 || true
}

ensure_app_user() {
  log "Garantindo usuário dedicado ${APP_USER}"
  getent group "$APP_GROUP" >/dev/null 2>&1 || groupadd --system "$APP_GROUP"
  if ! getent passwd "$APP_USER" >/dev/null 2>&1; then
    useradd --system --home-dir "$APP_HOME" --create-home --shell /bin/bash --gid "$APP_GROUP" "$APP_USER"
  else
    usermod -d "$APP_HOME" -s /bin/bash -g "$APP_GROUP" "$APP_USER" >/dev/null 2>&1 || true
  fi
  install -d -m 0755 -o "$APP_USER" -g "$APP_GROUP" "$APP_HOME" "$APP_HOME/.npm" /var/log/dieta-milenar
  chown -R "$APP_USER:$APP_GROUP" "$APP_HOME" /var/log/dieta-milenar
}

prepare_repo_permissions() {
  log "Preparando permissões do repositório em ${REPO_DIR}"
  if [[ "$ADMIN_USER" != "root" ]]; then chown -R "$ADMIN_USER:$ADMIN_GROUP" "$REPO_DIR"; fi
  find "$REPO_DIR" -type d -exec chmod 0755 {} +
  find "$REPO_DIR" -type f -exec chmod 0644 {} +
  find "$REPO_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
}

ensure_admin_sudo() {
  [[ "$ADMIN_USER" != "root" ]] || return 0
  log "Garantindo sudo administrativo para ${ADMIN_USER}"
  usermod -aG sudo "$ADMIN_USER" >/dev/null 2>&1 || true
  command -v visudo >/dev/null 2>&1 || return 0
  local sudoers_file="/etc/sudoers.d/90-${ADMIN_USER}-dieta-milenar" tmp
  tmp="$(mktemp)"
  printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$ADMIN_USER" > "$tmp"
  chmod 0440 "$tmp"; chown root:root "$tmp"
  visudo -cf "$tmp" >/dev/null
  install -m 0440 -o root -g root "$tmp" "$sudoers_file"
  rm -f "$tmp"
}

write_start_alias() {
  local user_name="$1" home_dir="$2" group_name="$3" rc
  [[ -d "$home_dir" ]] || return 0
  for rc in "$home_dir/.bashrc" "$home_dir/.profile"; do
    touch "$rc"; chown "$user_name:$group_name" "$rc" 2>/dev/null || true; chmod 0644 "$rc" 2>/dev/null || true
    grep -q 'START_ALIAS_DIETA_MILENAR' "$rc" 2>/dev/null || cat >> "$rc" <<'EOF'

# START_ALIAS_DIETA_MILENAR
alias start='/usr/local/bin/start'
# END_START_ALIAS_DIETA_MILENAR
EOF
  done
}

install_menu_and_aliases() {
  log "Instalando menu operacional"
  install -d -m 0755 /usr/local/bin
  install -m 0755 -o root -g root "$MENU_SH" "$BIN_MENU"
  cat > "$START_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
MENU_PATH="/usr/local/bin/menu.sh"
if [[ ! -f "$MENU_PATH" ]]; then echo "Menu não encontrado: $MENU_PATH" >&2; exit 1; fi
if [[ ${EUID:-999} -ne 0 ]]; then exec sudo bash "$MENU_PATH" "$@"; fi
exec bash "$MENU_PATH" "$@"
EOF
  chmod 0755 "$START_WRAPPER"; chown root:root "$START_WRAPPER"
  printf "alias start='/usr/local/bin/start'\n" > "$PROFILE_ALIAS_FILE"
  chmod 0644 "$PROFILE_ALIAS_FILE"; chown root:root "$PROFILE_ALIAS_FILE"
  write_start_alias root /root root
  [[ "$ADMIN_USER" == "root" ]] || write_start_alias "$ADMIN_USER" "$ADMIN_HOME" "$ADMIN_GROUP"
  ok "Menu instalado em ${BIN_MENU}"
  ok "Comando global criado: start"
}

run_install_stack() { log "Executando install.sh"; exec bash "$INSTALL_SH"; }
open_menu() { log "Abrindo menu operacional"; exec bash "$START_WRAPPER"; }

ensure_base_packages
ensure_app_user
prepare_repo_permissions
ensure_admin_sudo
install_menu_and_aliases

case "$MODE" in
  --install-stack|install|--install) run_install_stack ;;
  --menu|menu|"") open_menu ;;
  *) fatal "Modo inválido: $MODE. Use: --menu ou --install-stack" ;;
esac
