#!/usr/bin/env bash
set -euo pipefail

#####################################
#           CONFIGURATION           #
#####################################
PROJECT_ROOT="$(pwd)"                    
FRONTEND_DIR="$PROJECT_ROOT/frontend"
BACKEND_DIR="$PROJECT_ROOT/backend"
SQL_FILE="$PROJECT_ROOT/setup.sql"   
VENV_DIR="$PROJECT_ROOT/backend/.venv"

GUNICORN_MODULE="wsgi:app"

BACKEND_PORT="5000"
FRONTEND_PORT="5173"

DB_NAME="bestblogs"
DB_USER="bestblogs_user"
DB_PASS="bestblogs_password"

echo "==> Updating apt and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y build-essential python3 python3-venv python3-pip mysql-server curl php php-cli

echo "==> Installing Node.js LTS (for Vite/React)..."
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
set +u
source "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
set -u
node -v    
npm -v

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


echo "Starting frontend"
(
    cd "$FRONTEND_DIR/web-app"
    rm -rf node_modules package-lock.json
    npm cache clean --force
    npm install
    npm run dev -- --port "$FRONTEND_PORT" --host > "$PROJECT_ROOT/frontend.log" 2>&1
) &

echo "Starting backend"
(
    rm -rf "$VENV_DIR"
    cd "$BACKEND_DIR"
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    flask --app src/app run --host=0.0.0.0 --port="$BACKEND_PORT" > "$PROJECT_ROOT/backend.log" 2>&1
) &

echo "Setup complete"
wait
