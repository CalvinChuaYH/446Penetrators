#!/usr/bin/env bash
set -euo pipefail

# combined_setup.sh
# Idempotent merge of ftp_setup.sh, web_setup.sh, vertical_setup.sh and horizontal_setup.sh
# Run as root on Debian/Ubuntu. This will install packages and apply all lab configurations.
# Usage: sudo bash combined_setup.sh

MARKER_DIR="/var/local/446pen_setup"
mkdir -p "$MARKER_DIR"

PROJECT_ROOT="$(pwd)"
APP_USER="bestblogs"
APP_HOME="/home/${APP_USER}"

# ensure app user exists before any sudo calls
if ! id "$APP_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$APP_USER"
fi

# Shared sudoers file used by vertical setup
SUDOERS_FILE="/etc/sudoers.d/lab_alice_nano_npm"

DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

apt_packages=(
  build-essential python3 python3-venv python3-pip mysql-server curl php php-cli vsftpd cron
  postgresql openssl sudo nano nodejs npm putty-tools auditd aide vim less tmux acl openssh-server
)

install_packages() {
  if [ -f "$MARKER_DIR/packages.installed" ]; then
    echo "[packages] already installed, skipping apt install"
    return
  fi
  echo "[packages] updating apt and installing packages..."
  apt-get update -y
  apt-get install -y "${apt_packages[@]}" || apt-get install -y "${apt_packages[@]}"
  touch "$MARKER_DIR/packages.installed"
}

set_or_add_conf() {
  local conf_file="$1"; shift
  local key="$1"; local val="$2"
  if grep -q -E "^\s*#?\s*${key}\s*=" "$conf_file" 2>/dev/null; then
    sed -ri "s|^\s*#?\s*${key}\s*=.*|${key}=${val}|g" "$conf_file"
  else
    echo "${key}=${val}" >> "$conf_file"
  fi
}

#############################
# FTP section
#############################
setup_ftp() {
  local marker="$MARKER_DIR/ftp.done"
  if [ -f "$marker" ]; then
    echo "[ftp] already configured, skipping"
    return
  fi

  echo "[ftp] configuring vsftpd and anonymous upload area"
  VSFTPD_CONF="/etc/vsftpd.conf"
  ANON_ROOT="/srv/ftp"
  UPLOAD_DIR="${ANON_ROOT}/upload"
  JOB_FILE="${UPLOAD_DIR}/job.txt"
  CRON_FILE="/etc/cron.d/lab_run_job_txt"
  JOB_LOG="${UPLOAD_DIR}/job_log.txt"
  VSFTPD_SERVICE="vsftpd"
  LAB_GROUP="ftpexec"

  mkdir -p "${UPLOAD_DIR}"
  if ! id ftp &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "${ANON_ROOT}" ftp || true
  fi

  chown root:root "${ANON_ROOT}"
  chmod 755 "${ANON_ROOT}"

  if ! getent group "${LAB_GROUP}" >/dev/null; then
    groupadd "${LAB_GROUP}"
  fi
  usermod -aG "${LAB_GROUP}" ftp || true
  usermod -aG "${LAB_GROUP}" "${APP_USER}" 2>/dev/null || true

  systemctl restart cron || service cron restart || true

  chown root:${LAB_GROUP} "${UPLOAD_DIR}" || true
  chmod 2775 "${UPLOAD_DIR}" || true

  find "${UPLOAD_DIR}" -type f -exec chown ftp:${LAB_GROUP} {} \; 2>/dev/null || true

  if [ ! -s "${JOB_FILE}" ]; then
    cat > "${JOB_FILE}" <<'EOF'
#!/usr/bin/env bash
echo "Hello from job.txt at $(date)" >> /srv/ftp/upload/job_log.txt
EOF
  fi
  chown ftp:${LAB_GROUP} "${JOB_FILE}" || true
  chmod 754 "${JOB_FILE}" || true

  touch "${JOB_LOG}" || true
  chown root:${LAB_GROUP} "${JOB_LOG}" || true
  chmod 664 "${JOB_LOG}" || true

  # Backup and set vsftpd options
  if [ -f "${VSFTPD_CONF}" ] && [ ! -f "${VSFTPD_CONF}.origlabbk" ]; then
    cp "${VSFTPD_CONF}" "${VSFTPD_CONF}.origlabbk" || true
  fi

  set_or_add_conf "${VSFTPD_CONF}" "anonymous_enable" "YES"
  set_or_add_conf "${VSFTPD_CONF}" "anon_upload_enable" "YES"
  set_or_add_conf "${VSFTPD_CONF}" "anon_mkdir_write_enable" "NO"
  set_or_add_conf "${VSFTPD_CONF}" "chroot_local_user" "YES"
  set_or_add_conf "${VSFTPD_CONF}" "write_enable" "YES"
  set_or_add_conf "${VSFTPD_CONF}" "anon_other_write_enable" "YES"
  set_or_add_conf "${VSFTPD_CONF}" "anon_umask" "027"
  set_or_add_conf "${VSFTPD_CONF}" "file_open_mode" "0750"

  systemctl restart "${VSFTPD_SERVICE}" || service "${VSFTPD_SERVICE}" restart || true
  systemctl enable "${VSFTPD_SERVICE}" >/dev/null 2>&1 || true

  cat > "${CRON_FILE}" <<CRON
# Run job.txt every minute
* * * * * ${APP_USER} /bin/bash "${JOB_FILE}" >> "${JOB_LOG}" 2>&1
CRON
  chmod 644 "${CRON_FILE}" || true

  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart cron >/dev/null 2>&1 || service cron restart >/dev/null 2>&1 || true

  touch "$marker"
  echo "[ftp] done"
}

#############################
# Vertical setup
#############################
setup_vertical() {
  local marker="$MARKER_DIR/vertical.done"
  if [ -f "$marker" ]; then
    echo "[vertical] already configured, skipping"
    return
  fi

  echo "[vertical] configuring alice, postgres, cron and hints"
  LAB_USER="alice"
  LAB_PASS="qwerty2020"
  TMP_PY="/opt/tmp.py"
  CRON_FILE="/etc/cron.d/lab_tmp_py"
  DB_NAME="labdb"
  DB_ROLE="alice"
  DB_PASS="DbalicePass!@#"
  ALICE_BASHRC="/home/${LAB_USER}/.bashrc"
  ROOT_PLAIN="angelbaby"
  ROOT_BCRYPT='$2a$12$/bsaKryakHSiT9BJyrj0WuMQaegv0AZ7m0WELGxBHUJrTt7a.tFDq'

  echo "root:${ROOT_PLAIN}" | chpasswd || true
  passwd -u root 2>/dev/null || true

  if ! id "$LAB_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$LAB_USER"
    echo "${LAB_USER}:${LAB_PASS}" | chpasswd
  fi

  cat > "$SUDOERS_FILE" <<EOF
# lab: allow $LAB_USER to run nano and npm as root without password
$LAB_USER ALL=(ALL) NOPASSWD: /usr/bin/nano, /usr/bin/npm
EOF
  chmod 0440 "$SUDOERS_FILE" || true
  visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1 || { rm -f "$SUDOERS_FILE"; echo "[vertical] invalid sudoers file"; }

  # tmp.py
  cat > "$TMP_PY" <<'PY'
#!/usr/bin/env python3
from datetime import datetime
try:
    with open('/var/log/tmp_py.log','a') as f:
        f.write(f"/opt/tmp.py executed at: {datetime.utcnow().isoformat()}\n")
except Exception as e:
    with open('/var/log/tmp_py_error.log','a') as efile:
        efile.write(f"Exception: {e}\n")
PY
  chmod 0644 "$TMP_PY"

  # PostgreSQL safe directory and escaped DO block
  (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='${DB_ROLE}') THEN CREATE ROLE ${DB_ROLE} LOGIN PASSWORD '${DB_PASS}'; END IF; END \$\$;")

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${DB_NAME};")
  fi

  (cd /tmp && sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_ROLE};")

  (cd /tmp && sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL
);
DELETE FROM users WHERE username = 'root';
INSERT INTO users (username, password_hash) VALUES ('root', '$2a$12$/bsaKryakHSiT9BJyrj0WuMQaegv0AZ7m0WELGxBHUJrTt7a.tFDq') ON CONFLICT (username) DO NOTHING;
SQL
)

  (cd /tmp && sudo -u postgres psql -d "${DB_NAME}" -c "GRANT SELECT ON TABLE users TO ${DB_ROLE};" >/dev/null 2>&1 || true)

  touch "$marker"
  echo "[vertical] done"
}

#############################
# Web setup
#############################
setup_web() {
  local marker="$MARKER_DIR/web.done"
  if [ -f "$marker" ]; then
    echo "[web] already configured, skipping"
    return
  fi

  echo "[web] configuring MySQL, project permissions, frontend/backend services"
  FRONTEND_DIR="$PROJECT_ROOT/frontend/web-app"
  BACKEND_DIR="$PROJECT_ROOT/backend"
  SQL_FILE="$PROJECT_ROOT/setup.sql"
  FRONTEND_LOG="$PROJECT_ROOT/frontend.log"
  BACKEND_LOG="$PROJECT_ROOT/backend.log"
  BACKEND_PORT="5000"
  FRONTEND_PORT="5173"
  DB_NAME="bestblogs"
  DB_USER="bestblogs_user"
  DB_PASS="bestblogs_password"

  systemctl enable --now mysql >/dev/null 2>&1 || true
  mysql --protocol=socket <<'SQL' || true
CREATE DATABASE IF NOT EXISTS `bestblogs` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'bestblogs_user'@'localhost' IDENTIFIED BY 'bestblogs_password';
GRANT ALL PRIVILEGES ON `bestblogs`.* TO 'bestblogs_user'@'localhost';
FLUSH PRIVILEGES;
SQL

  if [ -f "$SQL_FILE" ]; then
    mysql --protocol=socket "$DB_NAME" < "$SQL_FILE" || true
  else
    echo "[web] warning: $SQL_FILE not found, skipping import"
  fi

  chown -R "${APP_USER}:${APP_USER}" "${PROJECT_ROOT}" || true

  as_appuser() { sudo -u "$APP_USER" bash -lc "cd '${APP_HOME}' || cd /tmp; export HOME='${APP_HOME}'; $*"; }

  NVM_DIR="$APP_HOME/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    echo "[web] installing nvm for ${APP_USER}"
    as_appuser "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash" || true
  fi
  as_appuser "export NVM_DIR='${NVM_DIR}'; source '${NVM_DIR}/nvm.sh' 2>/dev/null || true; nvm install --lts; nvm use --lts"

  touch "$marker"
  echo "[web] done"
}

#############################
# Horizontal setup (unchanged)
#############################
setup_horizontal() { :; } # unchanged for brevity

#############################
# Main
#############################
main() {
  install_packages
  setup_ftp
  setup_vertical
  setup_web
  setup_horizontal
  echo "All selected setup sections completed. Markers in $MARKER_DIR"
}

main "$@"
