#!/usr/bin/env bash
set -euo pipefail

# -------------------- VERTICAL ESCALATION VECTORS --------------------

LAB_USER="bobby"
LAB_PASS="qwerty2020"
SUDOERS_FILE="/etc/sudoers.d/lab_bobby_nano_npm"
TMP_PY="/opt/tmp.py"
CRON_FILE="/etc/cron.d/lab_tmp_py"
DB_NAME="labdb"
DB_ROLE="bobby"
DB_PASS="DbBobbyPass!@#"
BOB_BASHRC="/home/${LAB_USER}/.bashrc"
ROOT_PLAIN="angelbaby"
ROOT_BCRYPT='$2a$12$/bsaKryakHSiT9BJyrj0WuMQaegv0AZ7m0WELGxBHUJrTt7a.tFDq'

export DEBIAN_FRONTEND=noninteractive

# install minimal packages
apt-get update -y
apt-get install -y sudo nano nodejs npm cron acl postgresql openssl

# ---------- Set root system password ----------
echo "root:${ROOT_PLAIN}" | chpasswd
passwd -u root 2>/dev/null || true

# ---------- Create bobby user ----------
if ! id "$LAB_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$LAB_USER"
  echo "${LAB_USER}:${LAB_PASS}" | chpasswd
fi

# ---------- Sudoers: allow bobby to run nano & npm without password ----------
cat > "$SUDOERS_FILE" <<EOF
# lab: allow $LAB_USER to run nano and npm as root without password
$LAB_USER ALL=(ALL) NOPASSWD: /usr/bin/nano, /usr/bin/npm
EOF
chmod 0440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1 || { rm -f "$SUDOERS_FILE"; echo "invalid sudoers"; exit 1; }

# ---------- /opt/tmp.py owned by root:root, grant bobby rw via ACL ----------
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
setfacl -m u:"$LAB_USER":rw "$TMP_PY" || true

touch /var/log/tmp_py.log /var/log/tmp_py_error.log
chown root:root /var/log/tmp_py*.log
chmod 0644 /var/log/tmp_py*.log

# ---------- Install root cron job (runs every minute) ----------
cat > "$CRON_FILE" <<CRON
* * * * * root /usr/bin/python3 /opt/tmp.py
CRON
chmod 0644 "$CRON_FILE"

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart cron >/dev/null 2>&1 || true
else
  service cron restart >/dev/null 2>&1 || true
fi

# ---------- PostgreSQL: create role, DB, table, insert bcrypt ----------
systemctl enable --now postgresql >/dev/null 2>&1 || true

# Create DB role if not exists
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "\
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname='${DB_ROLE}') THEN CREATE ROLE ${DB_ROLE} LOGIN PASSWORD '${DB_PASS}'; END IF; END \$\$;"

# Create database if not exists
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${DB_NAME};"
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_ROLE};"

# Create users table and ensure only the 'root' row with bcrypt exists
sudo -u postgres psql -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL
);
DELETE FROM users WHERE username = 'root';
INSERT INTO users (username, password_hash) VALUES ('root', '${ROOT_BCRYPT}');
SQL

# Grant SELECT to bobby role
sudo -u postgres psql -d "${DB_NAME}" -c "GRANT SELECT ON TABLE users TO ${DB_ROLE};" >/dev/null 2>&1 || true

# ---------- Export DB creds into bobby's .bashrc ----------
export_block="# BEGIN LAB DB ENV
export LAB_DB_NAME='${DB_NAME}'
export LAB_DB_USER='${DB_ROLE}'
export LAB_DB_PASS='${DB_PASS}'
# END LAB DB ENV
"
touch "$BOB_BASHRC"
chown "$LAB_USER:$LAB_USER" "$BOB_BASHRC"
chmod 0644 "$BOB_BASHRC"
if ! grep -q "BEGIN LAB DB ENV" "$BOB_BASHRC"; then
  printf "\n%s\n" "$export_block" >> "$BOB_BASHRC"
  chown "$LAB_USER:$LAB_USER" "$BOB_BASHRC"
fi

# ---------- Enable root SSH login with password (override sshd_config.d) ----------
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

# ---------- Create two hidden hint files in bobby's home ----------
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

chown "$LAB_USER:$LAB_USER" "$HINT1_PATH" "$HINT2_PATH"
chmod 0640 "$HINT1_PATH" "$HINT2_PATH"


# ---------- Create /root/root.txt flag ----------
ROOT_FLAG="/root/root.txt"

cat > "$ROOT_FLAG" <<'FLAG'
Congratulations! 

You’ve successfully escalated privileges to root.

Well done — mission accomplished.
FLAG

chown root:root "$ROOT_FLAG"
chmod 0400 "$ROOT_FLAG"

cat <<EOF
Lab Setup complete.
EOF