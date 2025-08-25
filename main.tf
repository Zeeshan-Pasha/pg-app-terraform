# Security Group
resource "aws_security_group" "web_sg" {
  name_prefix = "pg-app-sg-"
  description = "Security group for PG Application (.NET 8 + React 20)"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = ".NET app port"
  }

  ingress {
    from_port   = 5173
    to_port     = 5173
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Vite dev port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name    = "PG-App-Security-Group"
    Project = "DotNetCore8-React20"
  }
}

# EC2 Instance
resource "aws_instance" "example" {
  ami                         = "ami-0f58b397bc5c1f2e8" # Ubuntu 22.04 LTS in ap-south-1 (Mumbai)
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

echo "Starting user-data script at $(date)" >> /var/log/user-data.log

# ---------- Update System ----------
apt-get update -y
apt-get upgrade -y
apt-get install -y git curl software-properties-common apt-transport-https ca-certificates gnupg lsb-release

# ---------- Install Docker ----------
echo "Installing Docker..." >> /var/log/user-data.log
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
sleep 10

# Test Docker installation
docker --version >> /var/log/user-data.log

# ---------- Create Docker Compose file ----------
mkdir -p /opt/pgapp
chown ubuntu:ubuntu /opt/pgapp

cat > /opt/pgapp/docker-compose.yml << 'COMPOSE'
version: '3.8'
services:
  pgapp:
    image: zeeshan781/pg-application:latest
    container_name: pgapp
    ports:
      - "5000:5000"
    restart: unless-stopped
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:5000
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
COMPOSE

# ---------- Create systemd service for Docker Compose ----------
cat > /etc/systemd/system/pgapp-docker.service << 'SERVICE'
[Unit]
Description=PG Application Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/pgapp
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
ExecReload=/usr/bin/docker-compose restart
TimeoutStartSec=0
User=root

[Install]
WantedBy=multi-user.target
SERVICE

# ---------- Install Docker Compose ----------
echo "Installing Docker Compose..." >> /var/log/user-data.log
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create symlink for docker-compose command
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version >> /var/log/user-data.log

# ---------- Enable and start the service ----------
systemctl daemon-reload
systemctl enable pgapp-docker

# ---------- Create startup script for manual deployment ----------
cat > /opt/pgapp/deploy.sh << 'DEPLOY'
#!/bin/bash
set -e

echo "Deploying PG Application..."
cd /opt/pgapp

# Pull latest image
echo "Pulling latest Docker image..."
docker-compose pull

# Stop existing containers
echo "Stopping existing containers..."
docker-compose down

# Start new containers
echo "Starting new containers..."
docker-compose up -d

# Show status
echo "Deployment complete. Container status:"
docker-compose ps

echo "Application should be available at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5000"
DEPLOY

chmod +x /opt/pgapp/deploy.sh
chown -R ubuntu:ubuntu /opt/pgapp

# ---------- Create health check script ----------
cat > /opt/pgapp/health-check.sh << 'HEALTH'
#!/bin/bash
response=$(curl -s -o /dev/null -w "%%{http_code}" http://localhost:5000 || echo "000")
if [ "$response" = "200" ] || [ "$response" = "404" ]; then
    echo "Application is running (HTTP $response)"
    exit 0
else
    echo "Application is not responding (HTTP $response)"
    exit 1
fi
HEALTH

chmod +x /opt/pgapp/health-check.sh
chown ubuntu:ubuntu /opt/pgapp/health-check.sh

# ---------- Initial deployment attempt ----------
echo "Attempting initial deployment..." >> /var/log/user-data.log
cd /opt/pgapp

# Try to pull and start the container (this might fail if image doesn't exist yet)
docker-compose pull || echo "Image not available yet, will be deployed via Jenkins"
sleep 5

echo "User-data script completed at $(date)" >> /var/log/user-data.log
echo "Check deployment status with: systemctl status pgapp-docker" >> /var/log/user-data.log
echo "Manual deployment: /opt/pgapp/deploy.sh" >> /var/log/user-data.log
EOF

  tags = {
    Name        = "PG-Application-Server"
    Project     = "DotNetCore8-React20"
    Environment = "Development"
  }
}