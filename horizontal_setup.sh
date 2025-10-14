#!/usr/bin/env bash
set -euo pipefail

# -------------------- HORIZONTAL ESCALATION LAB (updated) --------------------
# Integrates with vertical_setup.sh already run on the machine.
# Creates two horizontal vectors:
#  1) PuTTY .ppk disguised in /tmp/.sys_cache/.thumb (readable by alice)
#  2) Shared tmux session for alice with tight sudo wrapper so alice can attach
#
# Usage: sudo ./horizontal_setup.sh
#
LAB_ATK="bestblog"
LAB_ATK_PASS="best123"
LAB_VICTIM="alice"
LAB_VICTIM_PASS="alice123"

# Where we'll place the disguised key (plausible app cache / opt location)
PPK_PLACEMENT_DIR="/tmp/.sys_cache"
PPK_PLACEMENT_PATH="${PPK_PLACEMENT_DIR}/.thumb"

HINT_ATK="/home/${LAB_ATK}/.hint_attacker"
AUDIT_PUTTY_KEY="puttygen_exec"
AUDIT_HOME_KEY="home_write"
FIND_PPK_HELPER="/usr/local/bin/find_ppk"

export DEBIAN_FRONTEND=noninteractive

echo "[*] Starting enhanced horizontal escalation lab setup..."

# -------------------------
# Packages
# -------------------------
apt-get update -y
# install packages (tmux + puttygen + audit + aide if missing). No reliance on setfacl.
apt-get install -y openssh-server putty-tools auditd aide vim less curl tmux sudo

# Ensure sshd + auditd running
systemctl enable --now ssh >/dev/null 2>&1 || true
systemctl enable --now auditd >/dev/null 2>&1 || true

# -------------------------
# Create users
# -------------------------
# Create victim and attacker users if missing (idempotent)
if ! id "${LAB_VICTIM}" &>/dev/null; then
  useradd -m -s /bin/bash "${LAB_VICTIM}"
  echo "${LAB_VICTIM}:${LAB_VICTIM_PASS}" | chpasswd
fi

if ! id "${LAB_ATK}" &>/dev/null; then
  useradd -m -s /bin/bash "${LAB_ATK}"
  echo "${LAB_ATK}:${LAB_ATK_PASS}" | chpasswd
  usermod -aG adm ${LAB_ATK} #configure adm group for attacker
fi

touch /var/log/flaskapp.log
chown root:adm /var/log/flaskapp.log
chmod 640 /var/log/flaskapp.log  # Read for adm group

# Seed with LAB_VICTIM and LAB_VICTIM_PASS for demo (attacker can cat to pivot)
echo "2025-10-14 10:00:00 - LAB_VICTIM=${LAB_VICTIM} LAB_VICTIM_PASS=${LAB_VICTIM_PASS}" | tee -a /var/log/flaskapp.log
chown root:adm /var/log/flaskapp.log  # Restore ownership after append

# -------------------------
# Victim SSH keys & flag
# -------------------------
VICTIM_KEY_TYPE="ed25519"
VICTIM_PRIV_KEY="/home/${LAB_VICTIM}/.ssh/id_${VICTIM_KEY_TYPE}"

sudo -u "${LAB_VICTIM}" mkdir -p /home/"${LAB_VICTIM}"/.ssh
sudo -u "${LAB_VICTIM}" chmod 700 /home/"${LAB_VICTIM}"/.ssh

if [ ! -f "${VICTIM_PRIV_KEY}" ]; then
  sudo -u "${LAB_VICTIM}" ssh-keygen -t "${VICTIM_KEY_TYPE}" -f "${VICTIM_PRIV_KEY}" -N "" -C "alice_lab_key" >/dev/null 2>&1 || true
fi

# Append pubkey to authorized_keys (idempotent)
if [ -f "${VICTIM_PRIV_KEY}.pub" ]; then
  grep -qxF "$(cat ${VICTIM_PRIV_KEY}.pub)" /home/"${LAB_VICTIM}"/.ssh/authorized_keys 2>/dev/null || \
    cat "${VICTIM_PRIV_KEY}.pub" >> /home/"${LAB_VICTIM}"/.ssh/authorized_keys 2>/dev/null || true
fi

chown -R "${LAB_VICTIM}:${LAB_VICTIM}" /home/"${LAB_VICTIM}"/.ssh
chmod 700 /home/"${LAB_VICTIM}"/.ssh
[ -f /home/"${LAB_VICTIM}"/.ssh/authorized_keys ] && chmod 600 /home/"${LAB_VICTIM}"/.ssh/authorized_keys || true

# -------------------------
# Place disguised PPK
# -------------------------
mkdir -p "${PPK_PLACEMENT_DIR}"
chmod 0755 "${PPK_PLACEMENT_DIR}" || true

if command -v puttygen >/dev/null 2>&1; then
  TMP_COPY="/tmp/alice_priv_tmp"
  cp "${VICTIM_PRIV_KEY}" "${TMP_COPY}" || true
  chmod 600 "${TMP_COPY}" || true
  puttygen "${TMP_COPY}" -O private -o "${PPK_PLACEMENT_DIR}/alice_private.ppk" >/dev/null 2>&1 || true
  rm -f "${TMP_COPY}" || true
  mv "${PPK_PLACEMENT_DIR}/alice_private.ppk" "${PPK_PLACEMENT_PATH}" || true
  # make it plausible and readable by alice so they can discover it
  chown "${LAB_ATK}:${LAB_ATK}" "${PPK_PLACEMENT_PATH}" || true
  chmod 0644 "${PPK_PLACEMENT_PATH}" || true
else
  echo "WARNING: puttygen not installed; place a .ppk at ${PPK_PLACEMENT_PATH}"
fi

# Slight timestamp change to simulate being dropped earlier
if [ -f "${PPK_PLACEMENT_PATH}" ]; then
  touch --date="30 minutes ago" "${PPK_PLACEMENT_PATH}" || true
fi

# -------------------------
# Ensure SSH allows publickey authentication (so converted key works)
# -------------------------
mkdir -p /etc/ssh/sshd_config.d
echo "PubkeyAuthentication yes" > /etc/ssh/sshd_config.d/99-lab-pubkey.conf
systemctl restart ssh || true

# -------------------------
# Hints: visible + hidden
# -------------------------
# Visible main hint (alice home)
cat > "${HINT_ATK}" <<'MAINHINT'
There are 3 ways to get into alice's account:

1) Disguised private key (details hidden on the host).
2) [To be implemented later].
3) Shared tmux session (details hidden on the host).

Find the hidden notes on the VM to reveal steps for 1 and 3.
MAINHINT

chown "${LAB_ATK}:${LAB_ATK}" "${HINT_ATK}" || true
chmod 0640 "${HINT_ATK}" || true

# Hidden PPK hint (near the PPK)
HINT_PPK="${PPK_PLACEMENT_DIR}/.hint_ppk"
cat > "${HINT_PPK}" <<'PPK'
Hidden hint (Way 1 — PPK):
- Disguised key: /tmp/.sys_cache/.thumb
- Convert PPK -> OpenSSH and SSH locally:
    puttygen /tmp/.sys_cache/.thumb -O private-openssh -o /tmp/converted_id
    chmod 600 /tmp/converted_id
    ssh -i /tmp/converted_id alice@localhost
PPK
chown root:root "${HINT_PPK}" && chmod 0640 "${HINT_PPK}" || true
# Optionally make readable by alice (left restricted so trainees must discover)
# chown root:root "${HINT_PPK}"; setfacl -m u:${LAB_ATK}:r "${HINT_PPK}" 2>/dev/null || true

# Hidden tmux hint
HINT_TMUX="/tmp/.alice_tmux_hint"
cat > "${HINT_TMUX}" <<'TMUX'
Hidden hint (Way 3 — tmux):
tmux only allows clients with the same user as the server.
Use the allowed sudo wrapper to run the client as alice:

  sudo -u alice tmux -S /tmp/alice_tmux.sock attach -t shared

If you see "no session", list first:
  sudo -u alice tmux -S /tmp/alice_tmux.sock ls
TMUX
chown root:root "${HINT_TMUX}" && chmod 0640 "${HINT_TMUX}" || true

# -------------------------
# Shared tmux session & sudoers wrapper
# -------------------------
TMUX_SOCKET="/tmp/alice_tmux.sock"
TMUX_SESSION="shared"
TMUX_GROUP="alice_tmux"

# ensure group exists and both users are members (useful lab context)
groupadd -f "${TMUX_GROUP}" || true
usermod -a -G "${TMUX_GROUP}" "${LAB_VICTIM}" || true
usermod -a -G "${TMUX_GROUP}" "${LAB_ATK}" || true

# remove any stale socket and (re)start server as alice
[ -S "${TMUX_SOCKET}" ] && rm -f "${TMUX_SOCKET}" || true
sudo -u "${LAB_VICTIM}" tmux -S "${TMUX_SOCKET}" new -d -s "${TMUX_SESSION}" bash -lc "echo '[lab tmux: owned by ${LAB_VICTIM}]'; exec bash" || true

if [ ! -S "${TMUX_SOCKET}" ]; then
  echo "ERROR: socket ${TMUX_SOCKET} missing after tmux server creation."
fi

# Tight sudoers rule: allow alice (and group) to run tmux client as alice for this socket only.
SUDOERS_FILE="/etc/sudoers.d/90-alice-tmux"
cat > "${SUDOERS_FILE}" <<EOF
# Allow ${LAB_ATK} (and members of ${TMUX_GROUP}) to run the tmux client as alice for this specific socket
Cmnd_Alias TMUX_alice=/usr/bin/tmux -S ${TMUX_SOCKET} *
${LAB_ATK}    ALL=(alice) NOPASSWD: TMUX_alice
%${TMUX_GROUP} ALL=(alice) NOPASSWD: TMUX_alice
EOF
chmod 0440 "${SUDOERS_FILE}"
# validate syntax; if invalid, remove to avoid locking sudo
if ! visudo -cf "${SUDOERS_FILE}" >/dev/null 2>&1; then
  echo "WARNING: sudoers file ${SUDOERS_FILE} failed validation and will be removed"
  rm -f "${SUDOERS_FILE}"
fi

echo "[*] tmux server ready as ${LAB_VICTIM}."
echo "    Trainee command (Way 3): sudo -u ${LAB_VICTIM} tmux -S ${TMUX_SOCKET} attach -t ${TMUX_SESSION}"

# -------------------------
# Final info / sanity checks
# -------------------------
echo "[*] Setup complete."
echo " - Disguised PPK placed at: ${PPK_PLACEMENT_PATH} (if generated)"
echo " - Visible hint at: ${HINT_ATK}"
echo " - Hidden PPK hint at: ${HINT_PPK}"
echo " - Hidden tmux hint at: ${HINT_TMUX}"
echo " - tmux socket: ${TMUX_SOCKET} (owner should be ${LAB_VICTIM})"
echo " - sudoers drop-in: ${SUDOERS_FILE}"

# Print a short verification summary
ls -l "${PPK_PLACEMENT_PATH}" 2>/dev/null || true
ls -l "${HINT_ATK}" 2>/dev/null || true
ls -l "${HINT_PPK}" 2>/dev/null || true
ls -l "${HINT_TMUX}" 2>/dev/null || true
ls -l "${TMUX_SOCKET}" 2>/dev/null || true
getent group "${TMUX_GROUP}" || true

exit 0
