#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERRO] Linha $LINENO: comando falhou." >&2' ERR

log()   { printf '[INFO] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
fatal() { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-999} -eq 0 ]] || fatal "Execute como root: sudo bash init.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_SH="$REPO_DIR/install.sh"
MENU_SH="$REPO_DIR/menu.sh"
UBUNTU_USER="ubuntu"
SUDOERS_FILE="/etc/sudoers.d/90-ubuntu-nopasswd"

BIN_MENU="/usr/local/bin/menu.sh"
START_WRAPPER="/usr/local/bin/start"
PROFILE_ALIAS_FILE="/etc/profile.d/dieta-milenar-start.sh"

MODE="${1:-}"

[[ -f "$INSTALL_SH" ]] || fatal "install.sh não encontrado em $REPO_DIR"
[[ -f "$MENU_SH" ]] || fatal "menu.sh não encontrado em $REPO_DIR"
id "$UBUNTU_USER" >/dev/null 2>&1 || fatal "Usuário '$UBUNTU_USER' não existe nesta máquina"
command -v visudo >/dev/null 2>&1 || fatal "visudo não encontrado. Instale o pacote sudo antes de continuar"

log "Preparando permissões dos arquivos clonados em $REPO_DIR"

chown -R "$UBUNTU_USER:$UBUNTU_USER" "$REPO_DIR"
find "$REPO_DIR" -type d -exec chmod 0750 {} +
find "$REPO_DIR" -type f -exec chmod 0640 {} +
find "$REPO_DIR" -type f -name '*.sh' -exec chmod 0750 {} +
find "$REPO_DIR" -type f \( -iname '*.zip' -o -iname '*.sql' -o -iname '*.env' -o -iname '*.example' \) -exec chmod 0640 {} + 2>/dev/null || true

log "Concedendo administração total ao usuário ubuntu via sudo sem senha"

usermod -aG sudo "$UBUNTU_USER"

for grp in adm systemd-journal www-data docker lxd; do
  getent group "$grp" >/dev/null 2>&1 && usermod -aG "$grp" "$UBUNTU_USER" || true
done

TMP_SUDOERS="$(mktemp)"
cat > "$TMP_SUDOERS" <<'EOS'
ubuntu ALL=(ALL:ALL) NOPASSWD:ALL
EOS
chmod 0440 "$TMP_SUDOERS"
chown root:root "$TMP_SUDOERS"

visudo -cf "$TMP_SUDOERS" >/dev/null
install -m 0440 -o root -g root "$TMP_SUDOERS" "$SUDOERS_FILE"
rm -f "$TMP_SUDOERS"

log "Validando elevação do usuário ubuntu"
su - "$UBUNTU_USER" -c 'sudo -n true' >/dev/null 2>&1 || fatal "Falha ao validar sudo sem senha para ubuntu"

install_menu_and_aliases() {
  log "Instalando menu.sh em /usr/local/bin e criando alias"

  install -m 0755 -o root -g root "$MENU_SH" "$BIN_MENU"

  cat > "$START_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
MENU_PATH="/usr/local/bin/menu.sh"

if [[ ! -f "$MENU_PATH" ]]; then
  echo "Menu não encontrado: $MENU_PATH" >&2
  exit 1
fi

if [[ ${EUID:-999} -ne 0 ]]; then
  exec sudo bash "$MENU_PATH" "$@"
fi

exec bash "$MENU_PATH" "$@"
EOF

  chmod 0755 "$START_WRAPPER"
  chown root:root "$START_WRAPPER"

  cat > "$PROFILE_ALIAS_FILE" <<'EOF'
alias start='/usr/local/bin/start'
EOF
  chmod 0644 "$PROFILE_ALIAS_FILE"
  chown root:root "$PROFILE_ALIAS_FILE"

  ensure_start_alias() {
    local user_name="$1"
    local home_dir="$2"
    local group_name="$3"

    [[ -d "$home_dir" ]] || return 0

    local bashrc="${home_dir}/.bashrc"
    local profile="${home_dir}/.profile"

    touch "$bashrc" "$profile"
    chown "$user_name:$group_name" "$bashrc" "$profile"
    chmod 0644 "$bashrc" "$profile"

    for rc in "$bashrc" "$profile"; do
      if ! grep -q 'START_ALIAS_DIETA_MILENAR' "$rc" 2>/dev/null; then
        cat >> "$rc" <<'EOF'

# START_ALIAS_DIETA_MILENAR
alias start='/usr/local/bin/start'
# END_START_ALIAS_DIETA_MILENAR
EOF
      fi
    done
  }

  ensure_start_alias root /root root
  ensure_start_alias "$UBUNTU_USER" "/home/$UBUNTU_USER" "$UBUNTU_USER"
}

open_menu() {
  log "Executando menu"
  exec bash "$START_WRAPPER"
}

run_install_stack() {
  log "Executando install.sh"
  exec bash "$INSTALL_SH"
}

install_menu_and_aliases

case "$MODE" in
  --install-stack)
    run_install_stack
    ;;
  ""|--menu)
    open_menu
    ;;
  *)
    fatal "Modo inválido: $MODE"
    ;;
esac
