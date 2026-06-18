# Start with a Java 17 JDK Image
FROM mcr.microsoft.com/devcontainers/java:dev-17-jdk-trixie

# Install System Dependencies
RUN apt-get update && apt-get install -y \
    iptables ipset dnsutils jq curl git sudo unzip maven graphviz \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js & Claude Code
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code@2.1.0 http-server

# Setup Scripts
COPY --chmod=0755 .devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY --chmod=0755 .devcontainer/post-start.sh /usr/local/bin/post-start.sh

# Setup User
RUN echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers



WORKDIR /workspace