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

# Create the wrapper locally first to avoid /tmp permission issues in MINGW64
cat <<EOF > ./piper_wrapper
#!/bin/bash
# Wrapper for Piper Engine Docker Container
docker run --rm -it \
  -v \$(pwd):/app \
  --env-file .env \
  ghcr.io/philz-dev/piper-engine:v1 "\$@"
EOF

# Ensure the destination directory exists and move the wrapper
if [ -x "$(command -v sudo)" ]; then
    sudo mkdir -p /usr/local/bin
    sudo mv ./piper_wrapper /usr/local/bin/piper
    sudo chmod +x /usr/local/bin/piper
else
    # MINGW64 / Windows Fallback
    mkdir -p /usr/local/bin
    mv ./piper_wrapper /usr/local/bin/piper
    chmod +x /usr/local/bin/piper
fi
echo "✅ Global 'piper' command installed."

# 5. The Internal Handshake: Run init
echo "⚙️  Running Internal Core Initialization..."
# Calling via full path to ensure it runs even if PATH hasn't refreshed locally
/usr/local/bin/piper init

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