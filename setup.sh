#!/bin/bash
# 🚀 Piper Engine Bootstrap: The Automated Agency Setup
# Location: https://github.com/Philz-Dev/piper-installer/main/setup.sh

set -e # Exit immediately if a command fails

echo "------------------------------------------------"
echo "  PIPER ENGINE: System Initialization Starting  "
echo "------------------------------------------------"

# 1. Environment Check: Create .env if it doesn't exist
if [ ! -f .env ]; then
    echo "📌 No .env file found. Let's configure your database."
    read -p "Enter your PostgreSQL URL (e.g., postgresql://user:pass@localhost:5432/db): " db_url
    echo "DATABASE_URL=$db_url" > .env
    echo "✅ .env created successfully."
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

# 4. Create the Global CLI Wrapper (The "Magic" Link)
echo "🛠️  Installing 'piper' command globally..."

# Create the wrapper locally first to avoid /tmp permission issues
cat <<EOF > ./piper_wrapper
#!/bin/bash
# Wrapper for Piper Engine Docker Container
docker run --rm -it \
  -v \$(pwd):/app \
  --env-file .env \
  ghcr.io/philz-dev/piper-engine:v1 "\$@"
EOF

# Determine the best installation path based on environment
if [ -x "$(command -v sudo)" ]; then
    # Professional Linux Path
    INSTALL_DIR="/usr/local/bin"
    sudo mkdir -p "$INSTALL_DIR"
    sudo mv ./piper_wrapper "$INSTALL_DIR/piper"
    sudo chmod +x "$INSTALL_DIR/piper"
else
    # Windows/MINGW64 Path (User-level, no admin/sudo needed)
    INSTALL_DIR="$HOME/bin"
    mkdir -p "$INSTALL_DIR"
    mv ./piper_wrapper "$INSTALL_DIR/piper"
    chmod +x "$INSTALL_DIR/piper"
    
    # Add to current session path so Step 5 can find it immediately
    export PATH="\$PATH:\$INSTALL_DIR"
fi

echo "✅ Global 'piper' command installed in $INSTALL_DIR."

# 5. The Internal Handshake: Run init
echo "⚙️  Running Internal Core Initialization..."
# Attempt to run via the command name directly
piper init

# 6. Final Launch
if [ -f docker-compose.yml ]; then
    echo "🚀 Launching services with Docker Compose..."
    docker-compose up -d
    echo "------------------------------------------------"
    echo "  SUCCESS: Piper Engine is now running!         "
    echo "  You can now use the global command: piper     "
    echo "------------------------------------------------"
else
    echo "------------------------------------------------"
    echo "✅ Setup finished! 'piper' command is ready.    "
    echo "Try typing: piper --help                        "
    echo "------------------------------------------------"
fi