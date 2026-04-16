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
RUN pip install --no-cache-dir jaclang jac-client jac-scale byllm

# Install Bun (required for jac client-side dependencies)
RUN curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun/bin/bun /usr/local/bin/bun && \
    chmod +x /usr/local/bin/bun

# Copy application code
COPY . /app

# Install MCP relay (Jac/Python)
RUN pip install --no-cache-dir -e /app/mcp-server

# Install client-side npm dependencies and project dependencies
RUN jac clean --all --force
RUN jac add --npm && jac install
RUN jac setup pwa
# Set environment variables
ENV PORT=8000 \
    HOST=0.0.0.0 \
    DEBUG=false \
    LOG_LEVEL=info \
    PYTHONUNBUFFERED=1 \
    JASKETCH_RELAY_PORT=9601

# Create non-root user for security
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app

USER appuser

# Pre-warm Jac bytecode cache as appuser (avoids cold-start recompilation at runtime)
RUN python -c "import jaclang" || true

EXPOSE 8000 9601 9602

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:8000/ || exit 1

# Run jac app with embedded relay (started via JASKETCH_START_RELAY=true in main.jac)
CMD jac start --client pwa
