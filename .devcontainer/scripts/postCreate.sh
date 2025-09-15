#!/usr/bin/env bash
set -euo pipefail

echo "[postCreate] Starting post-create tasks..."

# Activate virtual environment created in Dockerfile
# How VIRTUAL_ENV is available:
# 1. Dockerfile sets: ENV VIRTUAL_ENV=/opt/${PYTHON_ENV}
# 2. Dockerfile sets: ENV PATH=/opt/${PYTHON_ENV}/bin:${PATH}
# 3. These environment variables are inherited by all processes in the container
# 4. When this script runs, VIRTUAL_ENV is already set to /opt/my_python_dev
# 5. ${VIRTUAL_ENV:-} means: use $VIRTUAL_ENV if set, otherwise use empty string
if [ -n "${VIRTUAL_ENV:-}" ]; then
  echo "[postCreate] Using existing venv at $VIRTUAL_ENV"
  . "$VIRTUAL_ENV/bin/activate"
else
  echo "[postCreate] Creating fallback virtualenv..."
  python -m venv .venv
  . .venv/bin/activate
fi

# Install dev-only tools from requirements-dev.txt (not included in Docker build to keep image lean)
if [ -f requirements-dev.txt ]; then
  echo "[postCreate] Installing dev requirements from requirements-dev.txt"
  pip install -r requirements-dev.txt
else
  echo "[postCreate] No requirements-dev.txt found, skipping dev tools installation"
fi

# Git safe directory setup (must come before pre-commit)
# What this does:
# - In some environments (Codespaces, Docker), git thinks the repo is "unsafe"
# - This happens when the repo owner doesn't match the current user
# - Adding to "safe.directory" tells git to trust this repo location
# - Without this, git commands might fail with "dubious ownership" errors
# - This MUST run before pre-commit install because pre-commit needs git to work
if [ -d .git ]; then
  echo "[postCreate] Adding repository to git safe.directory"
  if ! git config --global --add safe.directory "$(pwd)" 2>/tmp/git_safe_err.log; then
    echo "[postCreate] Warning: global git config write failed (likely locked). Retrying..."
    sleep 1
    if ! git config --global --add safe.directory "$(pwd)" 2>>/tmp/git_safe_err.log; then
      echo "[postCreate] Fallback: adding safe.directory to local config only"
      git config --local --add safe.directory "$(pwd)" || echo "[postCreate] Could not set local safe.directory (continuing)"
      echo "[postCreate] git safe.directory errors:" && sed 's/^/[git]/' /tmp/git_safe_err.log || true
    fi
  fi
fi

# Initialize pre-commit hooks if config exists
# What this does:
# - pre-commit is a tool that runs code checks (formatting, linting) before each git commit
# - .pre-commit-config.yaml defines which checks to run (black, isort, etc.)
# - "pre-commit install" sets up git hooks to automatically run these checks
# - "--install-hooks" downloads the actual hook tools
# - If you don't have .pre-commit-config.yaml, this section is skipped
if [ -f .pre-commit-config.yaml ]; then
  echo "[postCreate] Installing pre-commit hooks"
  pre-commit install --install-hooks
fi


# Smart Snowflake configuration setup with automatic host detection
#
# The goal: You never have to worry about where your config is, and you never leak secrets by accident.
#
# NOTE: The Snowflake VS Code extension always looks for the config at:
#   ~/.snowflake/connections.toml (in your container's home folder)
# This script makes sure that file is always there and correct!

SNOWFLAKE_CONFIGURED=false
snowflake_dir=$(find . -type d -name .snowflake | head -n 1)
if [ -n "$snowflake_dir" ]; then
  # 1. If you (or your team) put a .snowflake folder anywhere in your project, we use that first.
  #    - This is great for team/project configs you want to share.
  #    - We search everywhere, not just the top folder!
  #    - Instead of copying, we make ~/.snowflake a symlink to your project folder.
  #
  #    Why use a symlink?
  #    - Any changes you make to .snowflake in your project are instantly reflected for the extension and CLI.
  #    - No risk of stale or out-of-sync files between project and home.
  #    - You can commit .snowflake to git and share with your team, and everyone gets the same config.
  #    - If you remove or move the project, just remove the symlink and nothing is left behind in your home.
  #
  #    How does it work?
  #    - We remove any existing ~/.snowflake (file, folder, or symlink) to avoid conflicts.
  #    - We create a symlink: ~/.snowflake -> /absolute/path/to/your/project/.snowflake
  #    - The Snowflake extension and CLI see ~/.snowflake/connections.toml as usual, but it's really your project file.
  echo "[postCreate] Found .snowflake folder at $snowflake_dir - using project configuration (symlink mode)"
  rm -rf ~/.snowflake
  ln -s "$(realpath "$snowflake_dir")" ~/.snowflake
  echo "[postCreate] Project Snowflake configuration symlinked at ~/.snowflake/"
  SNOWFLAKE_CONFIGURED=true
else
  # 2. If you didn't add a .snowflake directory, but you have a Snowflake config on your own computer,
  #    and it's mounted into the container (the default), we use that.
  #    - This is automatic: if you set up Snowflake CLI on your host, it just works.
  if [ -f /host-snowflake/connections.toml ]; then
    echo "[postCreate] Auto-detected host Snowflake configuration"
    mkdir -p ~/.snowflake
    cp /host-snowflake/connections.toml ~/.snowflake/connections.toml
    echo "[postCreate] Host Snowflake configuration automatically copied to ~/.snowflake/connections.toml"
    echo "[postCreate] ✅ Your original host file remains safe and untouched!"
    SNOWFLAKE_CONFIGURED=true
  else
    # 3. If we can't find anything, we print instructions so you know what to do next.
    echo "[postCreate] No Snowflake config found. Setup options:"
    echo "  1. Add .snowflake/ folder to workspace (project-specific, can be committed)"
    echo "  2. Ensure host Snowflake CLI is configured: snowflake connection add"
    echo "  3. Rebuild container after configuring Snowflake CLI on host"
  fi
fi

# If Snowflake is configured, ensure proper setup for VS Code extension
if [ "$SNOWFLAKE_CONFIGURED" = true ]; then
  echo "[postCreate] Configuring Snowflake for VS Code remote usage..."

  # Ensure proper file permissions (Snowflake extension is picky about this)
  chmod 600 ~/.snowflake/connections.toml
  chmod 700 ~/.snowflake

  # Verify the file exists and is readable
  if [ -r ~/.snowflake/connections.toml ]; then
    echo "[postCreate] ✅ Snowflake configuration verified and ready for VS Code extension"
    echo "[postCreate] 📁 Config location: ~/.snowflake/connections.toml"

    # Show available connections (if any)
    if command -v snowflake >/dev/null 2>&1; then
      echo "[postCreate] 🔗 Available Snowflake connections:"
      snowflake connection list 2>/dev/null || echo "   Run 'snowflake connection list' to see connections"
    fi
  else
    echo "[postCreate] ⚠️  Warning: Snowflake config file not readable - check permissions"
  fi
fi

echo "[postCreate] Complete."
