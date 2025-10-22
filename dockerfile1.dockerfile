FROM node:18.18.2
LABEL author="abhinav.marri"
LABEL description="Node.js + PM2 + ClamAV + MongoDB Tools + Python container"

# Step 1: Create non-root user
RUN useradd -ms /bin/bash mgtmp &&\
    mkdir -p /home/mgtmp/workspace && \
    chown -R mgtmp:mgtmp /home/mgtmp/workspace

# Step 2: Install system dependencies and tools
RUN apt-get update && \
    apt-get install -y clamav clamav-daemon wget && \
    apt-get clean

# Step 3: Install Node.js global packages
RUN npm install -g pm2

# Step 4: Update ClamAV configuration
RUN sed -i 's/^#MaxFileSize .*/MaxFileSize 100M/' /etc/clamav/clamd.conf && \
    sed -i 's/^#TCPSocket .*/TCPSocket 3310/' /etc/clamav/clamd.conf

# Step 5: Install MongoDB tools
RUN wget https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2004-x86_64-100.9.3.deb -O /tmp/mongodb-tools.deb && \
    dpkg -i /tmp/mongodb-tools.deb || apt-get install -f -y && \
    rm -f /tmp/mongodb-tools.deb

# Step 6: Install Python 3 and pip
RUN apt-get install -y python3 python3-pip && \
    apt-get clean

# Step 6.5: Install NVM and Node.js versions
USER mgtmp
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash && \
    export NVM_DIR="$HOME/.nvm" && \
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && \
    nvm install 16.13.2 && \
    nvm install 18.18.2 && \
    nvm use 18.18.2

# Step 7: Switch to non-root user
USER mgtmp
WORKDIR /home/mgtmp/workspace

# Step 8: Setup SSH & Git Config
# Copy SSH keys into container (temporarily)
COPY .ssh /home/mgtmp/.ssh

# Set correct permissions
USER root
RUN chown -R mgtmp:mgtmp /home/mgtmp/.ssh && \
    chmod 700 /home/mgtmp/.ssh && \
    find /home/mgtmp/.ssh -type f -name "id_*" -exec chmod 600 {} \;

# Clone repositories
USER mgtmp
RUN git clone git@mbaas.github.com:ApplaudSolutions/applaud-cloud.git . && \
    git clone git@microservices.github.com:ApplaudSolutions/node.git . && \
    npm install

# Remove SSH Keys for security
USER root
RUN rm -rf /home/mgtmp/.ssh
USER mgtmp

# Step 9: Expose application and ClamAV ports
EXPOSE 2000 3000 4007 5000 3310

# Step 10: Create startup script
USER root
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Start ClamAV services as root\n\
echo "Starting ClamAV services..."\n\
freshclam\n\
clamd &\n\
\n\
# Wait a moment for ClamAV to start\n\
sleep 2\n\
\n\
# Switch to non-root user and start all services\n\
echo "Starting all application services..."\n\
su - mgtmp -c "source ~/.bashrc && cd /home/mgtmp/workspace && /home/mgtmp/start-services.sh" &\n\
\n\
# Keep container running and handle signals properly\n\
trap "echo \"Shutting down...\"; kill 0; exit 0" SIGTERM SIGINT\n\
wait' > /start.sh && \
    chmod +x /start.sh

# Step 11: Create services startup script
USER mgtmp
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Load NVM\n\
export NVM_DIR="$HOME/.nvm"\n\
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"\n\
\n\
echo "#### Starting Main Application Services ####"\n\
cd /home/mgtmp/workspace\n\
yarn seed\n\
nvm use 18\n\
\n\
echo "#### PM2 Start API, HIGH and LOW WORKERS ####"\n\
pm2 restart API || pm2 start ecosystem.config.js --only API\n\
pm2 restart HIGH_WORKER || pm2 start ecosystem.config.js --only HIGH_WORKER\n\
pm2 restart LOW_WORKER || pm2 start ecosystem.config.js --only LOW_WORKER\n\
pm2 restart EMAIL_WORKER || pm2 start ecosystem.config.js --only EMAIL_WORKER\n\
\n\
echo "#### Node repo Services ####"\n\
cd /home/mgtmp/workspace/node\n\
\n\
# Update node repository\n\
git fetch --all\n\
git reset --hard\n\
git checkout 16.0.0\n\
git pull origin 16.0.0\n\
\n\
# Start NODE_NATIVE_APPS\n\
cd /home/mgtmp/workspace/node/node-native-apps\n\
pm2 restart NODE_NATIVE_APPS || pm2 start ecosystem.config.js --only NODE_NATIVE_APPS\n\
\n\
# Start NODE_AI\n\
cd /home/mgtmp/workspace/node/node-ai\n\
rm -rf node_modules\n\
yarn\n\
pm2 restart NODE_AI || pm2 start ecosystem.config.js --only NODE_AI\n\
\n\
# Start node-branding\n\
cd /home/mgtmp/workspace/node/node-branding\n\
nvm use 16.13.2\n\
pm2 restart node-branding --interpreter $(which node) || pm2 start ecosystem.config.js --only node-branding --interpreter $(which node)\n\
\n\
# Start NODE_PUSH\n\
cd /home/mgtmp/workspace/node/node-push\n\
pm2 restart NODE_PUSH --interpreter $(which node) || pm2 start ecosystem.config.js --only NODE_PUSH --interpreter $(which node)\n\
\n\
# Start node-acs\n\
cd /home/mgtmp/workspace/node/node-acs\n\
sed -i "s/3000/8000/g" app.config.js\n\
pm2 restart node-acs || pm2 start ecosystem.config.js --only node-acs\n\
\n\
# Start node-url-shortener\n\
cd /home/mgtmp/workspace/node/node-url-shortener\n\
rm -rf node_modules\n\
yarn\n\
pm2 restart node_url_shortener || pm2 start ecosystem.config.js --only node_url_shortener\n\
\n\
# Setup PM2 log rotation and save\n\
pm2 start pm2-logrotate || pm2 restart pm2-logrotate\n\
pm2 save\n\
\n\
echo "#### All services started successfully ####"\n\
\n\
# Keep PM2 running\n\
pm2-runtime ecosystem.config.js' > /home/mgtmp/start-services.sh && \
    chmod +x /home/mgtmp/start-services.sh

# Step 12: Start services
CMD ["/start.sh"]
