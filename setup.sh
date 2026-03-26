#!/bin/bash
# 🚀 Piper Engine Bootstrap: High-Speed Provisioning
# Architecture: RAM-only Config + Aggressive Health Check

set -e 

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. ⚡ CREDENTIALS & RAM CONFIG ⚡
if [ -f .env ]; then
    DB_PASSWORD=$(grep DATABASE_URL .env | sed 's/.*:\(.*\)@.*/\1/')
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
      - piper-global-network
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

# 4. Global Command Setup
DOCKER_BIN="docker"
[[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] && DOCKER_BIN="winpty docker"

cat <<EOF > ./piper_wrapper
#!/bin/bash
$DOCKER_BIN run --rm -it -v "/\$(pwd):/app" --network piper-global-network --env-file .env ghcr.io/philz-dev/piper-engine:v1 "\$@"
EOF

# Install to path (Hidden logic)
INSTALL_DIR="/usr/local/bin"
[ ! -w "$INSTALL_DIR" ] && INSTALL_DIR="$HOME/piper_bin"
mkdir -p "$INSTALL_DIR"
mv ./piper_wrapper "$INSTALL_DIR/piper"
chmod +x "$INSTALL_DIR/piper"
[[ ":$PATH:" != *":$INSTALL_DIR:"* ]] && export PATH="$PATH:$INSTALL_DIR"

# 5. ⚙️ STARTING DATABASE (RAM ONLY)
echo "⚙️  Starting Core Database..."
docker rm -f piper-db 2>/dev/null || true

# Pipe RAM config to Docker
echo "$COMPOSE_CONFIG" | docker-compose -f - up -d

echo "⏳ Waiting for Database to wake up..."
RETRIES=0
set +e
while true; do
  # Check if container is actually running
  IS_RUNNING=$(docker ps -q -f name=piper-db)
  
  if [ -n "$IS_RUNNING" ]; then
    # Check if Postgres is accepting connections
    if docker exec piper-db pg_isready -U piper_admin >/dev/null 2>&1; then
      echo -e "\n✅ Database Ready!"
      break
    fi
  fi

  echo -n "."
  sleep 2
  ((RETRIES++))
  
  if [ $RETRIES -gt 20 ]; then
    echo -e "\n❌ Timeout. Printing logs for diagnosis:"
    docker logs piper-db --tail 10
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