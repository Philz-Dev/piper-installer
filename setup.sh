#!/bin/bash
# 🚀 Piper Engine Bootstrap: The Automated Agency Setup
# Architecture: Forced Managed Infrastructure (Database-as-Code)
# Fix: RAM-to-Stdin streaming to bypass Windows File System Sync issues

set -e # Exit immediately if a command fails

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. ⚡ MANDATORY DATABASE INITIALIZATION ⚡
# Define the config first so it's available in memory even if the file exists
DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_$(date +%s)")

COMPOSE_CONFIG=$(cat <<EOF
version: '3.8'
services:
  db:
    image: postgres:15-alpine
    container_name: piper-db
    restart: always
    environment:
      - POSTGRES_USER=piper_admin
      - POSTGRES_PASSWORD=$DB_PASSWORD
      - POSTGRES_DB=piper_data
    ports:
      - "5432:5432"
    volumes:
      - piper_db_data:/var/lib/postgresql/data
    networks:
      - piper-global-network

networks:
  piper-global-network:
    name: piper-global-network

volumes:
  piper_db_data:
EOF
)

if [ ! -f .env ]; then
    echo "📌 Initializing Piper Master Database..."
    echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
    # We still save the file for the user's future use
    echo "$COMPOSE_CONFIG" > docker-compose.db.yml
    echo "✅ Master Database configured and secured."
else
    # If .env exists, we try to pull the existing password for the display at the end
    DB_PASSWORD=$(grep DATABASE_URL .env | sed 's/.*:\(.*\)@.*/\1/')
fi

# 2. Dependency Check: Install Docker if missing
if ! [ -x "$(command -v docker)" ]; then
    echo "📦 Docker not found. Installing now..."
    if [ -x "$(command -v sudo)" ]; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
    else
        echo "❌ Automatic Docker install requires sudo. Please install Docker manually."
        exit 1
    fi
    echo "✅ Docker installed."
else
    echo "✅ Docker is already installed."
fi

# 3. Pull the Engine
echo "🚚 Pulling the latest Piper Engine image..."
docker pull ghcr.io/philz-dev/piper-engine:v1

# 4. Create the Global CLI Wrapper (with Windows TTY Fix)
echo "🛠️  Installing 'piper' command globally..."

DOCKER_BIN="docker"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    DOCKER_BIN="winpty docker"
fi

docker network create piper-global-network 2>/dev/null || true

cat <<EOF > ./piper_wrapper
#!/bin/bash
# Piper CLI Wrapper
$DOCKER_BIN run --rm -it \\
  -v "/\$(pwd):/app" \\
  --network piper-global-network \\
  --env-file .env \\
  ghcr.io/philz-dev/piper-engine:v1 "\$@"
EOF

if [ -w "/usr/local/bin" ] || ([ -x "$(command -v sudo)" ] && sudo mkdir -p /usr/local/bin 2>/dev/null); then
    INSTALL_DIR="/usr/local/bin"
    CMD_PREFIX=""
    if [ -x "$(command -v sudo)" ]; then CMD_PREFIX="sudo "; fi
    $CMD_PREFIX mv ./piper_wrapper "$INSTALL_DIR/piper"
    $CMD_PREFIX chmod +x "$INSTALL_DIR/piper"
else
    INSTALL_DIR="$HOME/piper_bin"
    mkdir -p "$INSTALL_DIR"
    mv ./piper_wrapper "$INSTALL_DIR/piper"
    chmod +x "$INSTALL_DIR/piper"
    export PATH="$PATH:$INSTALL_DIR"
    
    SHELL_PROFILE="$HOME/.bashrc"
    [ -f "$HOME/.bash_profile" ] && SHELL_PROFILE="$HOME/.bash_profile"
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$SHELL_PROFILE"
    fi
fi

echo "✅ Global 'piper' command installed in $INSTALL_DIR."

# 5. The Internal Handshake: Run init
echo "⚙️  Starting Core Database..."

# FIX: Stream the configuration directly from the Bash variable
# This bypasses the Windows hard drive entirely during the startup process.
echo "$COMPOSE_CONFIG" | docker-compose -f - up -d

echo "⏳ Waiting for Database to accept connections..."
RETRIES=0
until [ "$(docker ps -q -f name=piper-db)" ] && docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; do
  echo -n "."
  sleep 1
  ((RETRIES++))
  if [ $RETRIES -gt 30 ]; then
    echo -e "\n❌ Database failed to start. Run 'docker logs piper-db' to troubleshoot."
    exit 1
  fi
done

echo -e "\n✅ Database Ready! Running Core Initialization..."
"$INSTALL_DIR/piper" init

# 6. Final Launch
echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Setup Complete!"
echo "------------------------------------------------"
echo "📍 DATABASE CREDENTIALS (Saved in .env):"
echo "   User: piper_admin"
echo "   Pass: $DB_PASSWORD"
echo "------------------------------------------------"
echo "Try typing: piper --help"