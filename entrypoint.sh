#!/bin/bash
set -e

# Set up proper UID/GID mapping for the builder user
if [ -n "$LOCAL_UID" ] && [ -n "$LOCAL_GID" ]; then
    echo "Setting up user with UID=$LOCAL_UID, GID=$LOCAL_GID"
    groupmod -g "$LOCAL_GID" builder 2>/dev/null || true
    usermod -u "$LOCAL_UID" -g "$LOCAL_GID" builder 2>/dev/null || true
    chown -R builder:builder /workspace
fi

# Configure git (required for repo tool)
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

# Configure SSH for GitHub access (for Yocto git+ssh fetches)
mkdir -p /home/builder/.ssh
ssh-keyscan -t ed25519,rsa github.com >> /home/builder/.ssh/known_hosts 2>/dev/null || true

# Method 1: SSH agent socket forwarded from host
if [ -n "$SSH_AUTH_SOCK" ]; then
    echo "SSH agent socket detected at $SSH_AUTH_SOCK"
    # Make the socket accessible to the builder user
    chmod 777 "$SSH_AUTH_SOCK" 2>/dev/null || true
    chmod 755 "$(dirname "$SSH_AUTH_SOCK")" 2>/dev/null || true
fi

# Method 2: SSH private key passed as environment variable (fallback)
if [ -n "$GITHUB_SSH_KEY" ]; then
    echo "$GITHUB_SSH_KEY" > /home/builder/.ssh/id_rsa
    chmod 600 /home/builder/.ssh/id_rsa
fi

cat >> /home/builder/.ssh/config << 'EOF'
Host github.com
    StrictHostKeyChecking no
EOF
chmod 600 /home/builder/.ssh/config
chown -R builder:builder /home/builder/.ssh

# Set up bitbake environment variables
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Execute the provided command
if [ $# -eq 0 ]; then
    exec gosu builder /bin/bash
else
    exec gosu builder "$@"
fi
