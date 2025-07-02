#!/bin/bash

# ABOUTME: Voice-to-text script for Sway with hotkey toggle functionality
# ABOUTME: Captures audio, transcribes via API, and inserts text at cursor

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
TEMP_DIR="${TMPDIR:-/tmp}"
AUDIO_FILE="${TEMP_DIR}/voice_input.wav"
PID_FILE="${TEMP_DIR}/voice_recording.pid"
NOTIFICATION_ID_FILE="${TEMP_DIR}/voice_notification.id"

# Default configuration
API_ENDPOINT="${API_ENDPOINT:-}"
API_KEY="${API_KEY:-}"
API_TIMEOUT="${API_TIMEOUT:-30}"
SAMPLE_RATE="${SAMPLE_RATE:-16000}"
AUDIO_FORMAT="${AUDIO_FORMAT:-wav}"
INCLUDE_TIMESTAMPS="${INCLUDE_TIMESTAMPS:-false}"
SHOULD_CHUNK="${SHOULD_CHUNK:-true}"

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Function to show notification
show_notification() {
    local message="$1"
    local urgency="${2:-normal}"
    local timeout="${3:-0}"
    
    local notification_id
    notification_id=$(notify-send \
        --urgency="$urgency" \
        --expire-time="$timeout" \
        --print-id \
        "Voice-to-Text" \
        "$message" 2>/dev/null || echo "0")
    
    echo "$notification_id" > "$NOTIFICATION_ID_FILE"
}

# Function to update notification
update_notification() {
    local message="$1"
    local urgency="${2:-normal}"
    
    if [[ -f "$NOTIFICATION_ID_FILE" ]]; then
        local notification_id
        notification_id=$(cat "$NOTIFICATION_ID_FILE")
        
        if [[ "$notification_id" != "0" ]]; then
            notify-send \
                --urgency="$urgency" \
                --replace-id="$notification_id" \
                "Voice-to-Text" \
                "$message" 2>/dev/null || true
        else
            show_notification "$message" "$urgency"
        fi
    else
        show_notification "$message" "$urgency"
    fi
}

# Function to dismiss notification
dismiss_notification() {
    if [[ -f "$NOTIFICATION_ID_FILE" ]]; then
        rm -f "$NOTIFICATION_ID_FILE"
    fi
}

# Function to clean up temporary files
cleanup() {
    [[ -f "$AUDIO_FILE" ]] && rm -f "$AUDIO_FILE"
    # Don't remove PID file on exit - only when explicitly stopping
}

# Function to handle errors
handle_error() {
    local message="$1"
    echo "Error: $message" >&2
    show_notification "Error: $message" "critical" 5000
    cleanup
    exit 1
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    command -v arecord >/dev/null 2>&1 || missing_deps+=("arecord")
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    command -v wtype >/dev/null 2>&1 || missing_deps+=("wtype")
    command -v notify-send >/dev/null 2>&1 || missing_deps+=("notify-send")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        handle_error "Missing dependencies: ${missing_deps[*]}"
    fi
}

# Function to start recording
start_recording() {
    if [[ -f "$PID_FILE" ]]; then
        handle_error "Recording already in progress"
    fi
    
    show_notification "🎤 Recording started..." "normal"
    
    # Start recording in background
    arecord -f cd -t "$AUDIO_FORMAT" -r "$SAMPLE_RATE" "$AUDIO_FILE" &
    local arecord_pid=$!
    
    # Save PID for later termination
    echo "$arecord_pid" > "$PID_FILE"
    
    echo "Recording started with PID: $arecord_pid"
}

# Function to stop recording
stop_recording() {
    if [[ ! -f "$PID_FILE" ]]; then
        handle_error "No recording in progress"
    fi
    
    local arecord_pid
    arecord_pid=$(cat "$PID_FILE")
    
    # Stop recording
    if kill -TERM "$arecord_pid" 2>/dev/null; then
        wait "$arecord_pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        
        # Give arecord a moment to finish writing the file
        sleep 0.5
        
        update_notification "🔄 Transcribing..." "normal"
        echo "Recording stopped, starting transcription..."
        
        # Process the recording
        transcribe_and_insert
    else
        handle_error "Failed to stop recording process"
    fi
}

# Function to transcribe audio and insert text
transcribe_and_insert() {
    if [[ ! -f "$AUDIO_FILE" ]]; then
        handle_error "Audio file not found: $AUDIO_FILE"
    fi
    
    # Check if audio file has content
    if [[ ! -s "$AUDIO_FILE" ]]; then
        handle_error "Audio file is empty: $AUDIO_FILE"
    fi
    
    if [[ -z "$API_ENDPOINT" ]]; then
        handle_error "API endpoint not configured"
    fi
    
    # Prepare curl command
    local curl_cmd=(
        curl
        -s
        -X POST
        --max-time "$API_TIMEOUT"
        -H "Content-Type: multipart/form-data"
    )
    
    # Add API key if provided
    if [[ -n "$API_KEY" ]]; then
        curl_cmd+=(-H "Authorization: Bearer $API_KEY")
    fi
    
    # Add file and optional parameters for Parakeet-TDT
    curl_cmd+=(-F "file=@$AUDIO_FILE")
    
    # Add Parakeet-TDT specific parameters if they're set
    if [[ "$INCLUDE_TIMESTAMPS" == "true" ]]; then
        curl_cmd+=(-F "include_timestamps=true")
    fi
    
    if [[ "$SHOULD_CHUNK" == "true" ]]; then
        curl_cmd+=(-F "should_chunk=true")
    fi
    
    # Add endpoint last
    curl_cmd+=("$API_ENDPOINT")
    
    # Make API request
    local response
    if ! response=$("${curl_cmd[@]}" 2>/dev/null); then
        handle_error "Failed to connect to transcription API"
    fi
    
    # Extract text from response (handles both Parakeet-TDT and OpenAI formats)
    local transcribed_text
    if command -v jq >/dev/null 2>&1; then
        transcribed_text=$(echo "$response" | jq -r '.text // .transcript // empty' 2>/dev/null || echo "")
    else
        # Fallback: try to extract text manually if jq is not available
        transcribed_text=$(echo "$response" | grep -o '"text"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
    fi
    
    if [[ -z "$transcribed_text" ]] || [[ "$transcribed_text" == "null" ]]; then
        handle_error "No text received from API"
    fi
    
    # Insert text at cursor
    if ! wtype "$transcribed_text" 2>/dev/null; then
        handle_error "Failed to insert text"
    fi
    
    update_notification "✅ Text inserted: ${transcribed_text:0:50}..." "normal"
    
    echo "Transcription successful: $transcribed_text"
    
    # Clean up
    cleanup
    
    # Auto-dismiss notification after 3 seconds
    sleep 3
    dismiss_notification &
}

# Function to check if recording is active
is_recording() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
}

# Main function
main() {
    # Set up trap for cleanup
    trap cleanup EXIT
    
    # Check dependencies
    check_dependencies
    
    # Toggle recording based on current state
    if is_recording; then
        stop_recording
    else
        start_recording
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi