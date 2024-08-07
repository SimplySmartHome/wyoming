#!/bin/bash

# Variables
REPO_URL="https://github.com/rhasspy/wyoming-satellite.git"
SATELLITE_DIR="/home/pi/wyoming-satellite"
VENV_DIR="${SATELLITE_DIR}/.venv"

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

read -p "Enter the satellite name (e.g., my satellite): " SATELLITE_NAME

log_message "Step 1: Updating and upgrading the system..."
sudo apt-get update && sudo apt-get upgrade -y
check_error "Failed to update and upgrade the system"

log_message "Step 2: Installing required packages..."
sudo apt-get install --no-install-recommends -y git python3-venv libopenblas-dev python3-spidev python3-gpiozero
check_error "Failed to install required packages"

log_message "Step 3: Cloning the wyoming-satellite repository..."
git clone $REPO_URL $SATELLITE_DIR
check_error "Failed to clone the repository"

log_message "Step 4: Installing ReSpeaker 2Mic HAT drivers..."
cd $SATELLITE_DIR
sudo bash etc/install-respeaker-drivers.sh
check_error "Failed to install ReSpeaker 2Mic HAT drivers"

log_message "Step 5: Rebooting the system to apply changes..."
sudo reboot now

# After reboot
sleep 60  # Wait for the system to reboot

log_message "Step 6: Creating and activating a Python virtual environment..."
cd $SATELLITE_DIR
python3 -m venv $VENV_DIR
check_error "Failed to create Python virtual environment"

$VENV_DIR/bin/pip install --upgrade pip wheel setuptools
check_error "Failed to upgrade pip, wheel, and setuptools"

$VENV_DIR/bin/pip install -f 'https://synesthesiam.github.io/prebuilt-apps/' -r requirements.txt -r requirements_audio_enhancement.txt -r requirements_vad.txt
check_error "Failed to install Python dependencies"

log_message "Step 7: Testing audio devices..."
log_message "Listing available recording devices:"
arecord -L
check_error "Failed to list audio recording devices"

read -p "Enter the microphone device to use (e.g., plughw:CARD=seeed2micvoicec,DEV=0): " MIC_DEVICE

log_message "Listing available playback devices:"
aplay -L
check_error "Failed to list audio playback devices"

read -p "Enter the speaker device to use (e.g., plughw:CARD=seeed2micvoicec,DEV=0): " SND_DEVICE

log_message "Step 8: Testing recording and playback..."
arecord -D $MIC_DEVICE -r 16000 -c 1 -f S16_LE -t wav -d 5 test.wav
check_error "Failed to record audio"

aplay -D $SND_DEVICE test.wav
check_error "Failed to play back audio"

log_message "Step 9: Creating systemd service for wyoming-satellite..."
sudo bash -c 'cat << EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart='${SATELLITE_DIR}'/script/run --name "'${SATELLITE_NAME}'" --uri "tcp://0.0.0.0:10700" --mic-command "arecord -D '${MIC_DEVICE}' -r 16000 -c 1 -f S16_LE -t raw" --snd-command "aplay -D '${SND_DEVICE}' -r 22050 -c 1 -f S16_LE -t raw"
WorkingDirectory='${SATELLITE_DIR}'
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF'
check_error "Failed to create wyoming-satellite service"

log_message "Step 10: Enabling and starting the wyoming-satellite service..."
sudo systemctl enable wyoming-satellite.service
check_error "Failed to enable wyoming-satellite service"

sudo systemctl start wyoming-satellite.service
check_error "Failed to start wyoming-satellite service"

log_message "Step 11: Installing and configuring openWakeWord..."
cd ~
git clone https://github.com/rhasspy/wyoming-openwakeword.git
check_error "Failed to clone openWakeWord repository"

cd wyoming-openwakeword
script/setup
check_error "Failed to set up openWakeWord"

log_message "Step 12: Creating systemd service for openWakeWord..."
sudo bash -c 'cat << EOF > /etc/systemd/system/wyoming-openwakeword.service
[Unit]
Description=Wyoming openWakeWord

[Service]
Type=simple
ExecStart=/home/pi/wyoming-openwakeword/script/run --uri "tcp://127.0.0.1:10400"
WorkingDirectory=/home/pi/wyoming-openwakeword
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF'
check_error "Failed to create openWakeWord service"

log_message "Step 13: Enabling and starting the openWakeWord service..."
sudo systemctl enable wyoming-openwakeword.service
check_error "Failed to enable openWakeWord service"

sudo systemctl start wyoming-openwakeword.service
check_error "Failed to start openWakeWord service"

log_message "Step 14: Updating wyoming-satellite service to include wake word detection..."
sudo bash -c 'cat << EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target
Requires=wyoming-openwakeword.service

[Service]
Type=simple
ExecStart='${SATELLITE_DIR}'/script/run --name "'${SATELLITE_NAME}'" --uri "tcp://0.0.0.0:10700" --mic-command "arecord -D '${MIC_DEVICE}' -r 16000 -c 1 -f S16_LE -t raw" --snd-command "aplay -D '${SND_DEVICE}' -r 22050 -c 1 -f S16_LE -t raw" --wake-uri "tcp://127.0.0.1:10400" --wake-word-name "ok_nabu"
WorkingDirectory='${SATELLITE_DIR}'
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF'
check_error "Failed to update wyoming-satellite service"

log_message "Step 15: Reloading systemd and restarting the wyoming-satellite service..."
sudo systemctl daemon-reload
check_error "Failed to reload systemd"

sudo systemctl restart wyoming-satellite.service
check_error "Failed to restart wyoming-satellite service"

log_message "Step 16: Installing and configuring LED service for 2Mic HAT..."
cd ${SATELLITE_DIR}/examples
python3 -m venv --system-site-packages .venv
check_error "Failed to create Python virtual environment for LED service"

.venv/bin/pip install --upgrade pip wheel setuptools
check_error "Failed to upgrade pip, wheel, and setuptools for LED service"

.venv/bin/pip install 'wyoming==1.5.2'
check_error "Failed to install wyoming for LED service"

log_message "Step 17: Creating systemd service for LED control..."
sudo bash -c 'cat << EOF > /etc/systemd/system/2mic_leds.service
[Unit]
Description=2Mic LEDs

[Service]
Type=simple
ExecStart=/home/pi/wyoming-satellite/examples/.venv/bin/python3 2mic_service.py --uri "tcp://127.0.0.1:10500"
WorkingDirectory=/home/pi/wyoming-satellite/examples
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF'
check_error "Failed to create LED control service"

log_message "Step 18: Enabling and starting the LED service..."
sudo systemctl enable 2mic_leds.service
check_error "Failed to enable LED service"

sudo systemctl start 2mic_leds.service
check_error "Failed to start LED service"

log_message "Step 19: Updating wyoming-satellite service to include LED control..."
sudo bash -c 'cat << EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target
Requires=wyoming-openwakeword.service 2mic_leds.service

[Service]
Type=simple
ExecStart='${SATELLITE_DIR}'/script/run --name "'${SATELLITE_NAME}'" --uri "tcp://0.0.0.0:10700" --mic-command "arecord -D '${MIC_DEVICE}' -r 16000 -c 1 -f S16_LE -t raw" --snd-command "aplay -D '${SND_DEVICE}' -r 22050 -c 1 -f S16_LE -t raw" --wake-uri "tcp://127.0.0.1:10400" --wake-word-name "ok_nabu" --event-uri "tcp://127.0.0.1:10500"
WorkingDirectory='
