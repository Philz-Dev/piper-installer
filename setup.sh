#!/bin/bash
# 🚀 Piper Engine Bootstrap: The Automated Agency Setup
# Updated: Windows TTY (winpty) Support & Local DB Auto-Provisioning

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
        DB_PASSWORD=$(openssl rand -hex 12 2>/dev/null || echo "piper_pass_$(date +%s)")
        echo "DATABASE_URL=postgresql://piper_admin:$DB_PASSWORD@db:5432/piper_data" > .env
        
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
    # Update profile to persist the path
    SHELL_PROFILE="$HOME/.bashrc"
    [ -f "$HOME/.bash_profile" ] && SHELL_PROFILE="$HOME/.bash_profile"
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$SHELL_PROFILE"
    fi
fi

echo "✅ Global 'piper' command installed in $INSTALL_DIR."

# 5. The Internal Handshake: Run init
echo "⚙️  Running Internal Core Initialization..."
if [ "$AUTO_DB" = true ]; then
    echo "⏳ Waiting for Database container to wake up..."
    docker-compose -f docker-compose.db.yml up -d
    sleep 5 
fi

# Using absolute path to bypass any PATH refresh issues in current session
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