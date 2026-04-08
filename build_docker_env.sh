#!/bin/bash

set -e

DOCKER_IMAGE_NAME="streambox-builder"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_BUILD=false

# Parse arguments
while getopts ":f" opt; do
  case ${opt} in
    f )
      FORCE_BUILD=true
      ;;
    \? )
      echo "Usage: $0 [-f]"
      echo "  -f  Force rebuild the Docker image"
      exit 1
      ;;
  esac
done

# Check if image exists
IMAGE_EXISTS=$(docker images -q "${DOCKER_IMAGE_NAME}" 2>/dev/null || true)

if [ "$FORCE_BUILD" = true ] || [ -z "$IMAGE_EXISTS" ]; then
  echo "Building Docker image '${DOCKER_IMAGE_NAME}'..."
  if [ "$FORCE_BUILD" = true ] && [ -n "$IMAGE_EXISTS" ]; then
    echo "Force flag detected, rebuilding..."
    docker build --no-cache -t "${DOCKER_IMAGE_NAME}" "${SCRIPT_DIR}"
  else
    docker build -t "${DOCKER_IMAGE_NAME}" "${SCRIPT_DIR}"
  fi
  echo "Docker image built successfully."
else
  echo "Docker image '${DOCKER_IMAGE_NAME}' already exists. Skipping build."
  echo "Use -f flag to force rebuild."
fi

# Forward SSH agent for git+ssh fetches inside Docker
SSH_ARGS=""
if [ -n "$SSH_AUTH_SOCK" ]; then
  SSH_ARGS="-v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
  echo "SSH agent forwarding enabled"
else
  echo "WARNING: SSH_AUTH_SOCK not set — git+ssh fetches inside Docker may fail"
  echo "  Run: eval \$(ssh-agent) && ssh-add"
fi

# Run the container as non-root user with proper UID/GID mapping
exec docker run -it \
  --rm \
  -v "${SCRIPT_DIR}:/workspace" \
  -w /workspace \
  -e LOCAL_UID=$(id -u) \
  -e LOCAL_GID=$(id -g) \
  $SSH_ARGS \
  "${DOCKER_IMAGE_NAME}" \
  /bin/bash