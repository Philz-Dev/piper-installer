#!/bin/bash
# 🚀 Piper Engine Bootstrap: High-Speed Provisioning (Global Persistence Version)
set -e

# ✅ GLOBAL FIX: Prevent Git Bash from mangling Windows paths into Linux paths
export MSYS_NO_PATHCONV=1

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. ⚡ CREDENTIALS ⚡
if [ -f .env ]; then
    sed -i 's/@piper-db:/@db:/g' .env || true
    DB_PASSWORD=$(grep DATABASE_URL .env | sed -e 's|.*//[^:]*:\([^@]*\)@.*|\1|')
else
    echo "📌 Generating fresh credentials..."
    DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_$(date +%s)")
    echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
fi

# ✅ WINDOWS VS LINUX COMPOSE LOGIC
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    DB_VOLUMES="- ./piper_db_data:/var/lib/postgresql/data"
else
    DB_VOLUMES="- ./piper_db_data:/var/lib/postgresql/data
      - /var/run/docker.sock:/var/run/docker.sock"
fi

# --- FIX 1: Add 'external: true' to keep Compose from fighting the manual network ---
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
      $DB_VOLUMES
    networks:
      piper-network:
        aliases:
          - db
networks:
  piper-network:
    external: true
EOF
)

# 2. 🧹 THE CLEANUP FIX (Universal & Stable)
echo "🧹 Cleaning up old networks and clearing project cache..."

# ✅ FIX 2: Find and remove ANY worker on the network to prevent "Ghost IDs"
ACTIVE_WORKERS=$(docker ps -a --filter "network=piper-network" --format "{{.ID}}" 2>/dev/null || true)
if [ -n "$ACTIVE_WORKERS" ]; then
    echo "🔗 Unlinking active workers..."
    docker rm -f $ACTIVE_WORKERS 2>/dev/null || true
fi

docker rm -f piper-db piper_db piper_core client_temp 2>/dev/null || true
docker network rm piper-network 2>/dev/null || true
docker network prune -f

# Manually create the bridge so it's ready for the Handshake
docker network create piper-network

# 3. Pulling Engine
echo "📥 Ensuring Piper Engine image is present..."
docker pull ghcr.io/philz-dev/piper-engine:v1

# 4. Global Command Setup
echo "🔗 Setting up Global CLI..."
cat <<'EOF' > ./piper_wrapper
#!/bin/bash
export MSYS_NO_PATHCONV=1
DOCKER_BIN="docker"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    [ -t 0 ] && DOCKER_BIN="winpty docker"
    DOCKER_OPTS="-e DOCKER_HOST=tcp://host.docker.internal:2375"
else
    DOCKER_OPTS="-v /var/run/docker.sock:/var/run/docker.sock"
fi

$DOCKER_BIN run --rm -it \
    $DOCKER_OPTS \
    -v "/$(pwd):/app" \
    -v "/$(pwd)/.piper_config:/app/.piper_config" \
    --network piper-network \
    --env-file .env \
    ghcr.io/philz-dev/piper-engine:v1 "$@"
EOF

INSTALL_DIR="$HOME/piper_bin"
mkdir -p "$INSTALL_DIR"
mv ./piper_wrapper "$INSTALL_DIR/piper"
chmod +x "$INSTALL_DIR/piper"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "export PATH=\"\$HOME/piper_bin:\$PATH\"" >> ~/.bash_profile
fi

export PATH="$INSTALL_DIR:$PATH"
hash -r

# 5. ⚙️ STARTING DATABASE
echo "⚙️  Starting Core Database..."
echo "$COMPOSE_CONFIG" | docker-compose -f - up -d --remove-orphans

echo "⏳ Waiting for Database..."
until docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; do
    echo -n "."
    sleep 2
done

# ✅ NEW: Capture the Windows-specific path
echo "Capturing project root path..."
# 'pwd -W' is the secret weapon for Git Bash on Windows
WINDOWS_PWD=$(pwd -W)

# Check if HOST_PROJECT_PATH already exists in .env
if grep -q "HOST_PROJECT_PATH" .env; then
    # Update it if it exists
    sed -i "s|HOST_PROJECT_PATH=.*|HOST_PROJECT_PATH=$WINDOWS_PWD|" .env
else
    # Append it if it doesn't
    echo "HOST_PROJECT_PATH=$WINDOWS_PWD" >> .env
fi

echo "✅ Project root saved: $WINDOWS_PWD"

# 6. HANDSHAKE
echo -e "\n🚀 Running Core Initialization..."
"$INSTALL_DIR/piper" init
alias piper="$INSTALL_DIR/piper"

echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Online"
echo "------------------------------------------------"