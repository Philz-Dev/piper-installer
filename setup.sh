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

cat <<EOF > ./piper_wrapper
#!/bin/bash
# Wrapper for Piper Engine Docker Container
docker run --rm -it \
  -v \$(pwd):/app \
  --env-file .env \
  ghcr.io/philz-dev/piper-engine:v1 "\$@"
EOF

# Determine the best installation path based on environment permissions
# We check if we can write to /usr/local/bin OR if we can create it
if [ -w "/usr/local/bin" ] || ([ -x "$(command -v sudo)" ] && sudo mkdir -p /usr/local/bin 2>/dev/null); then
    # Professional Linux Path (or Admin Windows)
    INSTALL_DIR="/usr/local/bin"
    echo "Using system path: $INSTALL_DIR"
    
    # Use sudo only if available
    CMD_PREFIX=""
    if [ -x "$(command -v sudo)" ]; then CMD_PREFIX="sudo "; fi
    
    $CMD_PREFIX mv ./piper_wrapper "$INSTALL_DIR/piper"
    $CMD_PREFIX chmod +x "$INSTALL_DIR/piper"
else
    # Windows/MINGW64 Fallback (User-level folder to avoid Permission Denied)
    INSTALL_DIR="$HOME/piper_bin"
    echo "Permission denied for system path. Using user path: $INSTALL_DIR"
    
    mkdir -p "$INSTALL_DIR"
    mv ./piper_wrapper "$INSTALL_DIR/piper"
    chmod +x "$INSTALL_DIR/piper"
    
    # Add to current session path so Step 5 (piper init) works immediately
    export PATH="$PATH:$INSTALL_DIR"
    
    # Permanently add to Bash profile if not already there
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.bash_profile || echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.bashrc
    fi
fi

echo "✅ Global 'piper' command installed in $INSTALL_DIR."

# 5. The Internal Handshake: Run init
echo "⚙️  Running Internal Core Initialization..."
# Try running via the command name directly; fallback to full path if needed
if command -v piper >/dev/null 2>&1; then
    piper init
else
    "$INSTALL_DIR/piper" init
fi

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