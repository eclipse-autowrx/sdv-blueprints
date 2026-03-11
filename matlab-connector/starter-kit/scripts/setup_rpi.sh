#!/bin/bash

# setup.sh - Script to setup Python environment for digital.auto
# This script checks for Python installation, creates a virtual environment,
# and installs required dependencies.

set -e  # Exit on error

DIGITAL_AUTO_DIR="digital.auto"
VENV_NAME=".venv_da"

# Get home directory
HOME_DIR="${HOME:-$(eval echo ~$(whoami))}"

# Construct paths
DIGITAL_AUTO_PATH="$HOME_DIR/$DIGITAL_AUTO_DIR"
VENV_PATH="$DIGITAL_AUTO_PATH/$VENV_NAME"

echo "Starting Python environment setup..."

# Check if Docker is installed
if command -v docker &> /dev/null; then
    echo "Docker is already installed."
    docker --version
else
    echo "Docker not found. Installing Docker..."
    
    # Update package list
    echo "Updating package list..."
    sudo apt-get update
    
    # Install prerequisites
    echo "Installing prerequisites..."
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Detect OS
    . /etc/os-release
    OS_ID=$ID
    
    # Add Docker's official GPG key
    echo "Adding Docker's GPG key..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    echo "Installing Docker Engine..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Verify installation
    if command -v docker &> /dev/null; then
        echo "Docker installation successful."
        docker --version
        
        # Add current user to docker group to run docker without sudo
        echo "Adding current user to docker group..."
        sudo usermod -aG docker $USER
        echo "Note: You may need to log out and back in for docker group changes to take effect."
    else
        echo "ERROR: Docker installation failed." >&2
        exit 1
    fi
fi

echo "Docker install complete!"

# Pull the required Docker image if it doesn't exist
IMAGE_NAME="ghcr.io/eclipse-autowrx/sdv-runtime:latest"
if docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo "Docker image $IMAGE_NAME already exists locally."
else
    echo "Pulling Docker image $IMAGE_NAME..."
    if docker pull "$IMAGE_NAME"; then
        echo "Docker image pulled successfully."
    else
        echo "ERROR: Failed to pull Docker image." >&2
        exit 1
    fi
fi

# Check if Python 3 is installed
if command -v python3 &> /dev/null; then
    echo "Python is already installed."
    python3 --version
    
    # Check if pip3 is installed
    if command -v pip3 &> /dev/null; then
        echo "pip is already installed."
        pip3 --version
    else
        echo "pip3 not found. Installing pip3..."
        sudo apt-get update
        sudo apt-get install -y python3-pip
        echo "pip3 installation complete."
    fi
else
    echo "Python 3 not found. Installing Python 3..."
    
    # Update package list
    echo "Updating package list..."
    sudo apt-get update
    
    # Install Python 3 and pip
    echo "Installing Python 3 and pip..."
    sudo apt-get install -y python3 python3-pip
    
    # Verify installation
    if command -v python3 &> /dev/null; then
        echo "Python installation successful."
        python3 --version
        
        if command -v pip3 &> /dev/null; then
            echo "pip installation successful."
            pip3 --version
        fi
    else
        echo "ERROR: Python installation failed." >&2
        exit 1
    fi
fi

echo "Python install complete!"

# Create digital.auto directory if it doesn't exist
if [ ! -d "$DIGITAL_AUTO_PATH" ]; then
    echo "Creating directory: $DIGITAL_AUTO_PATH"
    mkdir -p "$DIGITAL_AUTO_PATH"
fi

# Create virtual environment if it doesn't exist
if [ -d "$VENV_PATH" ]; then
    echo "Virtual environment already exists at $VENV_PATH"
else
    echo "Creating virtual environment at $VENV_PATH..."
    python3 -m venv "$VENV_PATH"
    
    if [ -d "$VENV_PATH" ]; then
        echo "Virtual environment created successfully at $VENV_PATH"
        echo "To activate it, run: source $VENV_PATH/bin/activate"
    else
        echo "ERROR: Failed to create virtual environment." >&2
        exit 1
    fi
fi

# Install required Python packages in the virtual environment
echo "Installing Python dependencies..."
"$VENV_PATH/bin/pip" install kuksa-client

if [ $? -eq 0 ]; then
    echo "Python dependencies installed successfully."
else
    echo "WARNING: Failed to install kuksa-client package." >&2
    # Don't exit with error, as package might already be installed
fi

# Launching Docker container
echo "Launching Docker container..."
docker run -d -e RUNTIME_NAME="RpiMotorControl" -p 55555:55555 ghcr.io/eclipse-autowrx/sdv-runtime:latest

if [ $? -eq 0 ]; then
    echo "Docker container launched successfully."
else
    echo "ERROR: Failed to launch Docker container." >&2
    exit 1
fi

# Wait for KUKSA service to be ready and accepting connections on port 55555
echo "Waiting for KUKSA service to be ready on port 55555..."
WAIT_TIME=0
MAX_WAIT=60

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if nc -z 127.0.0.1 55555 2>/dev/null || timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/55555" 2>/dev/null; then
        echo "KUKSA service is ready and accepting connections."
        sleep 2  # Give it a couple more seconds to be fully initialized
        break
    fi
    sleep 3
    WAIT_TIME=$((WAIT_TIME + 3))
    echo "Waiting for service... ($WAIT_TIME seconds elapsed)"
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo "ERROR: KUKSA service did not become ready after ${MAX_WAIT} seconds." >&2
    exit 1
fi

# Launch uds_publisher.py script in the virtual environment
PUBLISHER_SCRIPT="$DIGITAL_AUTO_PATH/scripts/uds_publisher.py"

if [ -f "$PUBLISHER_SCRIPT" ]; then
    echo "Launching uds_publisher.py in virtual environment..."
    "$VENV_PATH/bin/python" "$PUBLISHER_SCRIPT" &
    
    if [ $? -eq 0 ]; then
        echo "uds_publisher.py launched successfully."
    else
        echo "ERROR: Failed to launch uds_publisher.py." >&2
        exit 1
    fi
else
    echo "WARNING: uds_publisher.py not found at $PUBLISHER_SCRIPT" >&2
fi

echo "Setup complete!"
exit 0
