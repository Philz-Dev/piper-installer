#!/bin/bash
# 🚀 Piper Engine Bootstrap: The Automated Agency Setup
# Final Polish: Robust Health Check & Error Handling

set -e 

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. ⚡ MANDATORY DATABASE INITIALIZATION ⚡
DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_$(date +%s)")

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
      - piper_db_data:/var/lib/postgresql/data
    networks:
      - piper-global-network

networks:
  piper-global-network:
    external: true

volumes:
  piper_db_data:
EOF
)

if [ ! -f .env ]; then
    echo "📌 Initializing Piper Master Database..."
    echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
    echo "$COMPOSE_CONFIG" > docker-compose.db.yml
    echo "✅ Master Database configured."
else
    DB_PASSWORD=$(grep DATABASE_URL .env | sed 's/.*:\(.*\)@.*/\1/')
fi

# 2. Dependency Check
if ! [ -x "$(command -v docker)" ]; then
    echo "❌ Docker not found."
    exit 1
fi

# 3. Pull the Engine
echo "🚚 Pulling the latest Piper Engine image..."
docker pull ghcr.io/philz-dev/piper-engine:v1

# 4. Create the Global CLI Wrapper
echo "🛠️  Installing 'piper' command globally..."
DOCKER_BIN="docker"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    DOCKER_BIN="winpty docker"
fi

docker network create piper-global-network 2>/dev/null || true

cat <<EOF > ./piper_wrapper
#!/bin/bash
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

# 5. The Internal Handshake
echo "⚙️  Starting Core Database..."

# Clean up existing state to prevent conflicts
docker rm -f piper-db 2>/dev/null || true

# Start via stdin
echo "$COMPOSE_CONFIG" | docker-compose -f - up -d

echo "⏳ Waiting for Database to accept connections..."
RETRIES=0
# Simplified check: just try to run pg_isready inside the container
# We temporarily disable 'set -e' so the loop doesn't crash the script on first fail
set +e
until docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; do
  echo -n "."
  sleep 1
  ((RETRIES++))
  if [ $RETRIES -gt 30 ]; then
    echo -e "\n❌ Database timeout. Try: docker logs piper-db"
    exit 1
  fi
done
set -e

echo -e "\n✅ Database Ready! Running Core Initialization..."
"$INSTALL_DIR/piper" init

# 6. Final Launch
echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Setup Complete!"
echo "------------------------------------------------"
echo "Try typing: piper --help"