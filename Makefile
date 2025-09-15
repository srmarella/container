################################################################################
# Makefile - Developer Convenience Commands for Python Dev Container
################################################################################
#
# ⚠️  IMPORTANT: This Makefile is NOT used by Docker or devcontainer automation!
#
# This is purely a DEVELOPER CONVENIENCE tool that provides shortcuts for common
# tasks. The actual container building and automation happens through:
# - Dockerfile (defines the container image)
# - devcontainer.json (configures VS Code integration)
# - postCreate.sh (runs setup after container starts)
#
# The devcontainer system works completely independently of this Makefile.
# You can delete this file and your devcontainer will still work perfectly.
#
# PURPOSE:
# This Makefile simply provides easy commands for developers to:
# - Check current Python version
# - Update Python version in Dockerfile
# - Trigger container rebuilds
# - Validate the setup
#
# OVERVIEW:
# - Dockerfile defines ARG PYTHON_VERSION=X.Y.Z (build-time Python version)
# - This Makefile can read that version and help you update it
# - bump-python-version.sh script handles the actual version updating
# - devcontainer CLI rebuilds the container with new settings
#
# HOW VERSION BUMPING WORKS:
# 1. Dockerfile initially has: ARG PYTHON_VERSION=3.12.3
# 2. "make bump VERSION=3.12.4" runs bump-python-version.sh script
# 3. Script EDITS the Dockerfile file, changing the line to: ARG PYTHON_VERSION=3.12.4
# 4. File is permanently modified (you can see the change in git diff)
# 5. Next container rebuild uses the NEW version as the default
# 6. The "initial code" in Docker is now the updated version!
#
# The bump doesn't override Docker defaults - it CHANGES the Docker defaults
# by modifying the source file itself. No build args needed at runtime.
#
# WORKFLOW:
# 1. Check current Python version: make info
# 2. Update to new version:       make bump VERSION=3.12.4 [SHA256=...]
# 3. Rebuild container:           make rebuild
# 4. Reopen in VS Code or restart your container
#
# DEPENDENCIES:
# - devcontainer CLI (optional, for automated rebuild)
# - bash (for running bump-python-version.sh script)
# - awk (for parsing Dockerfile)
#
# FILES INVOLVED:
# - .devcontainer/Dockerfile           (contains ARG PYTHON_VERSION)
# - .devcontainer/scripts/bump-*.sh    (version update script)
# - .devcontainer/devcontainer.json    (container configuration)
#
################################################################################

## QUICK REFERENCE:
##  make info                                  -> shows current Python version from Dockerfile
##  make bump VERSION=3.12.4 [SHA256=...]     -> updates Python version (with optional checksum)
##  make rebuild                               -> rebuilds devcontainer (requires devcontainer CLI)
##  make help                                  -> shows this help message
##
## EXAMPLES:
##  make info                                  -> "Configured Python version: 3.12.3"
##  make bump VERSION=3.12.4                  -> updates Dockerfile to Python 3.12.4
##  make bump VERSION=3.12.4 SHA256=abc123... -> updates with integrity check
##  make rebuild                               -> rebuilds container with new Python version

################################################################################
# Configuration Variables
################################################################################

# Command to run devcontainer CLI (can be overridden: make rebuild DEVCONTAINER=podman)
DEVCONTAINER?=devcontainer

# Extract Python version from Dockerfile ARG line using awk
# Searches for lines like "ARG PYTHON_VERSION=3.12.3" and extracts the version
# Falls back to 'unknown' if not found or Dockerfile is missing
PY_VERSION:=$(shell awk -F= '/^ARG PYTHON_VERSION=/{print $$2}' .devcontainer/Dockerfile | head -1)
PY_VERSION:=$(if $(PY_VERSION),$(PY_VERSION),unknown)

################################################################################
# Targets
################################################################################

################################################################################
# Help Target - Shows usage information
#
# Displays available commands and current configuration.
# Also includes a reminder about what handles the actual automation.
################################################################################
.PHONY: help
help:
	@echo "Python Dev Container Management Commands"
	@echo "========================================"
	@echo ""
	@echo "⚠️  NOTE: This Makefile is for DEVELOPER CONVENIENCE ONLY"
	@echo "   It is NOT used by Docker/devcontainer automation."
	@echo "   Your devcontainer works independently of this file."
	@echo ""
	@grep '^##' Makefile | sed 's/^## //'
	@echo ""
	@echo "Current Configuration:"
	@echo "  Python Version: $(PY_VERSION)"
	@echo "  Devcontainer CLI: $(DEVCONTAINER)"
	@echo ""
	@echo "💡 The actual container automation happens via:"
	@echo "   - Dockerfile (builds the image)"
	@echo "   - devcontainer.json (configures VS Code)"
	@echo "   - postCreate.sh (runs after container starts)"

################################################################################
# Info Target - Display current configuration
#
# Shows detailed information about the current dev container setup,
# including how to perform common tasks.
################################################################################
.PHONY: info
info:
	@echo "=== Python Dev Container Information ==="
	@echo "Current Python version (from Dockerfile): $(PY_VERSION)"
	@echo "Devcontainer command: $(DEVCONTAINER)"
	@echo "Dockerfile location: .devcontainer/Dockerfile"
	@echo ""
	@echo "To update Python version:"
	@echo "  make bump VERSION=3.x.y [SHA256=checksum]"
	@echo ""
	@echo "To rebuild container:"
	@echo "  make rebuild"

################################################################################
# Bump Target - Update Python version in Dockerfile
#
# HOW THIS WORKS:
# 1. Validates that VERSION parameter is provided
# 2. Shows current vs new version for confirmation
# 3. Calls bump-python-version.sh script which:
#    - Searches Dockerfile for "ARG PYTHON_VERSION=" line
#    - Replaces the version value with the new VERSION
#    - Optionally updates SHA256 checksum if provided
#    - Physically modifies the Dockerfile text on disk
# 4. The Dockerfile now has a new default version
# 5. Next container rebuild will use the updated version
#
# IMPORTANT: This permanently modifies the Dockerfile source file.
# You can see the changes with 'git diff' after running this command.
################################################################################
.PHONY: bump
bump:
	@echo "=== Updating Python Version ==="
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: VERSION parameter is required"; \
		echo "Usage: make bump VERSION=3.x.y [SHA256=checksum]"; \
		echo "Example: make bump VERSION=3.12.4"; \
		echo "Example: make bump VERSION=3.12.4 SHA256=abc123..."; \
		exit 1; \
	fi
	@echo "Current version: $(PY_VERSION)"
	@echo "New version: $(VERSION)"
	@if [ -n "$(SHA256)" ]; then echo "SHA256 checksum: $(SHA256)"; fi
	@echo "Running bump script..."
	@bash .devcontainer/scripts/bump-python-version.sh -v $(VERSION) $(if $(SHA256),-s $(SHA256),)
	@echo "✓ Python version updated successfully"
	@echo "📝 Dockerfile has been modified with new version"
	@echo "⚠️  Remember to rebuild the container: make rebuild"

################################################################################
# Rebuild Target - Rebuild the devcontainer
#
# Attempts to rebuild the container using the devcontainer CLI.
# If the CLI is not available, provides manual alternatives.
# After successful rebuild, reminds user to restart their environment.
################################################################################
.PHONY: rebuild
rebuild:
	@echo "=== Rebuilding Dev Container ==="
	@echo "This will rebuild the container with current Dockerfile settings"
	@echo "Python version: $(PY_VERSION)"
	@echo ""
	@echo "Attempting to rebuild with devcontainer CLI..."
	@$(DEVCONTAINER) build --workspace-folder . || { \
		echo ""; \
		echo "❌ Devcontainer CLI not found or failed"; \
		echo ""; \
		echo "📋 Manual rebuild options:"; \
		echo "   VS Code: Command Palette > Dev Containers: Rebuild Container"; \
		echo "   CLI: Install devcontainer CLI: npm install -g @devcontainers/cli"; \
		echo ""; \
		exit 1; \
	}
	@echo "✓ Container rebuilt successfully"
	@echo "🔄 Reopen VS Code or restart your container to use the new environment"

################################################################################
# Additional utility targets
################################################################################

# Check if required files exist
.PHONY: check
check:
	@echo "=== Checking Dev Container Setup ==="
	@echo -n "Dockerfile: "
	@if [ -f .devcontainer/Dockerfile ]; then echo "✓ Found"; else echo "❌ Missing"; fi
	@echo -n "devcontainer.json: "
	@if [ -f .devcontainer/devcontainer.json ]; then echo "✓ Found"; else echo "❌ Missing"; fi
	@echo -n "postCreate script: "
	@if [ -f .devcontainer/scripts/postCreate.sh ]; then echo "✓ Found"; else echo "❌ Missing"; fi
	@echo -n "bump script: "
	@if [ -f .devcontainer/scripts/bump-python-version.sh ]; then echo "✓ Found"; else echo "❌ Missing"; fi
	@echo -n "requirements.txt: "
	@if [ -f requirements.txt ]; then echo "✓ Found"; else echo "⚠️  Optional"; fi
	@echo -n "requirements-dev.txt: "
	@if [ -f requirements-dev.txt ]; then echo "✓ Found"; else echo "⚠️  Optional"; fi

# Show the full workflow
.PHONY: workflow
workflow:
	@echo "=== Python Version Update Workflow ==="
	@echo ""
	@echo "1. Check current version:"
	@echo "   make info"
	@echo ""
	@echo "2. Update Python version:"
	@echo "   make bump VERSION=3.12.4"
	@echo "   # or with checksum for security:"
	@echo "   make bump VERSION=3.12.4 SHA256=abc123..."
	@echo ""
	@echo "3. Rebuild container:"
	@echo "   make rebuild"
	@echo "   # or manually in VS Code:"
	@echo "   # Command Palette > Dev Containers: Rebuild Container"
	@echo ""
	@echo "4. Reopen VS Code or restart container"
	@echo ""
	@echo "Current state: Python $(PY_VERSION)"
