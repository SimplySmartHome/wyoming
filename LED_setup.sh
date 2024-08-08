#!/bin/bash

# Variables
LED_SERVICE_DIR="$HOME/wyoming-satellite/examples"

log_message() {
  echo "====================================================================="
  echo "$1"
  echo "====================================================================="
}

check_error() {
  if [ $? -ne 0 ]; then
    echo "Error: $1"
    exit 1
  fi
}

log_message "Step 1: Navigating to LED service directory..."
cd $LED_SERVICE_DIR
check_error "Failed to navigate to LED service directory"

log_message "Step 2: Setting up Python virtual environment and installing required packages..."
python3 -m venv --system-site-packages .venv && \
.venv/bin/pip3 install --upgrade pip && \
.venv/bin/pip3 install --upgrade wheel setuptools && \
.venv/bin/pip3 install 'wyoming==1.5.2'
check_error "Failed to set up Python virtual environment or install required packages"

log_message "Step 3: Installing required system packages..."
sudo apt-get update && sudo apt-get install -y python3-spidev python3-gpiozero
check_error "Failed to install required system packages"

log_message "Step 4: Creating systemd service for the LED service..."
sudo bash -c "cat << EOF > /etc/systemd/system/2mic_leds.service
[Unit]
Description=2Mic LEDs

[Service]
Type=simple
ExecStart=$LED_SERVICE_DIR/.venv/bin/python3 2mic_service.py --uri 'tcp://127.0.0.1:10500'
WorkingDirectory=$LED_SERVICE_DIR
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF"
check_error "Failed to create systemd service for the LED service"

log_message "Step 5: Enabling and starting the systemd service..."
sudo systemctl enable 2mic_leds.service
check_error "Failed to enable 2mic_leds.service"

sudo systemctl start 2mic_leds.service
check_error "Failed to start 2mic_leds.service"

log_message "Step 6: Updating the Wyoming service to require the LED service..."
sudo sed -i '/\[Unit\]/a Requires=2mic_leds.service' /etc/systemd/system/wyoming-satellite.service
check_error "Failed to update [Unit] section of wyoming-satellite service"

sudo sed -i "s|ExecStart=.*|& --event-uri 'tcp://127.0.0.1:10500'|" /etc/systemd/system/wyoming-satellite.service
check_error "Failed to update ExecStart line of wyoming-satellite service"

log_message "Successfully updated the Wyoming service."

log_message "Step 7: Reloading the systemd daemon..."
sudo systemctl daemon-reload
check_error "Failed to reload the systemd daemon"

log_message "Step 8: Restarting the Wyoming service..."
sudo systemctl restart wyoming-satellite.service
check_error "Failed to restart the Wyoming service"

log_message "Setup complete! LED service and Wyoming service are now running."
