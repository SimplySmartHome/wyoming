#!/bin/bash

# Variables
REPO_URL="https://github.com/rhasspy/wyoming-satellite.git"
SATELLITE_DIR="$HOME/wyoming-satellite"
VENV_DIR="${SATELLITE_DIR}/.venv"
STATE_FILE="$HOME/setup_state.txt"

log_message() {
  zenity --info --text="$1" --width=400 --height=200
}

check_error() {
  if [ $? -ne 0 ]; then
    zenity --error --text="Error: $1" --width=400 --height=200
    exit 1
  fi
}

save_state() {
  echo "$1" > "$STATE_FILE"
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "0"
  fi
}

state=$(load_state)

if [ "$state" -lt "1" ]; then
  log_message "Step 1: Installing Zenity for GUI dialogs..."
  sudo apt-get install -y zenity
  check_error "Failed to install Zenity"
  save_state 1
fi

if [ "$state" -lt "2" ]; then
  SATELLITE_NAME=$(zenity --entry --title="Satellite Name" --text="Enter the satellite name (e.g., my satellite):")
  WAKE_WORD_NAME=$(zenity --list --title="Wake Word Name" --text="Choose the wake word:" --column="Wake Word" "ok_nabu" "hey_jarvis" "alexa" "hey_mycroft" "hey_rhasspy")
  save_state 2

  log_message "Step 2: Updating and upgrading the system..."
  sudo apt-get update && sudo apt-get upgrade -y
  check_error "Failed to update and upgrade the system"
  save_state 3
fi

if [ "$state" -lt "4" ]; then
  log_message "Step 3: Installing required packages..."
  sudo apt-get install --no-install-recommends -y git python3-venv libopenblas-dev python3-spidev python3-gpiozero
  check_error "Failed to install required packages"
  save_state 4
fi

if [ "$state" -lt "5" ]; then
  log_message "Step 4: Cloning the wyoming-satellite repository..."
  git clone $REPO_URL $SATELLITE_DIR
  check_error "Failed to clone the repository"
  save_state 5
fi

if [ "$state" -lt "6" ]; then
  log_message "Step 5: Installing ReSpeaker 2Mic HAT drivers..."
  cd $SATELLITE_DIR
  sudo bash etc/install-respeaker-drivers.sh
  check_error "Failed to install ReSpeaker 2Mic HAT drivers"
  save_state 6
fi

if [ "$state" -lt "7" ]; then
  log_message "Step 6: Rebooting the system to apply changes..."
  save_state 7
  sudo reboot now
fi

if [ "$state" -eq "7" ]; then
  log_message "Reconnecting after reboot..."
  save_state 8  # Move to the next state after reboot
  exit 0  # Exit the script to allow SSH reconnection
fi

if [ "$state" -lt "9" ]; then
  log_message "Step 7: Creating and activating a Python virtual environment..."
  cd $SATELLITE_DIR
  python3 -m venv $VENV_DIR
  check_error "Failed to create Python virtual environment"

  $VENV_DIR/bin/pip install --upgrade pip wheel setuptools
  check_error "Failed to upgrade pip, wheel, and setuptools"

  $VENV_DIR/bin/pip install -f 'https://synesthesiam.github.io/prebuilt-apps/' -r requirements.txt -r requirements_audio_enhancement.txt -r requirements_vad.txt
  check_error "Failed to install Python dependencies"
  save_state 9
fi

if [ "$state" -lt "10" ]; then
  log_message "Step 8: Testing audio devices..."
  log_message "Listing available recording devices:"
  MIC_DEVICES=$(arecord -L)
  check_error "Failed to list audio recording devices"

  MIC_DEVICE=$(echo "$MIC_DEVICES" | zenity --list --title="Select Microphone Device" --column="Devices" --height=400 --width=600)
  check_error "Failed to select microphone device"

  log_message "Listing available playback devices:"
  SND_DEVICES=$(aplay -L)
  check_error "Failed to list audio playback devices"

  SND_DEVICE=$(echo "$SND_DEVICES" | zenity --list --title="Select Speaker Device" --column="Devices" --height=400 --width=600)
  check_error "Failed to select speaker device"

  save_state 10
fi

if [ "$state" -lt "11" ]; then
  log_message "Step 9: Testing recording and playback..."
  zenity --info --text="Press OK to start recording..." --width=400 --height=200
  arecord -D $MIC_DEVICE -r 16000 -c 1 -f S16_LE -t wav -d 5 test.wav
  check_error "Failed to record audio"

  aplay -D $SND_DEVICE test.wav
  check_error "Failed to play back audio"
  save_state 11
fi

if [ "$state" -lt "12" ]; then
  log_message "Step 10: Creating systemd service for wyoming-satellite..."
  sudo bash -c 'cat << EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart='$HOME/wyoming-satellite/script/run --name "'${SATELLITE_NAME}'" --uri "tcp://0.0.0.0:10700" --mic-command "arecord -D '${MIC_DEVICE}' -r 16000 -c 1 -f S16_LE -t raw" --snd-command "aplay -D '${SND_DEVICE}' -r 22050 -c 1 -f S16_LE -t raw"
WorkingDirectory=$HOME/wyoming-satellite
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF'
  check_error "Failed to create wyoming-satellite service"
  save_state 12
fi

if [ "$state" -lt "13" ]; then
  log_message "Step 11: Enabling and starting the wyoming-satellite service..."
  sudo systemctl enable wyoming-satellite.service
  check_error "Failed to enable wyoming-satellite service"

  sudo systemctl start wyoming-satellite.service
  check_error "Failed to start wyoming-satellite service"
  save_state 13
fi

if [ "$state" -lt "14" ]; then
  log_message "Step 12: Installing and configuring openWakeWord..."
  cd ~
  git clone https://github.com/rhasspy/wyoming-openwakeword.git
  check_error "Failed to clone openWakeWord repository"
  save_state 14
fi

if [ "$state" -lt "15" ]; then
  cd wyoming-openwakeword
  script/setup
  check_error "Failed to set up openWakeWord"
  save_state 15
fi

if [ "$state" -lt "16" ]; then
  log_message "Step 13: Creating systemd service for openWakeWord..."
  sudo bash -c 'cat << EOF > /etc/systemd/system/wyoming-openwakeword.service
[Unit]
Description=Wyoming openWakeWord

[Service]
Type=simple
ExecStart='$HOME/wyoming-openwakeword/script/run --uri "tcp://127.0.0.1:10400"
WorkingDirectory=$HOME/wyoming-openwakeword
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF'
  check_error "Failed to create openWakeWord service"
  save_state 16
fi

if [ "$state" -lt "17" ]; then
  log_message "Step 14: Enabling and starting the openWakeWord service..."
  sudo systemctl enable wyoming-openwakeword.service
  check_error "Failed to enable openWakeWord service"

  sudo systemctl start wyoming-openwakeword.service
  check_error "Failed to start openWakeWord service"
  save_state 17
fi

if [ "$state" -lt "18" ]; then
  log_message "Step 15: Updating wyoming-satellite service to include wake word detection..."
  sudo bash -c 'cat << EOF > /etc/systemd/system/wyoming-satellite.service
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target
Requires=wyoming-openwakeword.service

[Service]
Type=simple
ExecStart='$HOME/wyoming-satellite/script/run --name "'${SATELLITE_NAME}'" --uri "tcp://0.0.0.0:10700" --mic-command "arecord -D '${MIC_DEVICE}' -r 16000 -c 1 -f S16_LE -t raw" --snd-command "aplay -D '${SND_DEVICE}' -r 22050 -c 1 -f S16_LE -t raw" --wake-uri "tcp://127.0.0.1:10400" --wake-word-name "'${WAKE_WORD_NAME}'"
WorkingDirectory=$HOME/wyoming-satellite
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF'
  check_error "Failed to update wyoming-satellite service"
  save_state 18
fi

log_message "Step 15: Reloading systemd and restarting the wyoming-satellite service..."
sudo systemctl daemon-reload
check_error "Failed toHere is the complete script with the correct ordering, bug fixes, and a final success message at the end:
log_message "Setup complete! Your Wyoming satellite is now running with wake word detection."
