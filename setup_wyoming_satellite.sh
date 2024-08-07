#!/bin/bash

# Variables
REPO_URL="https://github.com/rhasspy/wyoming-satellite.git"
SATELLITE_DIR="$HOME/wyoming-satellite"
STATE_FILE="$HOME/setup_state.txt"

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

save_state() {
  echo "$1" > "$STATE_FILE"
}

save_variables() {
  echo "state=${state}" > "$STATE_FILE"
  echo "SATELLITE_NAME=${SATELLITE_NAME}" >> "$STATE_FILE"
  echo "WAKE_WORD_NAME=${WAKE_WORD_NAME}" >> "$STATE_FILE"
  echo "MIC_DEVICE=${MIC_DEVICE}" >> "$STATE_FILE"
  echo "SND_DEVICE=${SND_DEVICE}" >> "$STATE_FILE"
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
  else
    state="0"
  fi
}

load_state

if [ "$state" -eq "5" ]; then
  log_message "Reconnecting after reboot..."
  state=6  # Move to the next state after reboot
  save_state $state
fi

if [ "$state" -lt "1" ]; then
  read -p "Enter the satellite name (e.g., my satellite): " SATELLITE_NAME
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
  state=1
  save_variables
fi

if [ "$state" -lt "2" ]; then
  log_message "Step 1: Installing required packages..."
  sudo apt-get update && sudo apt-get install -y git python3-venv libopenblas-dev python3-spidev python3-gpiozero
  check_error "Failed to install required packages"
  state=2
  save_state $state
fi

if [ "$state" -lt "3" ]; then
  log_message "Step 2: Cloning the wyoming-satellite repository..."
  git clone $REPO_URL $SATELLITE_DIR
  check_error "Failed to clone the repository"
  state=3
  save_state $state
fi

if [ "$state" -lt "4" ]; then
  log_message "Step 3: Installing ReSpeaker 2Mic HAT drivers..."
  cd $SATELLITE_DIR
  sudo bash etc/install-respeaker-drivers.sh
  check_error "Failed to install ReSpeaker 2Mic HAT drivers"
  state=4
  save_state $state
fi

if [ "$state" -lt "5" ]; then
  log_message "Step 4: Rebooting the system to apply changes..."
  state=5
  save_state $state
  log_message "System will reboot in 5 seconds..."
  sleep 5
  sudo reboot now
fi

if [ "$state" -eq "6" ]; then
  log_message "Reconnecting after reboot..."
  state=7  # Move to the next state after reboot
  save_state $state
fi

if [ "$state" -lt "7" ]; then
  log_message "Step 5: Creating and activating a Python virtual environment..."
  cd $SATELLITE_DIR
  python3 -m venv .venv
  check_error "Failed to create Python virtual environment"

  .venv/bin/pip3 install --upgrade pip
  check_error "Failed to upgrade pip"

  .venv/bin/pip3 install --upgrade wheel setuptools
  check_error "Failed to upgrade wheel and setuptools"

  .venv/bin/pip3 install -f 'https://synesthesiam.github.io/prebuilt-apps/' -r requirements.txt -r requirements_audio_enhancement.txt -r requirements_vad.txt
  check_error "Failed to install Python dependencies"
  state=7
  save_state $state
fi

if [ "$state" -lt "8" ]; then
  log_message "Step 6: Testing audio devices..."
  log_message "Listing available recording devices:"
  arecord -L
  check_error "Failed to list audio recording devices"
  read -p "Enter the microphone device (e.g., plughw:CARD=seeed2micvoicec,DEV=0): " MIC_DEVICE

  log_message "Listing available playback devices:"
  aplay -L
  check_error "Failed to list audio playback devices"
  read -p "Enter the speaker device (e.g., plughw:CARD=seeed2micvoicec,DEV=0): " SND_DEVICE

  state=8
  save_variables
fi

if [ "$state" -lt "9" ]; then
  log_message "Step 7: Testing recording and playback..."
  read -p "Press Enter to start recording..."
  arecord -D $MIC_DEVICE -r 16000 -c 1 -f S16_LE -t wav -d 5 test.wav
  check_error "Failed to record audio"

  aplay -D $SND_DEVICE test.wav
  check_error "Failed to play back audio"
  state=9
  save_state $state
fi

if [ "$state" -lt "10" ]; then
  log_message "Step 8: Creating systemd service for wyoming-satellite..."
  sudo bash -c "cat << EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=$SATELLITE_DIR/script/run --name \"${SATELLITE_NAME}\" --uri \"tcp://0.0.0.0:10700\" --mic-command \"arecord -D '${MIC_DEVICE}' -r 16000 -c 1 -f S16_LE -t raw\" --snd-command \"aplay -D '${SND_DEVICE}' -r 22050 -c 1 -f S16_LE -t raw\" --mic-auto-gain 5 --mic-noise-suppression 2
WorkingDirectory=$SATELLITE_DIR
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF"
  check_error "Failed to create wyoming-satellite service"
  state=10
  save_state $state
fi

if [ "$state" -lt "11" ]; then
  log_message "Step 9: Enabling and starting the wyoming-satellite service..."
  sudo systemctl enable wyoming-satellite.service
  check_error "Failed to enable wyoming-satellite service"

  sudo systemctl start wyoming-satellite.service
  check_error "Failed to start wyoming-satellite service"
  log_message "Checking wyoming-satellite service logs..."
  sudo journalctl -u wyoming-satellite.service -f
  state=11
  save_state $state
fi

log_message "Setup complete! Your Wyoming satellite is now running."
