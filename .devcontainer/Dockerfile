################################################################################################
# ARG vs ENV (CHEAT SHEET)
# ARG = build-time only; changing it busts cache of subsequent layers.
# ENV = lives in final image; visible to shells/processes.
# We centralize Python version here only (no duplication in devcontainer.json) to avoid drift.
################################################################################################

ARG UBUNTU_VERSION=24.04
# Base Ubuntu version (pinned for reproducibility / caching)
FROM ubuntu:${UBUNTU_VERSION}
# Single base image; build toolchain and runtime libs live together in single-stage approach

################################################################################################
# BUILD ARGS (override with --build-arg). Provide PYTHON_SHA256 for integrity.
################################################################################################
ARG PYTHON_VERSION=3.12.3
ARG PYTHON_SHA256=
ARG PYTHON_ENV=my_python_dev
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
# PYTHON_SHA256 optional; provide to verify supply-chain integrity.
# PYTHON_ENV controls virtualenv path under /opt.
# USER / UID / GID align with host to minimize permission friction.

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHON_VERSION=${PYTHON_VERSION} \
    PYTHON_ENV=${PYTHON_ENV} \
    VIRTUAL_ENV=/opt/${PYTHON_ENV} \
    PATH=/opt/${PYTHON_ENV}/bin:${PATH}
# DEBIAN_FRONTEND suppresses interactive prompts; PATH prepends venv bin.

################################################################################################
# WHY A VIRTUALENV IN A CONTAINER?
# * Isolates pip state from system interpreter.
# * Stable path for editors: /opt/<name>/bin/python3.
# * Easy to recreate / swap without rebuilding base image.
################################################################################################

################################################################################################
# PACKAGES (BUILD + RUNTIME)
# Single-stage merges toolchain + runtime libs. Remove lines marked (*) to slim.
################################################################################################
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    # Toolchain to compile CPython and native extension wheels
    build-essential \
    # HTTP client for scripts / APIs (optional if wget alone is enough)
    curl \
    # Primary fetch tool for Python source & other artifacts
    wget \
    # TLS root certificates for secure downloads
    ca-certificates \
    # Extract .tar.xz archives (Python source distribution format)
    xz-utils \
    # zlib headers enable gzip & zipfile modules
    zlib1g-dev \
    # OpenSSL headers for ssl / hashlib / crypt / TLS
    libssl-dev \
    # bzip2 compression (bz2 module)
    libbz2-dev \
    # Readline line-editing in interactive REPL
    libreadline-dev \
    # SQLite embedded database (sqlite3 module)
    libsqlite3-dev \
    # libffi for cffi-based packages & cryptography
    libffi-dev \
    # LZMA / xz compression (lzma module)
    liblzma-dev \
    # (*) Drop the next line if you never use tkinter
    tk-dev \
    # Better REPL (drop if minimal)
    libncursesw5-dev \
    # Needed for VCS-based pip installs
    git \
    # (*) Handy for JSON scripting; optional
    jq \
    # Convenience; remove if unnecessary
    sudo \
    # (*) Shell UX sugar
    bash-completion \
    # (*) Editor convenience
    nano \
    # (*) Pager convenience
    less \
    # git@ / SSH interactions
    openssh-client \
 && rm -rf /var/lib/apt/lists/*

################################################################################################
# PYTHON SOURCE BUILD
# Downloads, optional checksum verify, compiles, installs (altinstall), symlinks python3/pip3.
################################################################################################
WORKDIR /tmp/python-build
# Ephemeral build workspace (cleaned after Python install)

RUN set -eux \
    # Build: construct tarball file name
    && TAR="Python-${PYTHON_VERSION}.tgz" \
    # Official source URL for exact version
    && URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${TAR}" \
    # Log fetch intent
    && echo "[python-build] Fetching $URL" \
    # Download Python source
    && wget -q "$URL" \
    # Optionally verify checksum
    && if [ -n "$PYTHON_SHA256" ]; then echo "$PYTHON_SHA256  $TAR" | sha256sum -c -; echo "[python-build] Checksum OK"; else echo "[python-build] WARNING: No PYTHON_SHA256 provided (skipping integrity verification)"; fi \
    # Extract source archive
    && tar -xf "$TAR" \
    # Enter source directory
    && cd "Python-${PYTHON_VERSION}" \
    # Configure with optimizations + ensurepip
    && ./configure --enable-optimizations --with-ensurepip=install \
    # Compile using all cores
    && make -j"$(nproc)" \
    # Install without clobbering default 'python'
    && make altinstall \
    # Derive major.minor for symlink creation
    && major_minor="${PYTHON_VERSION%.*}" \
    # Standardize python3 symlink
    && ln -sf /usr/local/bin/python${major_minor} /usr/local/bin/python3 \
    # Standardize pip3 symlink
    && ln -sf /usr/local/bin/pip${major_minor} /usr/local/bin/pip3 \
    # Leave build directory
    && cd / \
    # Remove build artifacts to reclaim space
    && rm -rf /tmp/python-build
# Python build sequence complete.

################################################################################################
# PROJECT WORKDIR + DEPENDENCIES
################################################################################################

# Set working directory to match devcontainer.json workspaceFolder
WORKDIR /workspaces/container

# Copy requirements.txt from workspace root (build context root)
COPY requirements.txt ./requirements.txt
# Copy early to leverage layer caching when dependencies unchanged.

RUN \
     # Create isolated virtual environment
     python3 -m venv "$VIRTUAL_ENV" \
     # Activate environment for subsequent pip work
 && . "$VIRTUAL_ENV/bin/activate" \
     # Upgrade pip and install essential build tools
 && python -m pip install --upgrade pip wheel setuptools \
     # Install project dependencies if manifest present
 && if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
# Virtualenv created & dependencies installed.

# TIP: Dev-only tools (black, mypy, pytest, pre-commit) are installed in postCreate.sh
# to keep the Docker image lean and allow faster rebuilds of core dependencies.

################################################################################################
# USER (NON-ROOT) - placed AFTER heavy build for better layer cache reuse.
################################################################################################
RUN set -eux \
    # Reuse existing UID/GID entries when the base image already defines them.
    && existing_group="$(getent group "${USER_GID}" | cut -d: -f1 || true)" \
    && if [ -n "${existing_group}" ] && [ "${existing_group}" != "${USERNAME}" ]; then \
         groupmod --new-name "${USERNAME}" "${existing_group}"; \
       elif ! getent group "${USERNAME}" >/dev/null; then \
         groupadd --gid "${USER_GID}" "${USERNAME}"; \
       fi \
    && groupmod --gid "${USER_GID}" "${USERNAME}" \
    && existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)" \
    && if [ -n "${existing_user}" ] && [ "${existing_user}" != "${USERNAME}" ]; then \
         usermod --login "${USERNAME}" "${existing_user}"; \
       elif ! id -u "${USERNAME}" >/dev/null 2>&1; then \
         useradd -s /bin/bash --uid "${USER_UID}" --gid "${USER_GID}" -m "${USERNAME}"; \
       fi \
    && usermod --uid "${USER_UID}" --gid "${USER_GID}" --shell /bin/bash "${USERNAME}" \
    && HOME_DIR="$(getent passwd "${USERNAME}" | cut -d: -f6)" \
    && if [ "${HOME_DIR}" != "/home/${USERNAME}" ]; then \
         usermod --home /home/${USERNAME} --move-home "${USERNAME}" || { mkdir -p /home/${USERNAME}; chown "${USER_UID}:${USER_GID}" /home/${USERNAME}; }; \
       fi \
    && mkdir -p /home/${USERNAME} \
    && chown ${USER_UID}:${USER_GID} /home/${USERNAME} \
    # Change ownership of virtual environment to the dev user
    && chown -R ${USER_UID}:${USER_GID} ${VIRTUAL_ENV} \
    # Grant passwordless sudo
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-${USERNAME} \
    # Seed login shell configuration for the dev user
    && touch /home/${USERNAME}/.bashrc \
    && printf '%s\n' "source ${VIRTUAL_ENV}/bin/activate" "export PS1='[devcontainer] \u@\h:\w$ '" >> /home/${USERNAME}/.bashrc \
    && chown ${USER_UID}:${USER_GID} /home/${USERNAME}/.bashrc
# Non-root dev user ready.

USER ${USERNAME}

SHELL ["/bin/bash", "-c"]

################################################################################################
# MAINTENANCE CHEAT SHEET
# * Bump Python: devcontainer build --build-arg PYTHON_VERSION=3.x.y --build-arg PYTHON_SHA256=<sha256>
# * Recreate venv: rm -rf /opt/${PYTHON_ENV} && python3 -m venv /opt/${PYTHON_ENV}
# * Dev tools: pip install -U black isort mypy pytest pre-commit
# * Integrity: always provide PYTHON_SHA256 outside local experiments.
################################################################################################
