#!/usr/bin/env bash
# Combined setup for the lab VM. Merges FTP, lab escalation vectors, and deploy steps.
set -euo pipefail

# -------------------- GLOBAL SETTINGS --------------------
export DEBIAN_FRONTEND=noninteractive

# Deployment (webapp) user
DEPLOY_APP_USER="bestblogs"
DEPLOY_APP_HOME="/home/${DEPLOY_APP_USER}"

# FTP-related variables (prefixed FTP_)
FTP_VSFTPD_CONF="/etc/vsftpd.conf"
FTP_ANON_ROOT="/srv/ftp"
FTP_UPLOAD_DIR="${FTP_ANON_ROOT}/upload"
FTP_JOB_FILE="${FTP_UPLOAD_DIR}/job.txt"
FTP_CRON_FILE="/etc/cron.d/lab_run_job_txt"
FTP_JOB_LOG="${FTP_UPLOAD_DIR}/job_log.txt"
FTP_VSFTPD_SERVICE="vsftpd"
FTP_LAB_GROUP="ftpexec"

# Lab escalation variables (prefixed LAB_)
LAB_USER="alice"
LAB_PASS="qwerty2020"
LAB_SUDOERS_FILE="/etc/sudoers.d/lab_alice_nano_npm"
LAB_TMP_PY="/opt/tmp.py"
LAB_CRON_FILE="/etc/cron.d/lab_tmp_py"
LAB_DB_NAME="labdb"
LAB_DB_ROLE="alice"
LAB_DB_PASS="DbalicePass!@#"
LAB_BASHRC="/home/${LAB_USER}/.bashrc"
LAB_ROOT_PLAIN="angelbaby"
LAB_ROOT_BCRYPT='$2a$12$/bsaKryakHSiT9BJyrj0WuMQaegv0AZ7m0WELGxBHUJrTt7a.tFDq'

# Deploy/webapp variables (prefixed DEPLOY_)
DEPLOY_PROJECT_ROOT="$(pwd)"
DEPLOY_FRONTEND_DIR="${DEPLOY_PROJECT_ROOT}/frontend/web-app"
DEPLOY_BACKEND_DIR="${DEPLOY_PROJECT_ROOT}/backend"
DEPLOY_SQL_FILE="${DEPLOY_PROJECT_ROOT}/setup.sql"
DEPLOY_VENV_DIR="${DEPLOY_BACKEND_DIR}/.venv"
DEPLOY_BACKEND_PORT="5000"
DEPLOY_FRONTEND_PORT="5173"
DEPLOY_DB_NAME="bestblogs"
DEPLOY_DB_USER="bestblogs_user"
DEPLOY_DB_PASS="bestblogs_password"
DEPLOY_NVM_DIR="${DEPLOY_APP_HOME}/.nvm"
DEPLOY_FRONTEND_LOG="${DEPLOY_PROJECT_ROOT}/frontend.log"
DEPLOY_BACKEND_LOG="${DEPLOY_PROJECT_ROOT}/backend.log"


as_deploy_user() {
  sudo -u "${DEPLOY_APP_USER}" bash -lc "export HOME='${DEPLOY_APP_HOME}'; $*"
}

# -------------------- Sanity: must be root --------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

echo "[+] Creating deploy user if needed: ${DEPLOY_APP_USER}"
if id -u "${DEPLOY_APP_USER}" >/dev/null 2>&1; then
  echo "==> User ${DEPLOY_APP_USER} already exists."
else
  useradd -m -s /bin/bash "${DEPLOY_APP_USER}"
  usermod -aG adm "${DEPLOY_APP_USER}"
fi

echo "[+] Updating apt and installing base dependencies (combined)"
apt-get update -y
apt-get install -y \
  build-essential python3 python3-venv python3-pip \
  mysql-server curl php php-cli vsftpd cron sudo nano nodejs npm \
  acl postgresql openssl || true

# -------------------- FTP setup --------------------
echo "[+] Setting up FTP anon upload area: ${FTP_UPLOAD_DIR}"
mkdir -p "${FTP_UPLOAD_DIR}"
if ! id ftp &>/dev/null; then
  useradd -r -s /usr/sbin/nologin -d "${FTP_ANON_ROOT}" ftp || true
fi
chown root:root "${FTP_ANON_ROOT}" || true
chmod 755 "${FTP_ANON_ROOT}" || true

if ! getent group "${FTP_LAB_GROUP}" >/dev/null; then
  groupadd "${FTP_LAB_GROUP}"
fi
usermod -aG "${FTP_LAB_GROUP}" ftp || true
usermod -aG "${FTP_LAB_GROUP}" "${DEPLOY_APP_USER}" || true

systemctl restart cron || service cron restart || true

chown root:${FTP_LAB_GROUP} "${FTP_UPLOAD_DIR}" || true
chmod 2775 "${FTP_UPLOAD_DIR}" || true
find "${FTP_UPLOAD_DIR}" -type f -exec chown ftp:${FTP_LAB_GROUP} {} \; || true

echo "[+] Create FTP job file if missing: ${FTP_JOB_FILE}"
if [ ! -s "${FTP_JOB_FILE}" ]; then
  cat > "${FTP_JOB_FILE}" <<'EOF'
#!/usr/bin/env bash
echo "Hello from job.txt at $(date)" >> /srv/ftp/upload/job_log.txt
EOF
fi
chown ftp:${FTP_LAB_GROUP} "${FTP_JOB_FILE}" || true
chmod 754 "${FTP_JOB_FILE}" || true

touch "${FTP_JOB_LOG}" || true
chown root:${FTP_LAB_GROUP} "${FTP_JOB_LOG}" || true
chmod 664 "${FTP_JOB_LOG}" || true

set_or_add_conf() {
  local key="$1"
  local val="$2"
  if grep -q -E "^\s*#?\s*${key}\s*=" "${FTP_VSFTPD_CONF}" 2>/dev/null; then
    sed -ri "s|^\s*#?\s*${key}\s*=.*|${key}=${val}|g" "${FTP_VSFTPD_CONF}"
  else
    echo "${key}=${val}" >> "${FTP_VSFTPD_CONF}"
  fi
}

if [ ! -f "${FTP_VSFTPD_CONF}.origlabbk" ]; then
  cp "${FTP_VSFTPD_CONF}" "${FTP_VSFTPD_CONF}.origlabbk" || true
fi

set_or_add_conf "anonymous_enable" "YES"
set_or_add_conf "anon_upload_enable" "YES"
set_or_add_conf "anon_mkdir_write_enable" "NO"
set_or_add_conf "chroot_local_user" "YES"
set_or_add_conf "write_enable" "YES"
set_or_add_conf "anon_other_write_enable" "YES"
set_or_add_conf "anon_umask" "027"
set_or_add_conf "file_open_mode" "0750"

systemctl restart "${FTP_VSFTPD_SERVICE}" || service "${FTP_VSFTPD_SERVICE}" restart || true
systemctl enable "${FTP_VSFTPD_SERVICE}" || true

echo "[+] Creating cron job to run FTP job every minute: ${FTP_CRON_FILE}"
cat > "${FTP_CRON_FILE}" <<CRON
# Run job.txt every minute (FTP job)
* * * * * ${DEPLOY_APP_USER} /bin/bash "${FTP_JOB_FILE}" >> "${FTP_JOB_LOG}" 2>&1
CRON
chmod 644 "${FTP_CRON_FILE}" || true

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart cron >/dev/null 2>&1 || service cron restart >/dev/null 2>&1 || true

# -------------------- LAB escalation vectors --------------------
echo "[+] Setting up lab user and escalation vectors for ${LAB_USER}"

if ! id "${LAB_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${LAB_USER}"
  echo "${LAB_USER}:${LAB_PASS}" | chpasswd
fi

cat > "${LAB_SUDOERS_FILE}" <<EOF
# lab: allow ${LAB_USER} to run nano and npm as root without password
${LAB_USER} ALL=(ALL) NOPASSWD: /usr/bin/nano, /usr/bin/npm
EOF
chmod 0440 "${LAB_SUDOERS_FILE}"
visudo -cf "${LAB_SUDOERS_FILE}" >/dev/null 2>&1 || { rm -f "${LAB_SUDOERS_FILE}"; echo "invalid sudoers"; }

cat > "${LAB_TMP_PY}" <<'PY'
#!/usr/bin/env python3
from datetime import datetime
try:
    with open('/var/log/tmp_py.log','a') as f:
        f.write(f"/opt/tmp.py executed at: {datetime.utcnow().isoformat()}\n")
except Exception as e:
    with open('/var/log/tmp_py_error.log','a') as efile:
        efile.write(f"Exception: {e}\n")
PY

chown root:root "${LAB_TMP_PY}" || true
chmod 0644 "${LAB_TMP_PY}" || true
setfacl -m u:"${LAB_USER}":rw "${LAB_TMP_PY}" || true

touch /var/log/tmp_py.log /var/log/tmp_py_error.log || true
chown root:root /var/log/tmp_py*.log || true
chmod 0644 /var/log/tmp_py*.log || true

cat > "${LAB_CRON_FILE}" <<CRON
* * * * * root /usr/bin/python3 "${LAB_TMP_PY}"
CRON
chmod 0644 "${LAB_CRON_FILE}" || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart cron >/dev/null 2>&1 || true
else
  service cron restart >/dev/null 2>&1 || true
fi

systemctl enable --now postgresql >/dev/null 2>&1 || true

# Create DB role if not exists (Postgres)
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "\
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='${LAB_DB_ROLE}') THEN CREATE ROLE ${LAB_DB_ROLE} LOGIN PASSWORD '${LAB_DB_PASS}'; END IF; END \$\$;"

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${LAB_DB_NAME}'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${LAB_DB_NAME};"
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${LAB_DB_NAME} TO ${LAB_DB_ROLE};"

sudo -u postgres psql -d "${LAB_DB_NAME}" -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL
);
DELETE FROM users WHERE username = 'root';
INSERT INTO users (username, password_hash) VALUES ('root', '${LAB_ROOT_BCRYPT}');
SQL

sudo -u postgres psql -d "${LAB_DB_NAME}" -c "GRANT SELECT ON TABLE users TO ${LAB_DB_ROLE};" >/dev/null 2>&1 || true

export_block="# BEGIN LAB DB ENV\nexport LAB_DB_NAME='${LAB_DB_NAME}'\nexport LAB_DB_USER='${LAB_DB_ROLE}'\nexport LAB_DB_PASS='${LAB_DB_PASS}'\n# END LAB DB ENV\n"
touch "${LAB_BASHRC}"
chown "${LAB_USER}:${LAB_USER}" "${LAB_BASHRC}" || true
chmod 0644 "${LAB_BASHRC}" || true
if ! grep -q "BEGIN LAB DB ENV" "${LAB_BASHRC}"; then
  printf "\n%s\n" "${export_block}" >> "${LAB_BASHRC}"
  chown "${LAB_USER}:${LAB_USER}" "${LAB_BASHRC}"
fi

# Enable root SSH login with password
SSH_MAIN="/etc/ssh/sshd_config"
if grep -q "^PermitRootLogin" "${SSH_MAIN}"; then
  sed -i.bak 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "${SSH_MAIN}" || true
else
  echo "PermitRootLogin yes" >> "${SSH_MAIN}" || true
fi
if grep -q "^PasswordAuthentication" "${SSH_MAIN}"; then
  sed -i.bak 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "${SSH_MAIN}" || true
else
  echo "PasswordAuthentication yes" >> "${SSH_MAIN}" || true
fi

mkdir -p /etc/ssh/sshd_config.d || true
echo "PermitRootLogin yes" > /etc/ssh/sshd_config.d/99-rootlogin.conf || true
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config.d/99-rootlogin.conf || true
systemctl restart ssh || true

# Hidden hints
HINT1_PATH="/home/${LAB_USER}/.hint1"
HINT2_PATH="/home/${LAB_USER}/.hint2"
cat > "${HINT1_PATH}" <<'H1'
There are 4 ways to do vertical privilege escalation in total on this machine.
All the answers can be found by scanning the machine with linpeas.sh and looking for abnormal configuration/files.
H1
cat > "${HINT2_PATH}" <<'H2'
Try harder before reading this hint.

1st and 2nd: Pretty obvious if you just run sudo -l.
3rd vector: The file you are looking for is located under /opt.
4th vector: Inspect environment variables for secrets or credentials.
H2
chown "${LAB_USER}:${LAB_USER}" "${HINT1_PATH}" "${HINT2_PATH}" || true
chmod 0640 "${HINT1_PATH}" "${HINT2_PATH}" || true

# Root flag
ROOT_FLAG="/root/root.txt"
cat > "${ROOT_FLAG}" <<'FLAG'
Congratulations! 

You’ve successfully escalated privileges to root.

Well done — mission accomplished.
FLAG
chown root:root "${ROOT_FLAG}" || true
chmod 0400 "${ROOT_FLAG}" || true

echo "[+] Lab setup (FTP + escalation vectors) complete."

# -------------------- Deploy / Webapp setup --------------------
echo "[+] Configuring MySQL (database + user + import) for deploy app"
systemctl enable --now mysql || true
mysql --protocol=socket <<SQL
CREATE DATABASE IF NOT EXISTS \
  \\`${DEPLOY_DB_NAME}\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DEPLOY_DB_USER}'@'localhost' IDENTIFIED BY '${DEPLOY_DB_PASS}';
GRANT ALL PRIVILEGES ON \\`${DEPLOY_DB_NAME}\\`.* TO '${DEPLOY_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

if [ -f "${DEPLOY_SQL_FILE}" ]; then
  mysql --protocol=socket "${DEPLOY_DB_NAME}" < "${DEPLOY_SQL_FILE}" || true
fi

chown -R "${DEPLOY_APP_USER}:${DEPLOY_APP_USER}" "${DEPLOY_PROJECT_ROOT}" || true

echo "[+] Installing Node.js LTS (via nvm) for ${DEPLOY_APP_USER}"
if [ ! -d "${DEPLOY_NVM_DIR}" ]; then
  as_deploy_user "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash" || true
fi
as_deploy_user "export NVM_DIR='${DEPLOY_NVM_DIR}'; source '${DEPLOY_NVM_DIR}/nvm.sh'; nvm install --lts; nvm use --lts; node -v; npm -v" || true

# Relocate project into deploy user home if not already there
PROJECT_NAME="$(basename "${DEPLOY_PROJECT_ROOT}")"
if [[ "${DEPLOY_PROJECT_ROOT}" != "${DEPLOY_APP_HOME}/"* ]]; then
  DEST="${DEPLOY_APP_HOME}/${PROJECT_NAME}"
  mkdir -p "${DEST}"
  mv "${DEPLOY_PROJECT_ROOT}/frontend" "${DEST}/" || true
  mv "${DEPLOY_PROJECT_ROOT}/backend" "${DEST}/" || true
  chown -R "${DEPLOY_APP_USER}:${DEPLOY_APP_USER}" "${DEST}" || true
  cd "${DEST}" || true
fi

# Recompute deploy paths
DEPLOY_PROJECT_ROOT="$(pwd)"
DEPLOY_FRONTEND_DIR="${DEPLOY_PROJECT_ROOT}/frontend/web-app"
DEPLOY_BACKEND_DIR="${DEPLOY_PROJECT_ROOT}/backend"
DEPLOY_SQL_FILE="${DEPLOY_PROJECT_ROOT}/setup.sql"
DEPLOY_VENV_DIR="${DEPLOY_BACKEND_DIR}/.venv"
DEPLOY_FRONTEND_LOG="${DEPLOY_PROJECT_ROOT}/frontend.log"
DEPLOY_BACKEND_LOG="${DEPLOY_PROJECT_ROOT}/backend.log"

echo "[+] Installing frontend dependencies as ${DEPLOY_APP_USER}"
as_deploy_user "export NVM_DIR='${DEPLOY_NVM_DIR}'; source '${DEPLOY_NVM_DIR}/nvm.sh'; nvm use --lts >/dev/null; cd '${DEPLOY_FRONTEND_DIR}'; rm -rf node_modules package-lock.json; npm cache clean --force; npm install" || true

echo "[+] Installing backend dependencies as ${DEPLOY_APP_USER}"
as_deploy_user "cd '${DEPLOY_BACKEND_DIR}'; rm -rf .venv; python3 -m venv .venv; source .venv/bin/activate; pip install --upgrade pip; pip install -r requirements.txt" || true

echo "[+] Starting frontend on: ${DEPLOY_FRONTEND_PORT} as ${DEPLOY_APP_USER}"
as_deploy_user "export NVM_DIR='${DEPLOY_NVM_DIR}'; source '${DEPLOY_NVM_DIR}/nvm.sh'; nvm use --lts >/dev/null; cd '${DEPLOY_FRONTEND_DIR}'; nohup npm run dev -- --port ${DEPLOY_FRONTEND_PORT} --host >> '${DEPLOY_FRONTEND_LOG}' 2>&1 & disown" || true

echo "[+] Starting backend on: ${DEPLOY_BACKEND_PORT} as ${DEPLOY_APP_USER}"
as_deploy_user "cd '${DEPLOY_BACKEND_DIR}'; source .venv/bin/activate; nohup flask --app src/app run --host=0.0.0.0 --port=${DEPLOY_BACKEND_PORT} >> '${DEPLOY_BACKEND_LOG}' 2>&1 & disown" || true

echo "[+] Full setup complete. Check logs: ${DEPLOY_FRONTEND_LOG}, ${DEPLOY_BACKEND_LOG}"
