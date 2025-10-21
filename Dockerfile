FROM node 18.18.2
LABEL author="abhinav.marri"
LABEL description="Node.js + PM2 + ClamAV + MongoDB Tools + Python container"

RUN apt-get update 
# Step 1: Create non-root user
RUN useradd -ms /bin/bash mgtmp &&\
    mkdir -p /workspace && \
    chown -R mgtmp:mgtmp /workspace 
    

# Step 3: Switch to the new user
USER mgtmp
# Step 4: Set working directory
WORKDIR /workspace

#Step 5: Configure ClamAV
USER root

RUN  apt-get update &&\
     apt-get install -y clamav clamav-daemon && \
     apt-get clean
RUN freshclam

RUN npm install -g pm2

#update config in clamd.config
RUN sed -i 's/^#MaxFileSize .*/MaxFileSize 100M' /etc/clamav/clamd.conf && \
    sed -i 's/^#TCPSocket .*/TCPSocket 3310' /etc/clamav/clamd.conf

##Step 6:install mongoDB tools
RUN apt-get update && \
    wget https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2004-x86_64-100.9.3.deb -O /tmp/mongodb-tools.deb && \
    dpkg -i /tmp/mongodb-tools.deb || apt-get install -f -y && \
    rm -f /tmp/mongodb-tools.deb
    

# Install Python 3 and pip
RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    apt-get clean
USER mgtmp

#Step 6: Mount SSH & Git Config
# Copy SSH keys into container (temporarily)
COPY ssh /home/mgtmp/.ssh

# Set correct permissions
RUN chown -R mgtmp:mgtmp /home/mgtmp/.ssh && \
    chmod 700 /home/mgtmp/.ssh && \
    chmod 600 /home/mgtmp/.ssh/id_rsa

    USER mgtmp
RUN git clone git@mbaas.github.com:ApplaudSolutions/applaud-cloud.git /workspace && \
    git clone git@microservices.github.com:ApplaudSolutions/node.git && \
    cd /workspace && npm install

#Remove SSH Keys
USER root
RUN rm -rf /home/mgtmp/.ssh
USER mgtmp

# Step7: Expose application and ClamAV ports

EXPOSE 2000 3000 4007 5000 3310

#Step 8: Start services

CMD sudo freshclam && sudo clamd & pm2-runtime ecosystem.config.js



 




