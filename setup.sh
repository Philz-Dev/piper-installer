#!/bin/bash
# 🚀 Piper Engine Bootstrap: The Automated Agency Setup
# Architecture: Forced Managed Infrastructure (Database-as-Code)

set -e # Exit immediately if a command fails

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. ⚡ MANDATORY DATABASE INITIALIZATION ⚡
if [ ! -f .env ]; then
    echo "📌 Initializing Piper Master Database..."
    
    # Generate a unique, secure password automatically
    DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_$(date +%s)")
    
    # Internal URL: 'db' is the hostname inside the Docker network
    echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
    
    # Create the dedicated Database Orchestrator
    cat <<EOF > docker-compose.db.yml
version: '3.8'
services:
  db:
    image: postgres:15-alpine
    restart: always
    environment:
      - POSTGRES_USER=piper_admin
      - POSTGRES_PASSWORD=$DB_PASSWORD
      - POSTGRES_DB=piper_data
    ports:
      - "5432:5432"
    volumes:
      - ./piper_db_data:/var/lib/postgresql/data
    networks:
      - piper-global-network

networks:
  piper-global-network:
    name: piper-global-network

volumes:
  piper_db_data:
EOF
    echo "✅ Master Database configured and secured."
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

# Detect if we are on Windows MINGW/MSYS to apply winpty
DOCKER_BIN="docker"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    DOCKER_BIN="winpty docker"
fi

# We ensure the network exists before running the wrapper
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
docker-compose -f docker-compose.db.yml up -d

echo "⏳ Waiting for Database to accept connections..."
# Professional Health Check loop: prevents init from failing if Postgres is slow to boot
until docker exec $(docker ps -q -f name=db) pg_isready -U piper_admin >/dev/null 2>&1; do
  echo -n "."
  sleep 1
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