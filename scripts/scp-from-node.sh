#!/bin/bash
set -eu
SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY:-}
SSH_USERNAME=${SSH_USERNAME:-}
SSH_HOST=${SSH_HOST:-}
SSH_PORT=${SSH_PORT:-}

TARGET=${TARGET:-}

mkdir -p "${TARGET}"

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "${SSH_PRIVATE_KEY}" \
    -P "${SSH_PORT}" \
    "${SSH_USERNAME}@${SSH_HOST}:$REMOTE_FILE_PATH" \
    "${TARGET}"