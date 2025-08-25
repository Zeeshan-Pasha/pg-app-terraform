#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

# ---------- Update System ----------
apt-get update -y
apt-get upgrade -y
apt-get install -y git curl software-properties-common apt-transport-https ca-certificates

# ---------- Install Docker ----------
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ---------- Create systemd Service Placeholder ----------
cat > /etc/systemd/system/pgapp-docker.service << 'SERVICE'
[Unit]
Description=PG Application Docker Container
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=10
ExecStart=/usr/bin/docker run --rm -p 5000:5000 --name pgapp pgapp:latest
ExecStop=/usr/bin/docker stop pgapp
User=ubuntu

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable pgapp-docker
systemctl start pgapp-docker
