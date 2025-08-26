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

  # Enhanced root block device for better performance and space
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    tags = {
      Name = "PG-App-Root-Volume"
    }
  }

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail

# Redirect all output to log file with timestamps
exec > >(tee /var/log/user-data.log) 2>&1

echo "================================" >> /var/log/user-data.log
echo "Starting user-data script at $(date)" >> /var/log/user-data.log
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" >> /var/log/user-data.log
echo "================================" >> /var/log/user-data.log

# ---------- Update System ----------
echo "Updating system packages..." >> /var/log/user-data.log
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y git curl wget software-properties-common apt-transport-https ca-certificates gnupg lsb-release unzip htop net-tools

# ---------- Install Docker ----------
echo "Installing Docker..." >> /var/log/user-data.log
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
sleep 15

# Test Docker installation
docker --version >> /var/log/user-data.log
systemctl status docker --no-pager >> /var/log/user-data.log

# ---------- Install Docker Compose ----------
echo "Installing Docker Compose..." >> /var/log/user-data.log
# Get latest version dynamically
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
echo "Installing Docker Compose version: $DOCKER_COMPOSE_VERSION" >> /var/log/user-data.log

curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create symlink for docker-compose command
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version >> /var/log/user-data.log

# ---------- Create Application Directory ----------
echo "Setting up application directory..." >> /var/log/user-data.log
mkdir -p /opt/pgapp
chown ubuntu:ubuntu /opt/pgapp

# ---------- Create Docker Compose file ----------
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
      - DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
      - TZ=Asia/Kolkata
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health", "||", "curl", "-f", "http://localhost:5000", "||", "exit", "1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M
COMPOSE

# ---------- Create enhanced systemd service ----------
cat > /etc/systemd/system/pgapp-docker.service << 'SERVICE'
[Unit]
Description=PG Application Docker Container
After=docker.service network.target
Requires=docker.service
StartLimitBurst=3
StartLimitInterval=300

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/pgapp
ExecStartPre=/usr/bin/docker-compose pull --quiet
ExecStart=/usr/bin/docker-compose up -d --remove-orphans
ExecStop=/usr/bin/docker-compose down --remove-orphans
ExecReload=/usr/bin/docker-compose restart
TimeoutStartSec=300
TimeoutStopSec=60
User=root
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

# ---------- Create enhanced deployment script ----------
cat > /opt/pgapp/deploy.sh << 'DEPLOY'
#!/bin/bash
set -e

echo "================================"
echo "Deploying PG Application..."
echo "Timestamp: $(date)"
echo "================================"

cd /opt/pgapp

# Function to check if image exists on Docker Hub
check_image_exists() {
    local image="$1"
    echo "Checking if image $image exists on Docker Hub..."
    
    # Try to pull the image metadata without downloading
    if docker manifest inspect "$image" > /dev/null 2>&1; then
        echo "✅ Image $image exists on Docker Hub"
        return 0
    else
        echo "❌ Image $image not found on Docker Hub"
        return 1
    fi
}

# Check if image exists before attempting deployment
if ! check_image_exists "zeeshan781/pg-application:latest"; then
    echo "⚠️ Warning: Image not found. This might be the first deployment."
    echo "Please ensure the Jenkins pipeline has completed the image build and push steps."
    exit 1
fi

# Pull latest image with retry logic
echo "Pulling latest Docker image..."
RETRY_COUNT=0
MAX_RETRIES=3

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker-compose pull; then
        echo "✅ Successfully pulled Docker image"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "⚠️ Pull failed, retrying in 10 seconds... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
            sleep 10
        else
            echo "❌ Failed to pull Docker image after $MAX_RETRIES attempts"
            exit 1
        fi
    fi
done

# Stop existing containers gracefully
echo "Stopping existing containers..."
docker-compose down --remove-orphans || true

# Clean up old images to save space
echo "Cleaning up old images..."
docker image prune -f

# Start new containers
echo "Starting new containers..."
docker-compose up -d --remove-orphans

# Wait for container to start
echo "Waiting for container to start..."
sleep 20

# Verify container is running
if ! docker ps | grep -q pgapp; then
    echo "❌ Container failed to start"
    echo "Container logs:"
    docker-compose logs pgapp
    exit 1
fi

# Show status
echo "Deployment complete. Container status:"
docker-compose ps

# Show recent logs
echo "Recent container logs:"
docker-compose logs --tail=20

# Get public IP and show URL
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "localhost")
echo "Application should be available at: http://$PUBLIC_IP:5000"

echo "================================"
echo "Deployment completed successfully at $(date)"
echo "================================"
DEPLOY

chmod +x /opt/pgapp/deploy.sh

# ---------- Create enhanced health check script ----------
cat > /opt/pgapp/health-check.sh << 'HEALTH'
#!/bin/bash

echo "Performing comprehensive health check..."

# Check if container is running
if ! docker ps | grep -q pgapp; then
    echo "❌ Container 'pgapp' is not running"
    echo "Available containers:"
    docker ps -a
    exit 1
fi

# Check container health status
HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' pgapp 2>/dev/null || echo "unknown")
echo "Container health status: $HEALTH_STATUS"

# Check if port is listening
if ! netstat -tuln | grep -q ":5000 "; then
    echo "❌ Port 5000 is not listening"
    echo "Open ports:"
    netstat -tuln | grep LISTEN
    exit 1
fi

# Check HTTP response with multiple attempts
MAX_ATTEMPTS=3
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "HTTP check attempt $ATTEMPT/$MAX_ATTEMPTS..."
    
    response=$(curl -s -o /dev/null -w "%%{http_code}" http://localhost:5000 || echo "000")
    
    if [ "$response" = "200" ]; then
        echo "✅ Application is healthy (HTTP $response)"
        
        # Additional checks
        echo "Container uptime: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep pgapp)"
        echo "Memory usage: $(docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}' pgapp)"
        
        exit 0
    elif [ "$response" = "404" ]; then
        echo "⚠️ Application is running but returned 404 (HTTP $response)"
        echo "   This might be expected if no route is configured for '/'"
        exit 0
    elif [ "$response" = "000" ]; then
        echo "⚠️ Connection failed (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    else
        echo "⚠️ Unexpected HTTP response: $response (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    fi
    
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo "   Waiting 5 seconds before next attempt..."
        sleep 5
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

echo "❌ Health check failed after $MAX_ATTEMPTS attempts"
echo "Container logs (last 20 lines):"
docker logs pgapp --tail 20
echo "Container stats:"
docker stats --no-stream pgapp || echo "Could not get container stats"

exit 1
HEALTH

chmod +x /opt/pgapp/health-check.sh

# ---------- Create monitoring script ----------
cat > /opt/pgapp/monitor.sh << 'MONITOR'
#!/bin/bash

echo "=== PG Application Monitoring ==="
echo "Timestamp: $(date)"
echo

echo "=== Container Status ==="
docker-compose ps

echo
echo "=== Resource Usage ==="
docker stats --no-stream pgapp || echo "Container not running"

echo
echo "=== Recent Logs (last 10 lines) ==="
docker logs pgapp --tail 10 || echo "No logs available"

echo
echo "=== Network Status ==="
netstat -tuln | grep :5000 || echo "Port 5000 not listening"

echo
echo "=== Disk Usage ==="
df -h /opt/pgapp
docker system df

echo
echo "=== Application URL ==="
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "localhost")
echo "http://$PUBLIC_IP:5000"
MONITOR

chmod +x /opt/pgapp/monitor.sh

# ---------- Set proper ownership ----------
chown -R ubuntu:ubuntu /opt/pgapp

# ---------- Enable systemd service ----------
echo "Enabling pgapp-docker service..." >> /var/log/user-data.log
systemctl daemon-reload
systemctl enable pgapp-docker

# ---------- Create log rotation ----------
cat > /etc/logrotate.d/pgapp << 'LOGROTATE'
/var/log/user-data.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    copytruncate
}
LOGROTATE

# ---------- Wait for Docker to be fully ready ----------
echo "Waiting for Docker to be fully ready..." >> /var/log/user-data.log
sleep 30

# ---------- Create status indicator file ----------
echo "ready" > /opt/pgapp/.status
chown ubuntu:ubuntu /opt/pgapp/.status

# ---------- Final system status ----------
echo "================================" >> /var/log/user-data.log
echo "Final system status:" >> /var/log/user-data.log
echo "Docker version: $(docker --version)" >> /var/log/user-data.log
echo "Docker Compose version: $(docker-compose --version)" >> /var/log/user-data.log
echo "Docker service status:" >> /var/log/user-data.log
systemctl status docker --no-pager >> /var/log/user-data.log
echo "pgapp-docker service status:" >> /var/log/user-data.log
systemctl status pgapp-docker --no-pager >> /var/log/user-data.log

echo "================================" >> /var/log/user-data.log
echo "User-data script completed successfully at $(date)" >> /var/log/user-data.log
echo "================================" >> /var/log/user-data.log
echo "" >> /var/log/user-data.log
echo "🚀 Ready for Jenkins deployment!" >> /var/log/user-data.log
echo "" >> /var/log/user-data.log
echo "Useful commands:" >> /var/log/user-data.log
echo "- Check status: sudo systemctl status pgapp-docker" >> /var/log/user-data.log
echo "- Manual deploy: sudo /opt/pgapp/deploy.sh" >> /var/log/user-data.log
echo "- Health check: /opt/pgapp/health-check.sh" >> /var/log/user-data.log
echo "- Monitor app: /opt/pgapp/monitor.sh" >> /var/log/user-data.log
echo "- View logs: tail -f /var/log/user-data.log" >> /var/log/user-data.log
echo "- Container logs: docker logs pgapp -f" >> /var/log/user-data.log
EOF

  tags = {
    Name        = "PG-Application-Server"
    Project     = "DotNetCore8-React20"
    Environment = "Development"
    CreatedBy   = "Terraform"
    ManagedBy   = "Jenkins-Pipeline"
  }
}