# Minimal Dockerfile for Local Development
# Files come from volume mount, dependencies installed at startup
FROM node:24-alpine

# Install system dependencies
RUN apk add --no-cache dumb-init curl bash python3 make cmake g++

# Install nx + drizzle-kit globally for CLI access
RUN npm install -g nx@latest drizzle-kit

# Enable Yarn via corepack
RUN corepack enable yarn

# Opt out of telemetry pings (Next.js)
ENV NEXT_TELEMETRY_DISABLED=1

# Set working directory
WORKDIR /app

# Uncomment if non-root user is not available.
#RUN addgroup -g 1000 -S node && \
#    adduser -S node -u 1000 -G node

# Create directories with proper permissions for volume mounts
RUN mkdir -p node_modules uploads .nx/cache tmp && \
    chown -R 1000:1000 node_modules uploads .nx tmp

# Switch to non-root user
USER 1000

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# Default command (overridden by docker-compose)
CMD ["sh"]
