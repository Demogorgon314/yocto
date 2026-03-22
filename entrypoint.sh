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

# Configure git to use SSH for GitHub (for submodules)
if [ -n "$GITHUB_SSH_KEY" ]; then
    mkdir -p /home/builder/.ssh
    echo "$GITHUB_SSH_KEY" > /home/builder/.ssh/id_rsa
    chmod 600 /home/builder/.ssh/id_rsa
    chown -R builder:builder /home/builder/.ssh
    cat >> /home/builder/.ssh/config << 'EOF'
Host github.com
    StrictHostKeyChecking no
EOF
    chmod 600 /home/builder/.ssh/config
fi

# Set up bitbake environment variables
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Execute the provided command
if [ $# -eq 0 ]; then
    exec gosu builder /bin/bash
else
    exec gosu builder "$@"
fi
