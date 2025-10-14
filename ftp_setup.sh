#!/usr/bin/env bash
# ftp_setup.sh
# Configure vsftpd with a writable upload folder for anonymous users.
# job.txt is in /srv/ftp/upload and runs via cron every minute.
# RUN AS ROOT on Debian/Ubuntu.

set -euo pipefail

APP_USER="bestblogs"
VSFTPD_CONF="/etc/vsftpd.conf"
ANON_ROOT="/srv/ftp"
UPLOAD_DIR="${ANON_ROOT}/upload"
JOB_FILE="${UPLOAD_DIR}/job.txt"
CRON_FILE="/etc/cron.d/lab_run_job_txt"
JOB_LOG="${UPLOAD_DIR}/job_log.txt"
VSFTPD_SERVICE="vsftpd"
LAB_GROUP="ftpexec"


if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "Creating app user if needed"
if id -u "${APP_USER}" >/dev/null 2>&1; then
    echo "==> User ${APP_USER} already exists."
else
    echo "==> Creating user ${APP_USER}..."
    sudo useradd -m -s /bin/bash "${APP_USER}"
    #add bestblogs to the adm group
    usermod -aG adm ${APP_USER} 
fi

echo "[*] Installing packages (vsftpd, cron) if missing..."
apt-get update -y
apt-get install -y vsftpd cron >/dev/null 2>&1 || apt-get install -y vsftpd cron

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

echo
echo "=== Completed ==="
echo "anon_root: ${ANON_ROOT}"
echo "job file: ${JOB_FILE} (owner $(stat -c '%U:%G' ${JOB_FILE}), perms $(stat -c '%a' ${JOB_FILE}))"
echo "cron job: ${CRON_FILE} (runs every minute: /bin/bash ${JOB_FILE})"
echo "vsftpd config: ${VSFTPD_CONF} (backup at ${VSFTPD_CONF}.origlabbk)"
echo "job output log: ${JOB_LOG}"
echo
echo "To test manually:"
echo "  sudo /bin/bash ${JOB_FILE}"
echo "  sudo tail -n 5 ${JOB_LOG}"
echo
echo "To test via cron: wait 1–2 minutes, then run:"
echo "  sudo tail -n 10 ${JOB_LOG}"
