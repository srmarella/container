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
  git config --global --add safe.directory "$(pwd)"
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

echo "[postCreate] Complete."
