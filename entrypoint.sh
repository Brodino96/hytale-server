#!/bin/bash
set -e

SERVER_PID=""
VERSION_FILE="/data/.installed-version"

# Graceful shutdown handler
shutdown_handler() {
    echo ""
    echo "=========================================="
    echo "Shutting down Hytale server..."
    echo "=========================================="
    if [ -n "$SERVER_PID" ]; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    # Clean up auth pipe if it exists
    rm -f /tmp/hytale-stdin 2>/dev/null || true
    echo "Server stopped."
    exit 0
}

trap shutdown_handler SIGTERM SIGINT

echo "=========================================="
echo "Hytale Server Docker Container"
echo "=========================================="
echo ""

# Download/Update logic (runs BEFORE validation)
if [ "$UPDATE_ON_STARTUP" = "true" ]; then
    echo "=========================================="
    echo "Checking for updates..."
    echo "=========================================="
    echo ""

    cd /data

    # Download hytale-downloader if not present
    if [ ! -f "/data/hytale-downloader-linux-amd64" ]; then
        echo "Downloading hytale-downloader..."
        curl -sL -o /data/hytale-downloader.zip https://downloader.hytale.com/hytale-downloader.zip
        unzip -o /data/hytale-downloader.zip -d /data
        chmod +x /data/hytale-downloader-linux-amd64
        rm -f /data/hytale-downloader.zip /data/hytale-downloader-windows-amd64.exe 2>/dev/null || true
        echo "hytale-downloader installed."
        echo ""
    fi

    # Get currently installed version
    INSTALLED_VERSION=""
    if [ -f "$VERSION_FILE" ]; then
        INSTALLED_VERSION=$(cat "$VERSION_FILE")
        echo "Installed version: $INSTALLED_VERSION"
    else
        echo "No version installed yet."
    fi

    # If no server files exist, we must download - skip version check
    if [ ! -f "/data/Server/HytaleServer.jar" ]; then
        echo ""
        echo "No server files found. Downloading..."
        echo ""
        echo "If authentication is required, click the link below:"
        echo ""

        ./hytale-downloader-linux-amd64 -patchline "$PATCHLINE" || {
            echo ""
            echo "Download failed. Please attach to the container and authenticate:"
            echo "  docker attach hytale-server"
            echo ""
            exit 1
        }

        # Find the downloaded zip
        DOWNLOAD_ZIP=$(ls -t /data/*.zip 2>/dev/null | grep -E '/[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+\.zip$' | head -1)

        if [ -n "$DOWNLOAD_ZIP" ] && [ -f "$DOWNLOAD_ZIP" ]; then
            LATEST_VERSION=$(basename "$DOWNLOAD_ZIP" .zip)
            echo ""
            echo "Downloaded: $LATEST_VERSION"
            echo ""
            echo "Extracting..."
            unzip -o "$DOWNLOAD_ZIP" -d /data
            echo "$LATEST_VERSION" > "$VERSION_FILE"
            rm -f "$DOWNLOAD_ZIP"
            echo ""
            echo "Installation complete."
            echo ""
        fi
    else
        # Server files exist - check for updates with timeout
        echo "Checking latest version for patchline: $PATCHLINE"

        LATEST_VERSION=$(timeout 10s ./hytale-downloader-linux-amd64 -print-version -patchline "$PATCHLINE" 2>/dev/null || echo "")

        if [ -z "$LATEST_VERSION" ]; then
            echo ""
            echo "Could not determine latest version (auth may be required)."
            echo "Skipping update check. Using existing files."
            echo ""
        elif [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
            echo "Latest version: $LATEST_VERSION"
            echo ""
            echo "Already up to date."
            echo ""
        else
            echo "Latest version: $LATEST_VERSION"
            echo ""
            if [ -z "$INSTALLED_VERSION" ]; then
                echo "Recording current version..."
                echo "$LATEST_VERSION" > "$VERSION_FILE"
                echo ""
            else
                echo "Updating from $INSTALLED_VERSION to $LATEST_VERSION..."
                echo ""
                echo "If authentication is required, click the link below:"
                echo ""

                ./hytale-downloader-linux-amd64 -patchline "$PATCHLINE" || {
                    echo ""
                    echo "WARNING: Download failed. Continuing with existing files..."
                    echo ""
                }

                # Find the downloaded zip
                DOWNLOAD_ZIP=$(ls -t /data/*.zip 2>/dev/null | grep -E '/[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+\.zip$' | head -1)

                if [ -n "$DOWNLOAD_ZIP" ] && [ -f "$DOWNLOAD_ZIP" ]; then
                    echo ""
                    echo "Downloaded: $(basename "$DOWNLOAD_ZIP")"
                    echo ""

                    # Create backups of server binaries (not user data)
                    echo "Creating backups..."
                    rm -rf /data/Server.bak
                    cp -r /data/Server /data/Server.bak
                    echo "  - Server/ -> Server.bak/"

                    if [ -f "/data/Assets.zip" ]; then
                        rm -f /data/Assets.zip.bak
                        cp /data/Assets.zip /data/Assets.zip.bak
                        echo "  - Assets.zip -> Assets.zip.bak"
                    fi
                    echo ""

                    # Extract new files
                    echo "Extracting..."
                    unzip -o "$DOWNLOAD_ZIP" -d /data

                    # Save installed version
                    echo "$LATEST_VERSION" > "$VERSION_FILE"

                    # Clean up downloaded zip
                    rm -f "$DOWNLOAD_ZIP"

                    echo ""
                    echo "Update complete. User data preserved:"
                    echo "  - universe/ (world data)"
                    echo "  - config.json (server settings)"
                    echo "  - auth.enc (authentication)"
                    echo "  - bans.json, whitelist.json, permissions.json"
                    echo "  - mods/ (user mods)"
                    echo "  - logs/ (server logs)"
                    echo ""
                fi
            fi
        fi
    fi
fi

# Validation (runs AFTER potential download)
if [ ! -f "/data/Server/HytaleServer.jar" ]; then
    echo "ERROR: Server/HytaleServer.jar not found in /data"
    echo ""
    echo "Please ensure your data directory contains:"
    echo "  - Server/HytaleServer.jar"
    echo "  - Assets.zip"
    echo ""
    echo "Option 1: Enable auto-download"
    echo "  Set UPDATE_ON_STARTUP=true in your docker-compose.yml"
    echo ""
    echo "Option 2: Manual setup"
    echo "  1. Download hytale-downloader from https://downloader.hytale.com/hytale-downloader.zip"
    echo "  2. Extract and run the downloader"
    echo "  3. Authenticate via the provided link"
    echo "  4. Extract the downloaded game zip"
    echo "  5. Copy Server/ and Assets.zip to your data directory"
    echo ""
    exit 1
fi

if [ ! -f "/data/Assets.zip" ]; then
    echo "ERROR: Assets.zip not found in /data"
    echo ""
    echo "Please ensure your data directory contains:"
    echo "  - Server/HytaleServer.jar"
    echo "  - Assets.zip"
    echo ""
    exit 1
fi

echo "Server files found."
echo ""

# Start server
echo "=========================================="
echo "Starting Hytale Server"
echo "=========================================="
echo ""
echo "Java options: $JAVA_OPTS"
echo ""

cd /data

AUTH_FILE="/data/auth.enc"
AUTH_STATE_DIR="/tmp/hytale-auth-state"

# Clean up function
cleanup_auth() {
    rm -f /tmp/hytale-commands
    rm -rf "$AUTH_STATE_DIR"
}

if [ ! -f "$AUTH_FILE" ]; then
    # No auth.enc found - need to run automatic authentication
    echo "No authentication credentials found (auth.enc missing)"
    echo ""
    echo "Starting automatic authentication flow..."
    echo "When the URL appears below, open it in your browser"
    echo "to complete authentication."
    echo ""
    echo "=========================================="
    echo ""

    # Set up state tracking directory
    rm -rf "$AUTH_STATE_DIR"
    mkdir -p "$AUTH_STATE_DIR"
    trap cleanup_auth EXIT

    # Create a file that we'll use to send commands to the server
    # Using tail -f on this file will keep stdin open and allow us to append commands
    CMD_FILE="/tmp/hytale-commands"
    rm -f "$CMD_FILE"
    touch "$CMD_FILE"

    # Start server with stdin from tail -f (which follows the command file)
    tail -f "$CMD_FILE" | java $JAVA_OPTS -jar Server/HytaleServer.jar --assets Assets.zip  $SERVER_ARGS 2>&1 | while IFS= read -r line; do
        # Print the line (preserve server output)
        echo "$line"

        # Check if we need to send auth login device command
        if [ ! -f "$AUTH_STATE_DIR/auth_sent" ] && echo "$line" | grep -q "Auth credential store: Memory"; then
            touch "$AUTH_STATE_DIR/auth_sent"
            # Small delay to ensure server console is ready
            (
                sleep 2
                echo ""
                echo "=========================================="
                echo "Initiating device authentication..."
                echo "=========================================="
                echo ""
                echo "auth login device" >> "$CMD_FILE"
            ) &
        fi

        # Check if authentication was successful
        if [ ! -f "$AUTH_STATE_DIR/persist_sent" ] && echo "$line" | grep -q "Authentication successful!"; then
            touch "$AUTH_STATE_DIR/persist_sent"
            # Small delay before sending persistence command
            (
                sleep 1
                echo ""
                echo "=========================================="
                echo "Authentication successful!"
                echo "Persisting credentials..."
                echo "=========================================="
                echo ""
                echo "auth persistence Encrypted" >> "$CMD_FILE"
            ) &
        fi

        # Check if persistence was successful
        if echo "$line" | grep -q "Swapped credential store to:"; then
            echo ""
            echo "=========================================="
            echo "Credentials saved to auth.enc"
            echo "Future restarts will auto-authenticate."
            echo "=========================================="
            echo ""
        fi
    done &
    SERVER_PID=$!
    wait $SERVER_PID

    # Clean up
    rm -f "$CMD_FILE"
else
    # auth.enc exists - normal startup
    echo "Authentication credentials found (auth.enc)"
    echo ""
    echo "To detach from this console without stopping"
    echo "the server, press: Ctrl+P, Ctrl+Q"
    echo ""
    echo "=========================================="
    echo ""

    exec java $JAVA_OPTS -jar Server/HytaleServer.jar --assets Assets.zip $SERVER_ARGS
fi
