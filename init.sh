#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERRO] Linha $LINENO: comando falhou." >&2' ERR

log()   { printf '[INFO] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
fatal() { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-999} -eq 0 ]] || fatal "Execute como root: sudo bash init.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_SH="$REPO_DIR/install.sh"
UBUNTU_USER="ubuntu"
SUDOERS_FILE="/etc/sudoers.d/90-ubuntu-nopasswd"

[[ -f "$INSTALL_SH" ]] || fatal "install.sh não encontrado em $REPO_DIR"
id "$UBUNTU_USER" >/dev/null 2>&1 || fatal "Usuário '$UBUNTU_USER' não existe nesta máquina"
command -v visudo >/dev/null 2>&1 || fatal "visudo não encontrado. Instale o pacote sudo antes de continuar"

log "Preparando permissões dos arquivos clonados em $REPO_DIR"

# Dono principal do repositório: ubuntu.
# Root continua com acesso total por privilégio administrativo.
chown -R "$UBUNTU_USER:$UBUNTU_USER" "$REPO_DIR"

# Diretórios: dono rwx, grupo rx, outros sem acesso.
find "$REPO_DIR" -type d -exec chmod 0750 {} +

# Arquivos regulares: dono rw, grupo r, outros sem acesso.
find "$REPO_DIR" -type f -exec chmod 0640 {} +

# Scripts shell executáveis.
find "$REPO_DIR" -type f -name '*.sh' -exec chmod 0750 {} +

# ZIPs legíveis pelo grupo ubuntu.
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

log "Executando install.sh"
exec bash "$INSTALL_SH"
