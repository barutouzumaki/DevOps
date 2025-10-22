# -----------------------------
# Step 0: Base image
# -----------------------------
FROM node:18.18.2

# -----------------------------
# Step 1: Metadata
# -----------------------------
LABEL author="Naruto Shippuden"
LABEL description="Node.js + PM2 + ClamAV + MongoDB Tools + Python container"

# -----------------------------
# Step 2: Create non-root user & workspace
# -----------------------------
# Create user 'mgtmp' with home directory and a workspace
RUN useradd -ms /bin/bash mgtmp && \
    mkdir -p /workspace && \
    chown -R mgtmp:mgtmp /workspace

WORKDIR /workspace

# -----------------------------
# Step 3: Install all system dependencies as root
# -----------------------------
USER root

# Update package list and install required packages:
# git         -> for cloning repositories
# sudo        -> allows temporary elevated commands for services
# curl/wget   -> for downloading files
# python3/pip -> for running Python scripts
# clamav      -> antivirus engine
# clamav-daemon -> ClamAV service
# npm PM2     -> global Node process manager
# MongoDB tools -> database tools like mongodump/mongorestore
RUN apt-get update && \
    apt-get install -y git sudo curl wget python3 python3-pip clamav clamav-daemon && \
    npm install -g pm2 && \
    wget https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2004-x86_64-100.9.3.deb -O /tmp/mongodb-tools.deb && \
    dpkg -i /tmp/mongodb-tools.deb || apt-get install -f -y && \
    rm -f /tmp/mongodb-tools.deb

# -----------------------------
# Step 4: Configure ClamAV
# -----------------------------
# Update virus definitions
RUN freshclam

# Configure ClamAV daemon settings
# MaxFileSize 100M -> maximum file size to scan
# TCPSocket 3310   -> enable TCP socket for other services to connect
RUN sed -i 's/^#MaxFileSize .*/MaxFileSize 100M/' /etc/clamav/clamd.conf && \
    sed -i 's/^#TCPSocket .*/TCPSocket 3310/' /etc/clamav/clamd.conf

# Clean up apt cache to reduce image size
RUN apt-get clean

# -----------------------------
# Step 5: Switch back to non-root user for running the app
# -----------------------------
USER mgtmp

# -----------------------------
# Step 6: Expose application and ClamAV ports
# -----------------------------
# Node.js app ports
EXPOSE 2000 3000 4007 5000
# ClamAV TCP socket
EXPOSE 3310

# -----------------------------
# Step 7: Start ClamAV and Node apps together (self-contained)
# -----------------------------
# freshclam -> update virus DB at container start
# clamd &   -> start ClamAV daemon in background
# pm2-runtime -> start all Node apps defined in ecosystem.config.js
CMD sudo freshclam && sudo clamd & pm2-runtime ecosystem.config.js
