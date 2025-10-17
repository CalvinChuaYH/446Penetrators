#!/usr/bin/env bash
# Combined lab setup (horizontal + vertical + webapp/ftp)
# Usage: sudo ./combined_lab_setup.sh
set -euo pipefail

# --------------------
# Common config
# --------------------
export DEBIAN_FRONTEND=noninteractive

# --- Users & passwords (keep original values from provided scripts) ---
LAB_ATK="bestblog"
LAB_ATK_PASS="best123"

LAB_ATK2="bestblogs"    # from webapp script (app user)
LAB_ATK2_PASS="bestblogs" # not used, but user will be created idempotently

LAB_VICTIM="alice"
LAB_VICTIM_PASS="alice123"   # script 1
# script 2 uses different alice password; keep alice123 to match first script

# vertical script 2 also declared:
LAB_USER="${LAB_VICTIM}"
LAB_PASS="qwerty2020"  # not applied to avoid overriding LAB_VICTIM_PASS repeatedly

# sudoers files
SUDOERS_FILE="/etc/sudoers.d/lab_alice_nano_npm"
SUDOERS_FILE_TMUX="/etc/sudoers.d/lab_tmux_wrapper"  # reserved if needed

# tmux and ppk placement
PPK_PLACEMENT_DIR="/tmp/.sys_cache"
PPK_PLACEMENT_PATH="${PPK_PLACEMENT_DIR}/.thumb"

HINT_ATK="/home/${LAB_ATK}/.hint_attacker"
HINT_PPK="${PPK_PLACEMENT_DIR}/.hint_ppk"
HINT_TMUX="/tmp/.alice_tmux_hint"

TMUX_SOCKET="/tmp/alice_tmux.sock"
TMUX_SESSION="shared"
TMUX_GROUP="alice_tmux"

# tmp.py and cron settings (vertical)
TMP_PY="/opt/tmp.py"
CRON_TMP_FILE="/etc/cron.d/lab_tmp_py"

# PostgreSQL DB (vertical)
DB_NAME="labdb"
DB_ROLE="alice"
DB_PASS="DbalicePass!@#"
ROOT_PLAIN="angelbaby"
ROOT_BCRYPT='$2a$12$/bsaKryakHSiT9BJyrj0WuMQaegv0AZ7m0WELGxBHUJrTt7a.tFDq'
ALICE_BASHRC="/home/${LAB_VICTIM}/.bashrc"
ROOT_FLAG="/root/root.txt"

# Web app / FTP settings (webapp)
APP_USER="${LAB_ATK2}"
APP_HOME="/home/${APP_USER}"
PROJECT_ROOT="$(pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend/web-app"
BACKEND_DIR="$PROJECT_ROOT/backend"
SQL_FILE="$PROJECT_ROOT/setup.sql"
VENV_DIR="$BACKEND_DIR/.venv"

BACKEND_PORT="5000"
FRONTEND_PORT="5173"

DB_NAME_WEB="bestblogs"
DB_USER_WEB="bestblogs_user"
DB_PASS_WEB="bestblogs_password"

NVM_DIR="$APP_HOME/.nvm"
FRONTEND_LOG="$PROJECT_ROOT/frontend.log"
BACKEND_LOG="$PROJECT_ROOT/backend.log"

# FTP
VSFTPD_CONF="/etc/vsftpd.conf"
ANON_ROOT="/srv/ftp"
UPLOAD_DIR="${ANON_ROOT}/upload"
JOB_FILE="${UPLOAD_DIR}/job.txt"
CRON_JOB_FILE="/etc/cron.d/lab_run_job_txt"
JOB_LOG="${UPLOAD_DIR}/job_log.txt"
VSFTPD_SERVICE="vsftpd"
LAB_GROUP="ftpexec"

# misc
AUDIT_PUTTY_KEY="puttygen_exec"
AUDIT_HOME_KEY="home_write"
FIND_PPK_HELPER="/usr/local/bin/find_ppk"

echo "[*] Starting combined lab setup..."

# --------------------
# Packages (union of all scripts)
# --------------------
apt-get update -y
apt-get install -y \
  openssh-server putty-tools auditd aide vim less curl tmux sudo nano nodejs npm cron acl postgresql openssl \
  build-essential python3 python3-venv python3-pip mysql-server php php-cli vsftpd

# Ensure services enabled where needed
systemctl enable --now ssh >/dev/null 2>&1 || true
systemctl enable --now auditd >/dev/null 2>&1 || true
systemctl enable --now postgresql >/dev/null 2>&1 || true
systemctl enable --now cron >/dev/null 2>&1 || true
systemctl enable --now mysql >/dev/null 2>&1 || true

# --------------------
# Create users (idempotent)
# alice (victim)
# bestblog (attacker from script 1)
# bestblogs (app user from script 3)
# --------------------
if ! id "${LAB_VICTIM}" &>/dev/null; then
  useradd -m -s /bin/bash "${LAB_VICTIM}"
  echo "${LAB_VICTIM}:${LAB_VICTIM_PASS}" | chpasswd
fi

if ! id "${LAB_ATK}" &>/dev/null; then
  useradd -m -s /bin/bash "${LAB_ATK}"
  echo "${LAB_ATK}:${LAB_ATK_PASS}" | chpasswd
  usermod -aG adm "${LAB_ATK}" || true
fi

if ! id "${APP_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${APP_USER}"
  # do not overwrite password if not set; set a default just in case
  echo "${APP_USER}:${LAB_ATK2_PASS}" | chpasswd || true
  usermod -aG adm "${APP_USER}" || true
fi

# --------------------
# Log file for demo (from script 1)
# --------------------
touch /var/log/flaskapp.log
chown root:adm /var/log/flaskapp.log || true
chmod 640 /var/log/flaskapp.log || true

echo "2025-10-14 10:00:00 - LAB_VICTIM=${LAB_VICTIM} LAB_VICTIM_PASS=${LAB_VICTIM_PASS}" | tee -a /var/log/flaskapp.log
chown root:adm /var/log/flaskapp.log || true

# --------------------
# Victim SSH keys & authorized_keys (script 1)
# --------------------
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

# --------------------
# Place disguised PPK (script 1)
# --------------------
mkdir -p "${PPK_PLACEMENT_DIR}"
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
else
  echo "WARNING: puttygen missing; you can manually place a .ppk at ${PPK_PLACEMENT_PATH}"
fi

if [ -f "${PPK_PLACEMENT_PATH}" ]; then
  touch --date="30 minutes ago" "${PPK_PLACEMENT_PATH}" || true
fi

# Ensure sshd allows pubkey auth
mkdir -p /etc/ssh/sshd_config.d
echo "PubkeyAuthentication yes" > /etc/ssh/sshd_config.d/99-lab-pubkey.conf
systemctl restart ssh || true

# --------------------
# Hints: visible + hidden (script 1)
# --------------------
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
chown root:root "${HINT_PPK}" && chmod 0640 "${HINT_PPK}" || true

cat > "${HINT_TMUX}" <<'TMUX'
Hidden hint (Way 3 — tmux):
tmux only allows clients with the same user as the server.
Use the allowed sudo wrapper to run the client as alice:

  sudo -u alice tmux -S /tmp/alice_tmux.sock attach -t shared

If you see "no session", list first:
  sudo -u alice tmux -S /tmp/alice_tmux.sock ls
TMUX
chown root:root "${HINT_TMUX}" && chmod 0640 "${HINT_TMUX}" || true

# --------------------
# Shared tmux session & group (script 1)
# --------------------
groupadd -f "${TMUX_GROUP}" || true
usermod -a -G "${TMUX_GROUP}" "${LAB_VICTIM}" || true
usermod -a -G "${TMUX_GROUP}" "${LAB_ATK}" || true

[ -S "${TMUX_SOCKET}" ] && rm -f "${TMUX_SOCKET}" || true
sudo -u "${LAB_VICTIM}" tmux -S "${TMUX_SOCKET}" new -d -s "${TMUX_SESSION}" bash -lc "echo '[lab tmux: owned by ${LAB_VICTIM}]'; exec bash" || true

if [ ! -S "${TMUX_SOCKET}" ]; then
  echo "ERROR: socket ${TMUX_SOCKET} missing after tmux server creation."
fi

# allow attacker access
sudo -u "${LAB_VICTIM}" tmux -S "${TMUX_SOCKET}" server-access -a "${LAB_ATK}" || true
chown "${LAB_VICTIM}:${TMUX_GROUP}" "${TMUX_SOCKET}" || true
chmod 0660 "${TMUX_SOCKET}" || true

echo "[*] tmux server ready as ${LAB_VICTIM}."
echo "    Trainee command (Way 3): sudo -u ${LAB_VICTIM} tmux -S ${TMUX_SOCKET} attach -t ${TMUX_SESSION}"

# --------------------
# Sudoers: allow alice to run nano & npm without password (script 2)
# --------------------
cat > "$SUDOERS_FILE" <<EOF
# lab: allow ${LAB_VICTIM} to run nano and npm as root without password
${LAB_VICTIM} ALL=(ALL) NOPASSWD: /usr/bin/nano, /usr/bin/npm
EOF
chmod 0440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1 || { rm -f "$SUDOERS_FILE"; echo "invalid sudoers"; exit 1; }

# --------------------
# /opt/tmp.py & cron (script 2)
# --------------------
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

chown root:root "$TMP_PY"
chmod 0644 "$TMP_PY"
setfacl -m u:"${LAB_VICTIM}":rw "$TMP_PY" || true

touch /var/log/tmp_py.log /var/log/tmp_py_error.log
chown root:root /var/log/tmp_py*.log || true
chmod 0644 /var/log/tmp_py*.log || true

cat > "$CRON_TMP_FILE" <<CRON
* * * * * root /usr/bin/python3 /opt/tmp.py
CRON
chmod 0644 "$CRON_TMP_FILE"

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart cron >/dev/null 2>&1 || true
else
  service cron restart >/dev/null 2>&1 || true
fi

# --------------------
# PostgreSQL setup (script 2)
# --------------------
systemctl enable --now postgresql >/dev/null 2>&1 || true

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "\
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='${DB_ROLE}') THEN CREATE ROLE ${DB_ROLE} LOGIN PASSWORD '${DB_PASS}'; END IF; END \$\$;" || true

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${DB_NAME};" || true
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_ROLE};" || true

sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<SQL || true
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL
);
DELETE FROM users WHERE username = 'root';
INSERT INTO users (username, password_hash) VALUES ('root', '${ROOT_BCRYPT}');
SQL

sudo -u postgres psql -d "${DB_NAME}" -c "GRANT SELECT ON TABLE users TO ${DB_ROLE};" >/dev/null 2>&1 || true

# Export DB creds into alice's .bashrc (if not already present)
export_block="# BEGIN LAB DB ENV
export LAB_DB_NAME='${DB_NAME}'
export LAB_DB_USER='${DB_ROLE}'
export LAB_DB_PASS='${DB_PASS}'
# END LAB DB ENV
"
touch "${ALICE_BASHRC}"
chown "${LAB_VICTIM}:${LAB_VICTIM}" "${ALICE_BASHRC}" || true
chmod 0644 "${ALICE_BASHRC}" || true
if ! grep -q "BEGIN LAB DB ENV" "${ALICE_BASHRC}" 2>/dev/null; then
  printf "\n%s\n" "${export_block}" >> "${ALICE_BASHRC}"
  chown "${LAB_VICTIM}:${LAB_VICTIM}" "${ALICE_BASHRC}" || true
fi

# --------------------
# Permit root SSH login with password (script 2)
# --------------------
SSH_MAIN="/etc/ssh/sshd_config"
if grep -q "^PermitRootLogin" "$SSH_MAIN" >/dev/null 2>&1; then
  sed -i.bak 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$SSH_MAIN" || true
else
  echo "PermitRootLogin yes" >> "$SSH_MAIN"
fi
if grep -q "^PasswordAuthentication" "$SSH_MAIN" >/dev/null 2>&1; then
  sed -i.bak 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_MAIN" || true
else
  echo "PasswordAuthentication yes" >> "$SSH_MAIN"
fi

mkdir -p /etc/ssh/sshd_config.d
echo "PermitRootLogin yes" > /etc/ssh/sshd_config.d/99-rootlogin.conf
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config.d/99-rootlogin.conf
systemctl restart ssh || true

# --------------------
# Hidden hints in alice's home (script 2)
# --------------------
HINT1_PATH="/home/${LAB_VICTIM}/.hint1"
HINT2_PATH="/home/${LAB_VICTIM}/.hint2"

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

chown "${LAB_VICTIM}:${LAB_VICTIM}" "$HINT1_PATH" "$HINT2_PATH" || true
chmod 0640 "$HINT1_PATH" "$HINT2_PATH" || true

# --------------------
# Root flag (script 2)
# --------------------
cat > "$ROOT_FLAG" <<'FLAG'
Congratulations! 

You’ve successfully escalated privileges to root.

Well done — mission accomplished.
FLAG

chown root:root "$ROOT_FLAG"
chmod 0400 "$ROOT_FLAG"

# --------------------
# Root system password (script 2)
# --------------------
echo "root:${ROOT_PLAIN}" | chpasswd || true
passwd -u root 2>/dev/null || true

# --------------------
# FTP + job.txt cron + shared group (script 3)
# --------------------
echo "[*] Creating anon root and upload dir..."
mkdir -p "${UPLOAD_DIR}"

if ! id ftp &>/dev/null; then
  useradd -r -s /usr/sbin/nologin -d "${ANON_ROOT}" ftp || true
fi

echo "[*] Fix ownership for chroot safety..."
chown root:root "${ANON_ROOT}" || true
chmod 755 "${ANON_ROOT}" || true

echo "[*] Setting up shared group..."
if ! getent group "${LAB_GROUP}" >/dev/null; then
  groupadd "${LAB_GROUP}" || true
fi

usermod -aG "${LAB_GROUP}" ftp || true
usermod -aG "${LAB_GROUP}" "${APP_USER}" || true

systemctl restart cron || service cron restart || true

chown root:${LAB_GROUP} "${UPLOAD_DIR}" || true
chmod 2775 "${UPLOAD_DIR}" || true

find "${UPLOAD_DIR}" -type f -exec chown ftp:${LAB_GROUP} {} \; || true

echo "[*] Create job.txt if missing..."
if [ ! -s "${JOB_FILE}" ]; then
  cat > "${JOB_FILE}" <<'EOF'
#!/usr/bin/env bash
echo "Hello from job.txt at $(date)" >> /srv/ftp/upload/job_log.txt
EOF
fi

chown ftp:${LAB_GROUP} "${JOB_FILE}" || true
chmod 754 "${JOB_FILE}" || true

echo "[*] Ensure job log exists..."
touch "${JOB_LOG}" || true
chown root:${LAB_GROUP} "${JOB_LOG}" || true
chmod 664 "${JOB_LOG}" || true

# vsftpd config helper
set_or_add_conf() {
  local key="$1"
  local val="$2"
  if grep -q -E "^\s*#?\s*${key}\s*=" "${VSFTPD_CONF}" 2>/dev/null; then
    sed -ri "s|^\s*#?\s*${key}\s*=.*|${key}=${val}|g" "${VSFTPD_CONF}"
  else
    echo "${key}=${val}" >> "${VSFTPD_CONF}"
  fi
}

echo "[*] Backing up vsftpd config..."
if [ -f "${VSFTPD_CONF}" ] && [ ! -f "${VSFTPD_CONF}.origlabbk" ]; then
  cp "${VSFTPD_CONF}" "${VSFTPD_CONF}.origlabbk" || true
fi

echo "[*] Writing vsftpd settings..."
set_or_add_conf "anonymous_enable" "YES"
set_or_add_conf "anon_upload_enable" "YES"
set_or_add_conf "anon_mkdir_write_enable" "NO"
set_or_add_conf "chroot_local_user" "YES"
set_or_add_conf "write_enable" "YES"
set_or_add_conf "anon_other_write_enable" "YES"
set_or_add_conf "anon_umask" "027"
set_or_add_conf "file_open_mode" "0750"

echo "[*] Restarting vsftpd..."
systemctl restart "${VSFTPD_SERVICE}" || service "${VSFTPD_SERVICE}" restart || true
systemctl enable "${VSFTPD_SERVICE}" || true

echo "[*] Creating cron job to run job.txt every minute..."
cat > "${CRON_JOB_FILE}" <<CRON
# Run job.txt every minute
* * * * * ${APP_USER} /bin/bash "${JOB_FILE}" >> "${JOB_LOG}" 2>&1
CRON
chmod 644 "${CRON_JOB_FILE}" || true

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart cron >/dev/null 2>&1 || service cron restart >/dev/null 2>&1 || true

# --------------------
# MySQL (web) config + import SQL (script 3)
# --------------------
echo "==> Configuring MySQL (database + user + import)..."
systemctl enable --now mysql || true

# create DB and user (if mysql available)
if command -v mysql >/dev/null 2>&1; then
  sudo mysql --protocol=socket <<SQL || true
CREATE DATABASE IF NOT EXISTS \`${DB_NAME_WEB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER_WEB}'@'localhost' IDENTIFIED BY '${DB_PASS_WEB}';
GRANT ALL PRIVILEGES ON \`${DB_NAME_WEB}\`.* TO '${DB_USER_WEB}'@'localhost';
FLUSH PRIVILEGES;
SQL

  if [ -f "${SQL_FILE}" ]; then
    sudo mysql --protocol=socket "${DB_NAME_WEB}" < "${SQL_FILE}" || true
  else
    echo "Note: ${SQL_FILE} not found; skipping import."
  fi
else
  echo "mysql client not found; skipping MySQL setup."
fi

# --------------------
# Relocate project into app home & prepare environment (script 3)
# --------------------
as_appuser() {
  sudo -u "$APP_USER" bash -lc "export HOME='$APP_HOME'; $*"
}

echo "Creating app user home if missing"
mkdir -p "${APP_HOME}" || true
chown "${APP_USER}:${APP_USER}" "${APP_HOME}" || true

PROJECT_NAME="$(basename "$PROJECT_ROOT")"
if [[ "$PROJECT_ROOT" != "$APP_HOME/"* ]]; then
  DEST="$APP_HOME/$PROJECT_NAME"
  echo "==> Relocating project to $DEST ..."
  mkdir -p "$DEST" || true
  # Try moving frontend/backend if they exist; if not, continue
  [ -d "$PROJECT_ROOT/frontend" ] && mv "$PROJECT_ROOT/frontend" "$DEST/" || true
  [ -d "$PROJECT_ROOT/backend" ] && mv "$PROJECT_ROOT/backend" "$DEST/" || true
  chown -R "$APP_USER:$APP_USER" "$DEST" || true
  cd "$DEST" || true
fi

# recompute paths
PROJECT_ROOT="$(pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend/web-app"
BACKEND_DIR="$PROJECT_ROOT/backend"
SQL_FILE="$PROJECT_ROOT/setup.sql"
VENV_DIR="$BACKEND_DIR/.venv"
FRONTEND_LOG="$PROJECT_ROOT/frontend.log"
BACKEND_LOG="$PROJECT_ROOT/backend.log"

# Node / NVM install & frontend deps (as app user)
if [ -d "$FRONTEND_DIR" ]; then
  echo "==> Installing Node.js LTS (via nvm) and frontend deps..."
  if [[ ! -d "$NVM_DIR" ]]; then
    as_appuser "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash" || true
  fi
  as_appuser "export NVM_DIR='$NVM_DIR'; source '$NVM_DIR/nvm.sh' >/dev/null 2>&1 || true; nvm install --lts || true; nvm use --lts || true; \
    cd '$FRONTEND_DIR' && rm -rf node_modules package-lock.json || true; npm cache clean --force || true; npm install || true" || true
else
  echo "No frontend directory at ${FRONTEND_DIR}, skipping frontend install."
fi

# Backend deps (Python venv)
if [ -d "$BACKEND_DIR" ]; then
  echo "==> Installing backend dependencies"
  as_appuser "cd '$BACKEND_DIR'; python3 -m venv .venv || true; source .venv/bin/activate || true; pip install --upgrade pip || true; \
    [ -f requirements.txt ] && pip install -r requirements.txt || true" || true
else
  echo "No backend directory at ${BACKEND_DIR}, skipping backend install."
fi

# Start frontend & backend (non-blocking)
if [ -d "$FRONTEND_DIR" ]; then
  echo "Starting frontend on: $FRONTEND_PORT as $APP_USER"
  as_appuser "
    export NVM_DIR='$NVM_DIR'; source '$NVM_DIR/nvm.sh' >/dev/null 2>&1 || true;
    cd '$FRONTEND_DIR';
    nohup npm run dev -- --port $FRONTEND_PORT --host >> '$FRONTEND_LOG' 2>&1 &
    disown
  " || true
fi

if [ -d "$BACKEND_DIR" ]; then
  echo "Starting backend on: $BACKEND_PORT as $APP_USER"
  as_appuser "
    cd '$BACKEND_DIR';
    source .venv/bin/activate || true;
    nohup flask --app src/app run --host=0.0.0.0 --port=$BACKEND_PORT >> '$BACKEND_LOG' 2>&1 &
    disown
  " || true
fi

# --------------------
# Final sanity checks & summary
# --------------------
echo "[*] Combined setup complete."
echo " - Disguised PPK: ${PPK_PLACEMENT_PATH} (if generated)"
echo " - Visible hint (attacker): ${HINT_ATK}"
echo " - Hidden PPK hint: ${HINT_PPK}"
echo " - Hidden tmux hint: ${HINT_TMUX}"
echo " - tmux socket: ${TMUX_SOCKET} (owner should be ${LAB_VICTIM})"
echo " - alice tmp.py cron: ${CRON_TMP_FILE}"
echo " - job.txt cron: ${CRON_JOB_FILE}"
echo " - MySQL DB: ${DB_NAME_WEB} (user: ${DB_USER_WEB})"
echo " - PostgreSQL DB: ${DB_NAME} (role: ${DB_ROLE})"
echo " - root flag: ${ROOT_FLAG}"
echo " - sudoers: ${SUDOERS_FILE}"

# quick ls checks (best-effort)
ls -l "${PPK_PLACEMENT_PATH}" 2>/dev/null || true
ls -l "${HINT_ATK}" 2>/dev/null || true
ls -l "${HINT_PPK}" 2>/dev/null || true
ls -l "${HINT_TMUX}" 2>/dev/null || true
ls -l "${TMUX_SOCKET}" 2>/dev/null || true
getent group "${TMUX_GROUP}" || true

exit 0
