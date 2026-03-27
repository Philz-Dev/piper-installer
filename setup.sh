#!/bin/bash
# 🚀 Piper Engine Bootstrap: High-Speed Provisioning
set -e 

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
networks:
  piper-network:
    name: piper-network
EOF
)

# 2. 🧹 THE CLEANUP FIX
echo "🧹 Cleaning up old networks and containers..."
docker rm -f piper-db piper_db piper_core 2>/dev/null || true
# This removes the problematic network so Compose can recreate it correctly
docker network rm piper-network 2>/dev/null || true

# 3. Pulling Engine
docker pull ghcr.io/philz-dev/piper-engine:v1

# 4. Global Command Setup
cat <<'EOF' > ./piper_wrapper
#!/bin/bash
USE_TTY="-it"
FINAL_BIN="docker"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    [ -t 0 ] && FINAL_BIN="winpty docker" || { FINAL_BIN="docker"; USE_TTY="-i"; }
else
    FINAL_BIN="docker"
fi

$FINAL_BIN run --rm $USE_TTY \
  -v "/$(pwd):/app" \
  --network piper-network \
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
echo "$COMPOSE_CONFIG" | docker-compose -f - up -d --remove-orphans

echo "⏳ Waiting for Database..."
until docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; do
  echo -n "."
  sleep 2
done

# 6. HANDSHAKE
echo -e "\n🚀 Running Core Initialization..."
"$INSTALL_DIR/piper" init

echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Online"
echo "------------------------------------------------"