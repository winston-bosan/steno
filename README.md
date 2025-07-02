# Voice-to-Text Script for Sway

A simple, hotkey-driven voice transcription script designed for the Sway window manager. Captures audio, transcribes via API, and inserts text at cursor position.
Purely for personal use, satisfaction not guaranteed, memory leak is guaranteed.

## Dependencies

1. Install the required dependencies:

```bash
# Ubuntu/Debian
sudo apt install alsa-utils curl wtype libnotify-bin jq

# Arch Linux
sudo pacman -S alsa-utils curl wtype libnotify jq
```

2. **Put your own configuration:**
`cp config.env.example config.env`
then at config.env:

```bash
API_ENDPOINT="http://localhost:8000/transcribe" # Or where-ever your OAI compliant API is at
```

3. **Set up hotkey in Sway:**
Add to your `~/.config/sway/config`:
```
bindsym $mod+Shift+v exec /path/to/steno/voice-to-text.sh
```

## Usage

1. **Start Recording**: Press your configured hotkey
   - Shows "🎤 Recording started..." notification

2. **Stop Recording**: Press the same hotkey again
   - Shows "🔄 Transcribing..." notification
   - Transcribes audio and inserts text at cursor
   - Shows "✅ Text inserted..." confirmation

## I like to live dangerously and have an nvidia GPU > 12.1 CUDA and containers don't scare me (in small dosage)
Fine, here you go:
```bash
git clone https://github.com/your-repo/parakeet-fastapi.git
cd parakeet-fastapi
docker build -t parakeet-stt .
docker run -d -p 8000:8000 --gpus all parakeet-stt

git clone https://github.com/winston-bosan/steno.git
cd steno
chmod +x voice-to-text.sh
./voice-to-text.sh
# SAY YOUR STUFF
./voice-to-text.sh
```
