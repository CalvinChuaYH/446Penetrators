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
# FTP section (from ftp_setup.sh / web_setup.sh)
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
# Vertical setup (from vertical_setup.sh)
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

  # ensure packages that vertical expects are present (install_packages handles overall install)

  # set root password
  echo "root:${ROOT_PLAIN}" | chpasswd || true
  passwd -u root 2>/dev/null || true

  if ! id "$LAB_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$LAB_USER"
    echo "${LAB_USER}:${LAB_PASS}" | chpasswd
  fi

  # sudoers allowing alice nano & npm (idempotent)
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
  chown root:root "$TMP_PY" || true
  chmod 0644 "$TMP_PY" || true
  # best-effort ACL: if setfacl available
  command -v setfacl >/dev/null 2>&1 && setfacl -m u:"$LAB_USER":rw "$TMP_PY" || true

  touch /var/log/tmp_py.log /var/log/tmp_py_error.log || true
  chown root:root /var/log/tmp_py*.log || true
  chmod 0644 /var/log/tmp_py*.log || true

  cat > "$CRON_FILE" <<CRON
* * * * * root /usr/bin/python3 /opt/tmp.py
CRON
  chmod 0644 "$CRON_FILE" || true

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart cron >/dev/null 2>&1 || true
  else
    service cron restart >/dev/null 2>&1 || true
  fi

  # PostgreSQL: create role, DB, table, insert bcrypt
  systemctl enable --now postgresql >/dev/null 2>&1 || true
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "\
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='${DB_ROLE}') THEN CREATE ROLE ${DB_ROLE} LOGIN PASSWORD '${DB_PASS}'; END IF; END $$;"

  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${DB_NAME};"
  fi

  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_ROLE};"

  sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL
);
DELETE FROM users WHERE username = 'root';
INSERT INTO users (username, password_hash) VALUES ('root', '${ROOT_BCRYPT}') ON CONFLICT (username) DO NOTHING;
SQL

  sudo -u postgres psql -d "${DB_NAME}" -c "GRANT SELECT ON TABLE users TO ${DB_ROLE};" >/dev/null 2>&1 || true

  # export DB creds into alice's .bashrc
  export_block="# BEGIN LAB DB ENV\nexport LAB_DB_NAME='${DB_NAME}'\nexport LAB_DB_USER='${DB_ROLE}'\nexport LAB_DB_PASS='${DB_PASS}'\n# END LAB DB ENV\n"
  touch "$ALICE_BASHRC"
  chown "$LAB_USER:$LAB_USER" "$ALICE_BASHRC" || true
  chmod 0644 "$ALICE_BASHRC" || true
  if ! grep -q "BEGIN LAB DB ENV" "$ALICE_BASHRC" 2>/dev/null; then
    printf "\n%s\n" "$export_block" >> "$ALICE_BASHRC"
    chown "$LAB_USER:$LAB_USER" "$ALICE_BASHRC" || true
  fi

  # SSH allow root login + password auth
  SSH_MAIN="/etc/ssh/sshd_config"
  if grep -q "^PermitRootLogin" "$SSH_MAIN"; then
    sed -i.bak 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$SSH_MAIN"
  else
    echo "PermitRootLogin yes" >> "$SSH_MAIN"
  fi
  if grep -q "^PasswordAuthentication" "$SSH_MAIN"; then
    sed -i.bak 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_MAIN"
  else
    echo "PasswordAuthentication yes" >> "$SSH_MAIN"
  fi
  mkdir -p /etc/ssh/sshd_config.d
  echo "PermitRootLogin yes" > /etc/ssh/sshd_config.d/99-rootlogin.conf
  echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config.d/99-rootlogin.conf
  systemctl restart ssh || true

  # hints and flags
  HINT1_PATH="/home/${LAB_USER}/.hint1"
  HINT2_PATH="/home/${LAB_USER}/.hint2"
  cat > "$HINT1_PATH" <<'H1'
There are 4 ways to do vertical privilege escalation in total on this machine.
All the answers can be found by scanning the machine with linpeas.sh and looking for abnormal configuration/files.
H1
  cat > "$HINT2_PATH" <<'H2'
Try harder before reading this hint.

1st and 2nd: Pretty obvious if you just run sudo -l.
3rd vector: The file you are looking for is located under /opt.
4th vector: Inspect environment variables for secrets or credentials.
H2
  chown "$LAB_USER:$LAB_USER" "$HINT1_PATH" "$HINT2_PATH" || true
  chmod 0640 "$HINT1_PATH" "$HINT2_PATH" || true

  ROOT_FLAG="/root/root.txt"
  cat > "$ROOT_FLAG" <<'FLAG'
Congratulations! 

You’ve successfully escalated privileges to root.

Well done — mission accomplished.
FLAG
  chown root:root "$ROOT_FLAG" || true
  chmod 0400 "$ROOT_FLAG" || true

  touch "$marker"
  echo "[vertical] done"
}

#############################
# Web setup (from web_setup.sh)
#############################
setup_web() {
  local marker="$MARKER_DIR/web.done"
  if [ -f "$marker" ]; then
    echo "[web] already configured, skipping"
    return
  fi

  echo "[web] configuring MySQL, project permissions, frontend/backend services"
  PROJECT_ROOT="${PROJECT_ROOT}"
  FRONTEND_DIR="$PROJECT_ROOT/frontend/web-app"
  BACKEND_DIR="$PROJECT_ROOT/backend"
  SQL_FILE="$PROJECT_ROOT/setup.sql"
  VENV_DIR="$BACKEND_DIR/.venv"
  FRONTEND_LOG="$PROJECT_ROOT/frontend.log"
  BACKEND_LOG="$PROJECT_ROOT/backend.log"
  BACKEND_PORT="5000"
  FRONTEND_PORT="5173"
  DB_NAME="bestblogs"
  DB_USER="bestblogs_user"
  DB_PASS="bestblogs_password"

  systemctl enable --now mysql >/dev/null 2>&1 || true
  mysql --protocol=socket <<SQL || true
CREATE DATABASE IF NOT EXISTS \\`${DB_NAME}\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \\`${DB_NAME}\\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

  if [ -f "$SQL_FILE" ]; then
    mysql --protocol=socket "$DB_NAME" < "$SQL_FILE" || true
  else
    echo "[web] warning: $SQL_FILE not found, skipping import"
  fi

  chown -R "${APP_USER}:${APP_USER}" "${PROJECT_ROOT}" || true

  # Node / NVM setup: attempt to install NVM for app user and install deps
  NVM_DIR="$APP_HOME/.nvm"
  as_appuser() { sudo -u "$APP_USER" bash -lc "export HOME='${APP_HOME}'; $*"; }

  if [ ! -d "$NVM_DIR" ]; then
    echo "[web] installing nvm for ${APP_USER}"
    as_appuser "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash" || true
  fi
  as_appuser "export NVM_DIR='${NVM_DIR}'; source '${NVM_DIR}/nvm.sh' 2>/dev/null || true; nvm install --lts || true; nvm use --lts || true"

  # Optionally relocate project into app user's home (preserve idempotency)
  PROJECT_NAME="$(basename "${PROJECT_ROOT}")"
  if [[ "${PROJECT_ROOT}" != "${APP_HOME}/"* ]]; then
    DEST="${APP_HOME}/${PROJECT_NAME}"
    echo "[web] relocating project to ${DEST}"
    mkdir -p "${DEST}"
    mv "${PROJECT_ROOT}/frontend" "${DEST}/" || true
    mv "${PROJECT_ROOT}/backend" "${DEST}/" || true
    chown -R "${APP_USER}:${APP_USER}" "${DEST}"
    cd "${DEST}" || true
    PROJECT_ROOT="$(pwd)"
  fi

  FRONTEND_DIR="$PROJECT_ROOT/frontend/web-app"
  BACKEND_DIR="$PROJECT_ROOT/backend"
  SQL_FILE="$PROJECT_ROOT/setup.sql"

  # Install frontend deps
  if [ -d "$FRONTEND_DIR" ]; then
    as_appuser "export NVM_DIR='${NVM_DIR}'; source '${NVM_DIR}/nvm.sh' 2>/dev/null || true; cd '${FRONTEND_DIR}'; rm -rf node_modules package-lock.json; npm cache clean --force || true; npm install || true"
    as_appuser "export NVM_DIR='${NVM_DIR}'; source '${NVM_DIR}/nvm.sh' 2>/dev/null || true; cd '${FRONTEND_DIR}'; nohup npm run dev -- --port ${FRONTEND_PORT} --host >> '${FRONTEND_LOG}' 2>&1 &" || true
  fi

  # Install backend deps
  if [ -d "$BACKEND_DIR" ]; then
    as_appuser "cd '${BACKEND_DIR}'; rm -rf .venv; python3 -m venv .venv; source .venv/bin/activate; pip install --upgrade pip; pip install -r requirements.txt || true"
    as_appuser "cd '${BACKEND_DIR}'; source .venv/bin/activate; nohup flask --app src/app run --host=0.0.0.0 --port=${BACKEND_PORT} >> '${BACKEND_LOG}' 2>&1 &" || true
  fi

  touch "$marker"
  echo "[web] done"
}

#############################
# Horizontal setup (from horizontal_setup.sh)
#############################
setup_horizontal() {
  local marker="$MARKER_DIR/horizontal.done"
  if [ -f "$marker" ]; then
    echo "[horizontal] already configured, skipping"
    return
  fi

  echo "[horizontal] configuring attacker/victim users, tmux sharing and disguised PPK"
  LAB_ATK="bestblog"
  LAB_ATK_PASS="best123"
  LAB_VICTIM="alice"
  LAB_VICTIM_PASS="alice123"

  PPK_PLACEMENT_DIR="/tmp/.sys_cache"
  PPK_PLACEMENT_PATH="${PPK_PLACEMENT_DIR}/.thumb"
  HINT_ATK="/home/${LAB_ATK}/.hint_attacker"
  HINT_PPK="${PPK_PLACEMENT_DIR}/.hint_ppk"
  HINT_TMUX="/tmp/.alice_tmux_hint"
  TMUX_SOCKET="/tmp/alice_tmux.sock"
  TMUX_SESSION="shared"
  TMUX_GROUP="alice_tmux"

  # create users if missing
  if ! id "${LAB_VICTIM}" &>/dev/null; then
    useradd -m -s /bin/bash "${LAB_VICTIM}"
    echo "${LAB_VICTIM}:${LAB_VICTIM_PASS}" | chpasswd
  fi
  if ! id "${LAB_ATK}" &>/dev/null; then
    useradd -m -s /bin/bash "${LAB_ATK}"
    echo "${LAB_ATK}:${LAB_ATK_PASS}" | chpasswd
    usermod -aG adm ${LAB_ATK} || true
  fi

  touch /var/log/flaskapp.log || true
  chown root:adm /var/log/flaskapp.log || true
  chmod 640 /var/log/flaskapp.log || true
  echo "$(date --iso-8601=seconds) - LAB_VICTIM=${LAB_VICTIM} LAB_VICTIM_PASS=${LAB_VICTIM_PASS}" | tee -a /var/log/flaskapp.log || true
  chown root:adm /var/log/flaskapp.log || true

  # Victim ssh keys
  VICTIM_KEY_TYPE="ed25519"
  VICTIM_PRIV_KEY="/home/${LAB_VICTIM}/.ssh/id_${VICTIM_KEY_TYPE}"
  sudo -u "${LAB_VICTIM}" mkdir -p /home/"${LAB_VICTIM}"/.ssh
  sudo -u "${LAB_VICTIM}" chmod 700 /home/"${LAB_VICTIM}"/.ssh
  if [ ! -f "${VICTIM_PRIV_KEY}" ]; then
    sudo -u "${LAB_VICTIM}" ssh-keygen -t "${VICTIM_KEY_TYPE}" -f "${VICTIM_PRIV_KEY}" -N "" -C "alice_lab_key" >/dev/null 2>&1 || true
  fi
  if [ -f "${VICTIM_PRIV_KEY}.pub" ]; then
    grep -qxF "$(cat ${VICTIM_PRIV_KEY}.pub)" /home/"${LAB_VICTIM}"/.ssh/authorized_keys 2>/dev/null || \
      cat "${VICTIM_PRIV_KEY}.pub" >> /home/"${LAB_VICTIM}"/.ssh/authorized_keys 2>/dev/null || true
  fi
  chown -R "${LAB_VICTIM}:${LAB_VICTIM}" /home/"${LAB_VICTIM}"/.ssh || true
  chmod 700 /home/"${LAB_VICTIM}"/.ssh || true
  [ -f /home/"${LAB_VICTIM}"/.ssh/authorized_keys ] && chmod 600 /home/"${LAB_VICTIM}"/.ssh/authorized_keys || true

  # Place disguised PPK (if puttygen installed)
  mkdir -p "${PPK_PLACEMENT_DIR}" || true
  chmod 0755 "${PPK_PLACEMENT_DIR}" || true
  if command -v puttygen >/dev/null 2>&1; then
    TMP_COPY="/tmp/alice_priv_tmp"
    cp "${VICTIM_PRIV_KEY}" "${TMP_COPY}" || true
    chmod 600 "${TMP_COPY}" || true
    puttygen "${TMP_COPY}" -O private -o "${PPK_PLACEMENT_DIR}/alice_private.ppk" >/dev/null 2>&1 || true
    rm -f "${TMP_COPY}" || true
    mv "${PPK_PLACEMENT_DIR}/alice_private.ppk" "${PPK_PLACEMENT_PATH}" || true
    chown "${LAB_ATK}:${LAB_ATK}" "${PPK_PLACEMENT_PATH}" || true
    chmod 0644 "${PPK_PLACEMENT_PATH}" || true
    touch -d "30 minutes ago" "${PPK_PLACEMENT_PATH}" 2>/dev/null || true
  else
    echo "[horizontal] puttygen not available; create ${PPK_PLACEMENT_PATH} manually if needed"
  fi

  # SSH config for pubkey
  mkdir -p /etc/ssh/sshd_config.d
  echo "PubkeyAuthentication yes" > /etc/ssh/sshd_config.d/99-lab-pubkey.conf
  systemctl restart ssh || true

  # Hints
  cat > "${HINT_ATK}" <<'MAINHINT'
There are 3 ways to get into alice's account:

1) Disguised private key (details hidden on the host).
2) [To be implemented later].
3) Shared tmux session (details hidden on the host).

Find the hidden notes on the VM to reveal steps for 1 and 3.
MAINHINT
  chown "${LAB_ATK}:${LAB_ATK}" "${HINT_ATK}" || true
  chmod 0640 "${HINT_ATK}" || true

  cat > "${HINT_PPK}" <<'PPK'
Hidden hint (Way 1 — PPK):
- Disguised key: /tmp/.sys_cache/.thumb
- Convert PPK -> OpenSSH and SSH locally:
    puttygen /tmp/.sys_cache/.thumb -O private-openssh -o /tmp/converted_id
    chmod 600 /tmp/converted_id
    ssh -i /tmp/converted_id alice@localhost
PPK
  chown root:root "${HINT_PPK}" || true
  chmod 0640 "${HINT_PPK}" || true

  cat > "${HINT_TMUX}" <<'TMUX'
Hidden hint (Way 3 — tmux):
tmux only allows clients with the same user as the server.
Use the allowed sudo wrapper to run the client as alice:

  sudo -u alice tmux -S /tmp/alice_tmux.sock attach -t shared

If you see "no session", list first:
  sudo -u alice tmux -S /tmp/alice_tmux.sock ls
TMUX
  chown root:root "${HINT_TMUX}" || true
  chmod 0640 "${HINT_TMUX}" || true

  # Shared tmux session and permissions
  groupadd -f "${TMUX_GROUP}" || true
  usermod -a -G "${TMUX_GROUP}" "${LAB_VICTIM}" || true
  usermod -a -G "${TMUX_GROUP}" "${LAB_ATK}" || true
  [ -S "${TMUX_SOCKET}" ] && rm -f "${TMUX_SOCKET}" || true
  sudo -u "${LAB_VICTIM}" tmux -S "${TMUX_SOCKET}" new -d -s "${TMUX_SESSION}" bash -lc "echo '[lab tmux: owned by ${LAB_VICTIM}]'; exec bash" || true
  sudo -u "${LAB_VICTIM}" tmux -S "${TMUX_SOCKET}" server-access -a "${LAB_ATK}" || true
  chown "${LAB_VICTIM}:${TMUX_GROUP}" "${TMUX_SOCKET}" || true
  chmod 0660 "${TMUX_SOCKET}" || true

  touch "$marker"
  echo "[horizontal] done"
}

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
