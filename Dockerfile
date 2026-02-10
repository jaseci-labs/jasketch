# JaSketch - Modern Whiteboard Application

FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    python3-gdbm \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x for client-side dependencies
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Jac packages from PyPI
RUN pip install --no-cache-dir jaclang==0.10.0 jac-client==0.2.16

# Install Bun (required for jac client-side dependencies)
RUN curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun/bin/bun /usr/local/bin/bun && \
    chmod +x /usr/local/bin/bun

# Copy application code
COPY . /app

# Install client-side npm dependencies and project dependencies
RUN jac add --npm && jac install

# Set environment variables
ENV PORT=8000 \
    HOST=0.0.0.0 \
    DEBUG=false \
    LOG_LEVEL=info \
    PYTHONUNBUFFERED=1

# Create non-root user for security
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/ || exit 1

# Run the application
CMD ["jac", "start"]
