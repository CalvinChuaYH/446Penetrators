#!/usr/bin/env bash
# ftp_setup.sh
# Idempotent: configure vsftpd + perms so anonymous can ls, uploads enabled (no mkdir), job.txt exists,
# and a cron runs /bin/bash /srv/ftp/job.txt every minute.
# RUN AS ROOT on Debian/Ubuntu.

set -euo pipefail

VSFTPD_CONF="/etc/vsftpd.conf"
ANON_ROOT="/srv/ftp"
JOB_FILE="${ANON_ROOT}/job.txt"
CRON_FILE="/etc/cron.d/lab_run_job_txt"
JOB_LOG="/var/log/job_txt_exec.log"
VSFTPD_SERVICE="vsftpd"

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[*] Installing packages (vsftpd, cron) if missing..."
apt-get update -y
apt-get install -y vsftpd cron >/dev/null 2>&1 || apt-get install -y vsftpd cron

echo "[*] Creating anon root and ensuring ftp user exists..."
mkdir -p /srv
mkdir -p "${ANON_ROOT}"
if ! id ftp &>/dev/null; then
  useradd -r -s /usr/sbin/nologin -d "${ANON_ROOT}" ftp || true
fi

echo "[*] Set ownership: ftp:ftp"
chown -R ftp:ftp "${ANON_ROOT}"

echo "[*] Ensure directories are 0755 so anonymous can ls"
find "${ANON_ROOT}" -type d -exec chmod 0755 {} \; || true

echo "[*] Create job.txt if missing or empty..."
if [ ! -s "${JOB_FILE}" ]; then
  cat > "${JOB_FILE}" <<'EOF'
#!/usr/bin/env bash
echo "Hello from job.txt at $(date)" >> /var/log/job_txt_exec.log
EOF
fi

echo "[*] Ensure files are 0644 so readable but not executable"
find "${ANON_ROOT}" -type f -exec chmod 0644 {} \; || true
chown ftp:ftp "${JOB_FILE}"
chmod 0644 "${JOB_FILE}"

echo "[*] Ensure job log exists (root-owned)"
touch "${JOB_LOG}"
chown root:root "${JOB_LOG}"
chmod 0644 "${JOB_LOG}"

# Helper: set or add key in vsftpd.conf
set_or_add_conf() {
  local key="$1"
  local val="$2"
  if grep -q -E "^\s*#?\s*${key}\s*=" "${VSFTPD_CONF}" 2>/dev/null; then
    sed -ri "s|^\s*#?\s*${key}\s*=.*|${key}=${val}|g" "${VSFTPD_CONF}"
  else
    echo "${key}=${val}" >> "${VSFTPD_CONF}"
  fi
}

echo "[*] Backing up vsftpd config if not already backed up..."
if [ ! -f "${VSFTPD_CONF}.origlabbk" ]; then
  cp "${VSFTPD_CONF}" "${VSFTPD_CONF}.origlabbk"
fi

echo "[*] Writing required vsftpd settings..."
set_or_add_conf "anonymous_enable" "YES"
set_or_add_conf "anon_root" "${ANON_ROOT}"
set_or_add_conf "anon_upload_enable" "YES"
set_or_add_conf "anon_mkdir_write_enable" "NO"
set_or_add_conf "chroot_local_user" "YES"
set_or_add_conf "write_enable" "YES"
set_or_add_conf "dirlist_enable" "YES"
set_or_add_conf "anon_umask" "022"
set_or_add_conf "file_open_mode" "0644"

echo "[*] Restarting vsftpd..."
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "${VSFTPD_SERVICE}" || service "${VSFTPD_SERVICE}" restart || true
else
  service "${VSFTPD_SERVICE}" restart || true
fi

echo "[*] Creating cron job to run /bin/bash ${JOB_FILE} every minute as root"
cat > "${CRON_FILE}" <<CRON
# run the FTP-provided job.txt every minute as root; append stdout/stderr to ${JOB_LOG}
* * * * * root /bin/bash "${JOB_FILE}" >> ${JOB_LOG} 2>&1
CRON
chmod 0644 "${CRON_FILE}"

echo "[*] Reloading cron"
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart cron >/dev/null 2>&1 || true
else
  service cron restart >/dev/null 2>&1 || true
fi

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
