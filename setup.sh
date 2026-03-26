#!/bin/bash
# 🚀 Piper Engine Bootstrap: The Automated Agency Setup
# Updated: Local Database Auto-Provisioning

set -e # Exit immediately if a command fails

echo "------------------------------------------------"
echo "   PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. Environment Check: Database Configuration
if [ ! -f .env ]; then
    echo "📌 Database Configuration"
    echo "1) Use my own existing PostgreSQL (Enter URL)"
    echo "2) Create a new local Database automatically (Recommended)"
    read -p "Select an option [2]: " db_choice
    db_choice=${db_choice:-2}

    if [ "$db_choice" == "1" ]; then
        read -p "Enter your PostgreSQL URL (e.g., postgresql://user:pass@localhost:5432/db): " db_url
        echo "DATABASE_URL=$db_url" > .env
    else
        # Generate a random 12-character hex password for security
        DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_pass_$(date +%s)")
        
        # We use @db:5432 because the CLI wrapper will be inside the docker network
        echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
        
        # Create the local docker-compose for the DB
        cat <<EOF > docker-compose.db.yml
version: '3.8'
services:
  db:
    image: postgres:15
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
        echo "✅ Local Database configuration generated."
        AUTO_DB=true
    fi
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

# 4. Create the Global CLI Wrapper
echo "🛠️  Installing 'piper' command globally..."

# We ensure the network exists before running the wrapper
docker network create piper-global-network 2>/dev/null || true

cat <<EOF > ./piper_wrapper
#!/bin/bash
docker run --rm -it \\
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
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.bashrc
    fi
fi

# 5. The Internal Handshake: Run init
echo "⚙️  Running Internal Core Initialization..."
if [ "$AUTO_DB" = true ]; then
    echo "⏳ Waiting for Database container to wake up..."
    docker-compose -f docker-compose.db.yml up -d
    sleep 5 # Give Postgres a moment to start
fi

"$INSTALL_DIR/piper" init

# 6. Final Launch
echo "------------------------------------------------"
echo "✅ SUCCESS: Piper Engine Setup Complete!"
echo "------------------------------------------------"
if [ "$AUTO_DB" = true ]; then
    echo "📍 LOCAL DB ACCESS (for TablePlus/DBeaver):"
    echo "   Host: localhost"
    echo "   Port: 5432"
    echo "   User: piper_admin"
    echo "   Pass: $DB_PASSWORD"
    echo "------------------------------------------------"
fi
echo "Try typing: piper --help"