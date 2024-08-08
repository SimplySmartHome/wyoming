#!/bin/bash

# Variables
REPO_URL="https://github.com/rhasspy/wyoming-openwakeword.git"
WAKEWORD_DIR="$HOME/wyoming-openwakeword"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

check_error() {
  if [ $? -ne 0 ]; then
    log_message "Error: $1"
    exit 1
  fi
}

# Step 1: Installing necessary system dependencies
log_message "Step 1: Installing necessary system dependencies..."
sudo apt-get update && sudo apt-get install --no-install-recommends -y libopenblas-dev
check_error "Failed to install system dependencies"

# Step 2: Cloning the wyoming-openwakeword repository
log_message "Step 2: Cloning the wyoming-openwakeword repository..."
git clone $REPO_URL $WAKEWORD_DIR
check_error "Failed to clone the repository"

# Step 3: Running setup script for wyoming-openwakeword
log_message "Step 3: Running setup script for wyoming-openwakeword..."
cd $WAKEWORD_DIR
script/setup
check_error "Failed to run the setup script"

# Step 4: Creating systemd service for wyoming-openwakeword
log_message "Step 4: Creating systemd service for wyoming-openwakeword..."
sudo bash -c "cat << EOF > /etc/systemd/system/wyoming-openwakeword.service
[Unit]
Description=Wyoming openWakeWord

[Service]
Type=simple
ExecStart=$WAKEWORD_DIR/script/run --uri 'tcp://127.0.0.1:10400'
WorkingDirectory=$WAKEWORD_DIR
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF"
check_error "Failed to create wyoming-openwakeword service"

# Step 5: Prompting user to choose a wake word
log_message "Step 5: Prompting user to choose a wake word..."
echo "Choose the wake word (type the number):"
echo "1) ok_nabu"
echo "2) hey_jarvis"
echo "3) alexa"
echo "4) hey_mycroft"
echo "5) hey_rhasspy"
read -p "Selection: " wake_word_choice

case $wake_word_choice in
  1) WAKE_WORD_NAME="ok_nabu" ;;
  2) WAKE_WORD_NAME="hey_jarvis" ;;
  3) WAKE_WORD_NAME="alexa" ;;
  4) WAKE_WORD_NAME="hey_mycroft" ;;
  5) WAKE_WORD_NAME="hey_rhasspy" ;;
  *) echo "Invalid selection"; exit 1 ;;
esac

# Step 6: Updating wyoming-satellite service to include wakeword detection
log_message "Step 6: Editing wyoming-satellite service to require wyoming-openwakeword service..."

# Add the Requires=wyoming-openwakeword.service under the [Unit] section
sudo sed -i '/\[Unit\]/a Requires=wyoming-openwakeword.service' /etc/systemd/system/wyoming-satellite.service
check_error "Failed to update [Unit] section of wyoming-satellite service"

log_message "Successfully updated [Unit] section to require wyoming-openwakeword service."

# Add the wake URI and wake word name to the ExecStart line
sudo sed -i "s|ExecStart=.*|& --wake-uri 'tcp://127.0.0.1:10400' --wake-word-name '${WAKE_WORD_NAME}'|" /etc/systemd/system/wyoming-satellite.service
check_error "Failed to update ExecStart line of wyoming-satellite service"

log_message "Successfully updated ExecStart line with wake URI and wake word name."

# Step 7: Reloading and restarting systemd services
log_message "Step 7: Reloading systemd daemon..."
sudo systemctl daemon-reload
check_error "Failed to reload systemd daemon"

log_message "Step 7: Restarting wyoming-satellite and wyoming-openwakeword services..."
sudo systemctl restart wyoming-satellite.service wyoming-openwakeword.service
check_error "Failed to restart services"

log_message "Setup complete! Your Wyoming satellite with local wake word detection is now running."
