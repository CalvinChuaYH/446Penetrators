#!/usr/bin/env bash
set -euo pipefail

#####################################
#           CONFIGURATION           #
#####################################
PROJECT_ROOT="$(pwd)"                    # Run this script from your repo root
mkdir -p "$PROJECT_ROOT/app"
FRONTEND_DIR="$PROJECT_ROOT/app/frontend"
BACKEND_DIR="$PROJECT_ROOT/app/backend"
SQL_FILE="$PROJECT_ROOT/app/setup.sql"   # Path to your SQL setup script
VENV_DIR="$PROJECT_ROOT/app/backend/venv"

GUNICORN_MODULE="wsgi:app"

BACKEND_PORT="5000"
FRONTEND_PORT="5173"

DB_NAME="bestblogs"
DB_USER="bestblogs_user"
DB_PASS="bestblogs_password"

#####################################
#               SETUP               #
#####################################
setup() {
  echo "==> Updating apt and installing dependencies..."
  apt-get update -y
  apt-get install -y build-essential python3 python3-venv python3-pip mysql-server curl git

  echo "==> Installing Node.js LTS (for Vite/React)..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y nodejs

  echo "==> Creating Python virtual environment and installing backend requirements..."
  python3 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  if [[ -f "$BACKEND_DIR/requirements.txt" ]]; then
    pip install -r "$BACKEND_DIR/requirements.txt"
  else
    echo "⚠️  No requirements.txt found under $BACKEND_DIR"
  fi
  deactivate

  echo "==> Configuring MySQL (database + user + import)..."
  systemctl enable --now mysql
  mysql --protocol=socket <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

  if [[ -f "$SQL_FILE" ]]; then
    echo "==> Running setup SQL file..."
    mysql --protocol=socket "$DB_NAME" < "$SQL_FILE"
  else
    echo "⚠️  No SQL file found at $SQL_FILE — skipping import."
  fi

  echo "==> Building frontend..."
  if [[ -f "$FRONTEND_DIR/package.json" ]]; then
    cd "$FRONTEND_DIR"
    npm ci || npm install
    npm run build
  else
    echo "⚠️  No package.json found under $FRONTEND_DIR"
  fi

  echo "✅ Setup complete."
}

#####################################
#               START               #
#####################################
start() {
  echo "==> Starting backend (Flask via Gunicorn)..."
  cd "$BACKEND_DIR"
  source "$VENV_DIR/bin/activate"
  gunicorn --workers 3 --bind 0.0.0.0:$BACKEND_PORT "$GUNICORN_MODULE" &
  BACKEND_PID=$!
  echo "Backend running on port $BACKEND_PORT (PID $BACKEND_PID)"
  deactivate

  echo "==> Starting frontend (Vite preview)..."
  cd "$FRONTEND_DIR"
  npx vite preview --host 0.0.0.0 --port "$FRONTEND_PORT" &
  FRONTEND_PID=$!
  echo "Frontend running on port $FRONTEND_PORT (PID $FRONTEND_PID)"

  echo
  echo "🌐 Frontend: http://<vm-ip>:$FRONTEND_PORT"
  echo "🛠  Backend:  http://<vm-ip>:$BACKEND_PORT"
  echo
  echo "Press Ctrl+C to stop both processes."
  echo

  # Keep script alive while both processes run
  wait $BACKEND_PID $FRONTEND_PID
}