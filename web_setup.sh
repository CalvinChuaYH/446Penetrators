#!/usr/bin/env bash
set -euo pipefail

#####################################
#           CONFIGURATION           #
#####################################
APP_USER="bestblogs"
APP_HOME="/home/$APP_USER"

PROJECT_ROOT="$(pwd)"                    
FRONTEND_DIR="$PROJECT_ROOT/frontend/web-app"
BACKEND_DIR="$PROJECT_ROOT/backend"
SQL_FILE="$PROJECT_ROOT/setup.sql"   
VENV_DIR="$PROJECT_ROOT/backend/.venv"

BACKEND_PORT="5000"
FRONTEND_PORT="5173"

DB_NAME="bestblogs"
DB_USER="bestblogs_user"
DB_PASS="bestblogs_password"

NVM_DIR="$APP_HOME/.nvm"
FRONTEND_LOG="$PROJECT_ROOT/frontend.log"
BACKEND_LOG="$PROJECT_ROOT/backend.log"

# FTP
VSFTPD_CONF="/etc/vsftpd.conf"
ANON_ROOT="/srv/ftp"
UPLOAD_DIR="${ANON_ROOT}/upload"
JOB_FILE="${UPLOAD_DIR}/job.txt"
CRON_FILE="/etc/cron.d/lab_run_job_txt"
JOB_LOG="${UPLOAD_DIR}/job_log.txt"
VSFTPD_SERVICE="vsftpd"
LAB_GROUP="ftpexec"

as_appuser() {
  sudo -u "$APP_USER" bash -lc "export HOME='$APP_HOME'; $*"
}

echo "Creating app user if needed"
if id -u "${APP_USER}" >/dev/null 2>&1; then
    echo "==> User ${APP_USER} already exists."
else
    echo "==> Creating user ${APP_USER}..."
    sudo useradd -m -s /bin/bash "${APP_USER}"
    #add bestblogs to the adm group
    usermod -aG adm ${APP_USER} 
fi

echo "==> Updating apt and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y build-essential python3 python3-venv python3-pip mysql-server curl php php-cli vsftpd cron

#####################################
#             FTP                   #
#####################################
echo "[*] Creating anon root and upload dir..."
mkdir -p "${UPLOAD_DIR}"

if ! id ftp &>/dev/null; then
  useradd -r -s /usr/sbin/nologin -d "${ANON_ROOT}" ftp || true
fi

echo "[*] Fix ownership for chroot safety..."
chown root:root "${ANON_ROOT}"
chmod 755 "${ANON_ROOT}"

# === Shared group setup for controlled execution ===
echo "[*] Setting up shared group..."
if ! getent group "${LAB_GROUP}" >/dev/null; then
  groupadd "${LAB_GROUP}"
fi

usermod -aG "${LAB_GROUP}" ftp
usermod -aG "${LAB_GROUP}" "${APP_USER}"

systemctl restart cron || service cron restart

# Make upload dir owned by root:labshare, with SGID bit
chown root:${LAB_GROUP} "${UPLOAD_DIR}"
chmod 2775 "${UPLOAD_DIR}"

# Ensure existing job files inherit group
find "${UPLOAD_DIR}" -type f -exec chown ftp:${LAB_GROUP} {} \;

echo "[*] Create job.txt if missing..."
if [ ! -s "${JOB_FILE}" ]; then
  cat > "${JOB_FILE}" <<'EOF'
#!/usr/bin/env bash
echo "Hello from job.txt at $(date)" >> /srv/ftp/upload/job_log.txt
EOF
fi

chown ftp:${LAB_GROUP} "${JOB_FILE}"
chmod 754 "${JOB_FILE}"  # owner rwx, group r-x, others none

echo "[*] Ensure job log exists..."
touch "${JOB_LOG}"
chown root:ftpexec "${JOB_LOG}"
chmod 664 "${JOB_LOG}"  # owner + group can write

# Helper to set or add vsftpd config keys
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
if [ ! -f "${VSFTPD_CONF}.origlabbk" ]; then
  cp "${VSFTPD_CONF}" "${VSFTPD_CONF}.origlabbk"
fi

echo "[*] Writing vsftpd settings..."
set_or_add_conf "anonymous_enable" "YES"
# set_or_add_conf "anon_root" "${ANON_ROOT}"
set_or_add_conf "anon_upload_enable" "YES"
set_or_add_conf "anon_mkdir_write_enable" "NO"
set_or_add_conf "chroot_local_user" "YES"
# set_or_add_conf "allow_writeable_chroot" "YES"
set_or_add_conf "write_enable" "YES"
set_or_add_conf "anon_other_write_enable" "YES"
# set_or_add_conf "dirlist_enable" "YES"
set_or_add_conf "anon_umask" "027"
set_or_add_conf "file_open_mode" "0750"

echo "[*] Restarting vsftpd..."
systemctl restart "${VSFTPD_SERVICE}" || service "${VSFTPD_SERVICE}" restart
systemctl enable "${VSFTPD_SERVICE}"

echo "[*] Creating cron job to run job.txt every minute..."
cat > "${CRON_FILE}" <<CRON
# Run job.txt every minute
* * * * * bestblogs /bin/bash "${JOB_FILE}" >> "${JOB_LOG}" 2>&1
CRON
chmod 644 "${CRON_FILE}"

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart cron >/dev/null 2>&1 || service cron restart >/dev/null 2>&1 || true

#####################################
#               WEB APP             #
#####################################
echo "==> Configuring MySQL (database + user + import)..."
sudo systemctl enable --now mysql
sudo mysql --protocol=socket <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> Running setup SQL file..."
sudo mysql --protocol=socket "$DB_NAME" < "$SQL_FILE"

echo "==> Setting permissions for $APP_USER..."
sudo chown -R "${APP_USER}:${APP_USER}" "${PROJECT_ROOT}"


echo "==> Installing Node.js LTS (for Vite/React)..."
if [[ ! -d "$NVM_DIR" ]]; then
  as_appuser "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
fi
as_appuser "export NVM_DIR='$NVM_DIR'; source '$NVM_DIR/nvm.sh'; nvm install --lts; nvm use --lts; node -v; npm -v"

# Relocate the project into /home/bestblogs if not already there
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
if [[ "$PROJECT_ROOT" != "$APP_HOME/"* ]]; then
  DEST="$APP_HOME/$PROJECT_NAME" #/home/bestblogs/446Penetrators
  echo "==> Relocating project to $DEST ..."
  mkdir -p "$DEST" #/home/bestblogs
  mv "$PROJECT_ROOT/frontend" "$DEST/"
  mv "$PROJECT_ROOT/backend" "$DEST/"
  chown -R "$APP_USER:$APP_USER" "$DEST"
  cd "$DEST"
  # Re-exec from new location (prevents path mismatches)
#   exec bash "$DEST/$(basename "$0")"
fi

# Recompute paths after relocation
PROJECT_ROOT="$(pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend/web-app"
BACKEND_DIR="$PROJECT_ROOT/backend"
SQL_FILE="$PROJECT_ROOT/setup.sql"
VENV_DIR="$BACKEND_DIR/.venv"
FRONTEND_LOG="$PROJECT_ROOT/frontend.log"
BACKEND_LOG="$PROJECT_ROOT/backend.log"


echo "==> Installing frontend dependencies"
as_appuser "
  export NVM_DIR='$NVM_DIR'; source '$NVM_DIR/nvm.sh'; nvm use --lts >/dev/null;
  cd '$FRONTEND_DIR';
  rm -rf node_modules package-lock.json;
  npm cache clean --force;
  npm install
"

echo "==> Installing backend dependencies"
as_appuser "
  cd '$BACKEND_DIR';
  rm -rf .venv;
  python3 -m venv .venv;
  source .venv/bin/activate;
  pip install --upgrade pip;
  pip install -r requirements.txt
"

echo "Starting frontend on: $FRONTEND_PORT as $APP_USER"
as_appuser "
  export NVM_DIR='$NVM_DIR'; source '$NVM_DIR/nvm.sh'; nvm use --lts >/dev/null;
  cd '$FRONTEND_DIR';
  nohup npm run dev -- --port $FRONTEND_PORT --host >> '$FRONTEND_LOG' 2>&1 &
  disown
"

echo "Starting backend on: $BACKEND_PORT as $APP_USER"
as_appuser "
  cd '$BACKEND_DIR';
  source .venv/bin/activate;
  nohup flask --app src/app run --host=0.0.0.0 --port=$BACKEND_PORT >> '$BACKEND_LOG' 2>&1 &
  disown
"

echo "Setup complete"
echo "Frontend log: $FRONTEND_LOG"
echo "Backend log: $BACKEND_LOG"
echo "Check: ss -tulpn | grep -E ':($FRONTEND_PORT|$BACKEND_PORT)'"
