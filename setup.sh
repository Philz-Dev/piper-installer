#!/bin/bash
# 🚀 Piper Engine Bootstrap: High-Speed Provisioning
# Architecture: RAM-only Config + Aggressive Health Check

set -e 

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. ⚡ CREDENTIALS & RAM CONFIG ⚡
# We use 'db' as a consistent alias for the internal connection
if [ -f .env ]; then
    sed -i 's/@piper-db:/@db:/g' .env || true
    DB_PASSWORD=$(grep DATABASE_URL .env | sed -e 's|.*//[^:]*:\([^@]*\)@.*|\1|')
else
    echo "📌 Generating fresh credentials..."
    DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_$(date +%s)")
    echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
fi

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
      piper-global-network:
        aliases:
          - db
networks:
  piper-global-network:
    external: true
EOF
)

# 2. Dependency Check & Network Prep
docker network create piper-global-network 2>/dev/null || true

# 3. Pulling Engine
echo "🚚 Pulling Piper Engine..."
docker pull ghcr.io/philz-dev/piper-engine:v1

# 4. Global Command Setup (The "Universal DNS" Fix)
cat <<'EOF' > ./piper_wrapper
#!/bin/bash
USE_TTY="-it"
FINAL_BIN="docker"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    if [ -t 0 ]; then
        FINAL_BIN="winpty docker"
    else
        USE_TTY="-i" 
    fi
fi

# 🚀 THE FIX: Using --link AND --add-host to force resolution
# We map 'db' to the special Docker gateway address
$FINAL_BIN run --rm $USE_TTY \
  -v "/$(pwd):/app" \
  --network piper-global-network \
  --add-host=db:host.docker.internal \
  --link piper-db:db \
  --env-file .env \
  ghcr.io/philz-dev/piper-engine:v1 "$@"
EOF

# Install to path
INSTALL_DIR="/usr/local/bin"
[ ! -w "$INSTALL_DIR" ] && INSTALL_DIR="$HOME/piper_bin"
mkdir -p "$INSTALL_DIR"
mv ./piper_wrapper "$INSTALL_DIR/piper"
chmod +x "$INSTALL_DIR/piper"
[[ ":$PATH:" != *":$INSTALL_DIR:"* ]] && export PATH="$PATH:$INSTALL_DIR"

# 5. ⚙️ STARTING DATABASE
echo "⚙️  Starting Core Database..."
docker rm -f piper-db 2>/dev/null || true
echo "$COMPOSE_CONFIG" | docker-compose -f - up -d

echo "⏳ Waiting for Database to wake up..."
RETRIES=0
set +e
while true; do
  IS_RUNNING=$(docker ps -q -f name=piper-db)
  if [ -n "$IS_RUNNING" ]; then
    if docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; then
      echo -e "\n✅ Database Ready!"
      break
    fi
  fi
  echo -n "."
  sleep 2
  ((RETRIES++))
  if [ $RETRIES -gt 20 ]; then
    echo -e "\n❌ Timeout."
    exit 1
  fi
done
set -e

# 6. HANDSHAKE
echo "🚀 Running Core Initialization..."
"$INSTALL_DIR/piper" init

echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Online"
echo "------------------------------------------------"