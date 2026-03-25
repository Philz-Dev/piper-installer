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
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    echo "✅ Docker installed."
else
    echo "✅ Docker is already installed."
fi

# 3. Pull the Engine
echo "🚚 Pulling the latest Piper Engine image..."
docker pull ghcr.io/philz-dev/piper-engine:v1

# 4. Create the Global CLI Wrapper (The "Magic" Link)
echo "🛠️  Installing 'piper' command globally..."
cat <<EOF > /tmp/piper
#!/bin/bash
# Wrapper for Piper Engine Docker Container
docker run --rm -it \
  -v \$(pwd):/app \
  --env-file .env \
  ghcr.io/philz-dev/piper-engine:v1 "\$@"
EOF

sudo mv /tmp/piper /usr/local/bin/piper
sudo chmod +x /usr/local/bin/piper
echo "✅ Global 'piper' command installed."

# 5. The Internal Handshake: Run init
echo "⚙️  Running Internal Core Initialization..."
# Note: We call 'init' directly because the Dockerfile ENTRYPOINT handles the python script
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