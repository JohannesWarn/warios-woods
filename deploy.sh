#!/usr/bin/env sh
set -eu

# ---- Script directory ----
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# ---- Config ----
HOST="warn.se"
USER="$(whoami)"
PORT="22"

LOCAL_DIR="$SCRIPT_DIR"
REMOTE_DIR="/home/johannes/warn.se/games/warios-woods/"

# ---- Validate ----
if [ ! -d "$LOCAL_DIR" ]; then
  echo "Local dir not found: $LOCAL_DIR" >&2
  exit 1
fi

# ---- Deploy ----
echo "Uploading '$LOCAL_DIR' -> '$USER@$HOST:$REMOTE_DIR' via SFTP…"

# Ensure remote dir exists
ssh -p "$PORT" "$USER@$HOST" "mkdir -p '$REMOTE_DIR'"

# Upload contents (not the parent folder name)
sftp -P "$PORT" "$USER@$HOST" <<EOF
cd $REMOTE_DIR
put -r $LOCAL_DIR/*
EOF

echo "Done."
