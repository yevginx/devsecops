# Multi-language development environment
# Supports Python 2.7, Python 3.x, and R

FROM ubuntu:20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Basic utilities
    curl \
    wget \
    git \
    vim \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    # Build tools
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    # Python dependencies
    python2.7 \
    python2.7-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    # R dependencies
    r-base \
    r-base-dev \
    # Additional libraries for data science
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install pip for Python 2.7
RUN curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py && \
    python2.7 get-pip.py && \
    rm get-pip.py

# Create symbolic links for easier access
RUN ln -s /usr/bin/python2.7 /usr/bin/python2 && \
    ln -s /usr/bin/python3 /usr/bin/python

# Copy requirements files
COPY requirements-python2.txt requirements-python3.txt requirements-r.txt ./

# Install Python 2 packages
RUN python2 -m pip install --no-cache-dir -r requirements-python2.txt

# Install Python 3 packages
RUN python3 -m pip install --no-cache-dir -r requirements-python3.txt

# Install R packages
RUN Rscript -e "install.packages(readLines('requirements-r.txt'), repos='https://cran.rstudio.com/')"

# Create non-root user for security
RUN useradd -m -s /bin/bash devuser && \
    chown -R devuser:devuser /app

USER devuser

# Set environment variables
ENV PATH="/home/devuser/.local/bin:$PATH"
ENV PYTHONPATH="/app:$PYTHONPATH"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 -c "import sys; print('Python 3:', sys.version)" && \
        python2 -c "import sys; print('Python 2:', sys.version)" && \
        R --version

# Default command to keep container running
CMD ["tail", "-f", "/dev/null"]
