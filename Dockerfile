FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies (combined Yocto 4.0 + StreamBox requirements)
RUN apt-get update && apt-get install -y \
    # Essentials from original build guide
    git \
    ssh \
    make \
    gcc \
    libssl-dev \
    liblz4-tool \
    expect \
    expect-dev \
    g++ \
    patchelf \
    chrpath \
    gawk \
    texinfo \
    diffstat \
    binfmt-support \
    qemu-user-static \
    live-build \
    bison \
    flex \
    fakeroot \
    cmake \
    gcc-multilib \
    g++-multilib \
    unzip \
    device-tree-compiler \
    ncurses-dev \
    libgucharmap-2-90-dev \
    bzip2 \
    expat \
    gpgv2 \
    cpp-aarch64-linux-gnu \
    libgmp-dev \
    libmpc-dev \
    bc \
    python2 \
    libstdc++-12-dev \
    xz-utils \
    repo \
    curl \
    wget \
    # Additional Yocto 4.0 requirements
    file \
    coreutils \
    socat \
    cpio \
    python3-git \
    python3-jinja2 \
    libegl1-mesa \
    libsdl1.2-dev \
    pylint \
    xterm \
    python3-subunit \
    mesa-common-dev \
    zstd \
    iputils-ping \
    debianutils \
    build-essential \
    sudo \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Install pip for python2 and python3
RUN curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip2.py \
    && python2 get-pip2.py \
    && rm get-pip2.py \
    && apt-get update && apt-get install -y python3-pip && rm -rf /var/lib/apt/lists/*

# Set python to use python2
RUN update-alternatives --install /usr/bin/python python /usr/bin/python2 1

# Install Python packages (for both python2 and python3)
RUN pip2 install numpy pillow
RUN pip3 install numpy pillow

# Install repo tool if not available via apt
RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo \
    && chmod a+x /usr/local/bin/repo

# Set up locale
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8

# Create a non-root user (UID/GID will be set at runtime)
RUN useradd -m -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create working directory
WORKDIR /workspace

# Set git config for repo (will be overwritten by entrypoint)
RUN git config --global user.name "Streambox Builder" \
    && git config --global user.email "builder@streambox.local"

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]