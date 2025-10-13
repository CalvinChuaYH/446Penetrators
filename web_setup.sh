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

as_appuser() {
  sudo -u "$APP_USER" bash -lc "export HOME='$APP_HOME'; $*"
}

echo "Creating app user if needed"
if id -u "${APP_USER}" >/dev/null 2>&1; then
    echo "==> User ${APP_USER} already exists."
else
    echo "==> Creating user ${APP_USER}..."
    sudo useradd -m -s /bin/bash "${APP_USER}"
fi

echo "==> Updating apt and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y build-essential python3 python3-venv python3-pip mysql-server curl php php-cli

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
  DEST="$APP_HOME/$PROJECT_NAME"
  echo "==> Relocating project to $DEST ..."
  mkdir -p "$APP_HOME"
  mv "$PROJECT_ROOT" "$DEST"
  chown -R "$APP_USER:$APP_USER" "$DEST"
  # Re-exec from new location (prevents path mismatches)
  exec bash "$DEST/$(basename "$0")"
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
  rm -rf "$VENV_DIR";
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
