#!/bin/bash
# 🚀 Piper Engine Universal Bootstrap (Cloud & One-Liner Ready)
set -e
export MSYS_NO_PATHCONV=1

# 🟢 REPO CONFIG (Update this!)
REPO_URL="https://github.com/philz-dev/piper-engine.git"

echo "------------------------------------------------"
echo "   PIPER ENGINE: Universal System Initialization "
echo "------------------------------------------------"

# 1. 🐧 LINUX/VPS DEPENDENCY CHECK
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "cygwin" ]]; then
    if ! command -v docker >/dev/null 2>&1; then
        echo "🐳 Docker not found. Installing..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        echo "✅ Docker installed. Please log out and back in if this is a fresh VPS."
    fi
fi

# 2. 📂 CLONE CHECK (For curl | bash users)
if [ ! -d "src" ]; then
    echo "📦 Repository components missing. Cloning from GitHub..."
    if command -v git >/dev/null 2>&1; then
        git clone "$REPO_URL" .
    else
        echo "❌ Error: git is not installed."
        exit 1
    fi
fi

# 3. 🌍 OS-AWARE PATH CAPTURE
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    HOST_PWD=$(pwd -W)
    DOCKER_SOCK="//var/run/docker.sock"
    EXTRA_VOLUMES="- /c/Users:/c/Users"
else
    HOST_PWD=$(pwd)
    DOCKER_SOCK="/var/run/docker.sock"
    EXTRA_VOLUMES=""
fi

# 4. ⚡ CREDENTIALS
if [ -f .env ]; then
    DB_PASSWORD=$(grep DATABASE_URL .env | sed -e 's|.*//[^:]*:\([^@]*\)@.*|\1|')
else
    echo "📌 Generating fresh credentials..."
    DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_$(date +%s)")
    echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
fi

sed -i "/HOST_PROJECT_PATH/d" .env || true
echo "HOST_PROJECT_PATH=$HOST_PWD" >> .env

# 5. 🧹 CLEANUP
echo "🧹 Cleaning up existing system components..."
docker rm -f piper-db piper-engine-master 2>/dev/null || true
docker network rm piper-network 2>/dev/null || true
docker network create piper-network

# 6. 🏗️ MERGED COMPOSE CONFIG
COMPOSE_CONFIG=$(cat <<EOF
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
      - ./piper_db_data:/var/lib/postgresql/data
    networks:
      piper-network:
        aliases:
          - db

  piper-master:
    image: ghcr.io/philz-dev/piper-engine:v1
    container_name: piper-engine-master
    restart: always
    entrypoint: ["tail", "-f", "/dev/null"]
    tty: true
    stdin_open: true
    environment:
      - DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data
      - MASTER_PASSWORD=$DB_PASSWORD
      - HOST_PROJECT_PATH=$HOST_PWD
      - IS_PIPER_CONTAINER=true
      - PYTHONPATH=/app:/app/src
    volumes:
      - "$HOST_PWD/.env:/app/.env"
      - "$DOCKER_SOCK:/var/run/docker.sock"
      - "$HOST_PWD:/app"
      $EXTRA_VOLUMES
    networks:
      - piper-network

networks:
  piper-network:
    external: true
EOF
)

# 7. 📥 LAUNCH CORE
echo "⚙️ Starting Core Services..."
# Detect if using 'docker compose' (plugin) or 'docker-compose' (standalone)
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi
echo "$COMPOSE_CONFIG" | $COMPOSE_CMD -f - up -d --remove-orphans

# 8. ⏳ DATABASE HANDSHAKE
until docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; do sleep 1; done

# 9. 🔗 DYNAMIC CLI WRAPPER
echo -e "\n🔗 Finalizing Global CLI..."
INSTALL_DIR="$HOME/piper_bin"
mkdir -p "$INSTALL_DIR"

cat <<'EOF' > "$INSTALL_DIR/piper"
#!/bin/bash
export MSYS_NO_PATHCONV=1
CORE_PATH=$(docker exec piper-engine-master find /app -name "core.py" | head -n 1 | tr -d '\r')

if [ -z "$CORE_PATH" ]; then
    echo "❌ Error: Could not find core.py inside the container /app folder."
    exit 1
fi

if [ "$1" == "start" ]; then
    CLIENT=$(echo "$@" | grep -oP '(?<=-c )[^ ]+|(?<=--client )[^ ]+')
    if [ -n "$CLIENT" ]; then
        docker rm -f "${CLIENT}_engine" 2>/dev/null || true
    fi
fi

docker exec -it piper-engine-master python "$CORE_PATH" "$@"
EOF

chmod +x "$INSTALL_DIR/piper"

# Add to PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    SHELL_RC="$HOME/.bashrc"
    [[ "$OSTYPE" == "msys" ]] && SHELL_RC="$HOME/.bash_profile"
    echo "export PATH=\"\$HOME/piper_bin:\$PATH\"" >> "$SHELL_RC"
    export PATH="$INSTALL_DIR:$PATH"
fi

echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Online"
echo "------------------------------------------------"