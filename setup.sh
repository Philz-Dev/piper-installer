#!/bin/bash
# 🚀 Piper Engine Bootstrap: High-Speed Provisioning
set -e 

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. ⚡ CREDENTIALS ⚡
# We will force the .env to use 'db' to match the internal alias
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
        # 🚀 THIS IS THE KEY: It gives the container the nickname "db"
        aliases:
          - db
networks:
  piper-network:
    name: piper-network
EOF
)

# 2. Network Prep
docker network create piper-network 2>/dev/null || true

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

# Run the container on the same network
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
docker rm -f piper-db 2>/dev/null || true
echo "$COMPOSE_CONFIG" | docker-compose -f - up -d --remove-orphans

echo "⏳ Waiting for Database..."
until docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; do
  echo -n "."
  sleep 2
done

# 6. HANDSHAKE
echo -e "\n🚀 Running Core Initialization..."
# Use the full path to ensure we use the wrapper we just made
"$INSTALL_DIR/piper" init

echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Online"
echo "------------------------------------------------"