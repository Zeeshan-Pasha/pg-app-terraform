resource "aws_security_group" "web_sg" {
  name_prefix = "pg-app-sg-"
  description = "Security group for PG Application (.NET 8 + React 19)"

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
    Project = "DotNetCore8-React19"
  }
}

resource "aws_instance" "example" {
  ami                         = "ami-09251aa2e0071bf5e" # Mumbai Amazon Linux 2 AMI
  instance_type              = var.instance_type
  key_name                   = var.key_name
  vpc_security_group_ids     = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail

# Enhanced logging
exec > >(tee /var/log/user-data.log) 2>&1
echo "========================================="
echo "Starting setup at $(date)"
echo "========================================="

# Update system
echo "Updating system packages..."
yum update -y

# Install prerequisites
echo "Installing prerequisites..."
yum install -y wget curl git

# Install .NET 8 SDK for Amazon Linux 2
echo "Installing .NET 8 SDK..."
wget https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
rpm -Uvh packages-microsoft-prod.rpm
yum install -y dotnet-sdk-8.0

# Verify .NET installation
echo "Verifying .NET installation..."
dotnet --version || echo "ERROR: .NET installation failed"

# Install Node.js 20 LTS
echo "Installing Node.js 20..."
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs

# Verify Node.js installation
echo "Verifying Node.js installation..."
node --version || echo "ERROR: Node.js installation failed"
npm --version || echo "ERROR: npm installation failed"

# Create application directory
echo "Setting up application directory..."
mkdir -p /opt/pgapp
cd /opt/pgapp

# Clone repository with better error handling
echo "Cloning repository..."
if ! git clone https://${var.github_user}:${urlencode(var.github_token)}@github.com/Zeeshan-Pasha/PG_Application.git .; then
    echo "ERROR: Failed to clone repository"
    exit 1
fi

# Set proper ownership
chown -R ec2-user:ec2-user /opt/pgapp

# Build frontend as ec2-user
echo "Building frontend..."
if [ -d "pg_application.client" ]; then
    cd pg_application.client
    sudo -u ec2-user npm install --legacy-peer-deps
    sudo -u ec2-user npm run build
    cd ..
else
    echo "WARNING: Frontend directory not found"
fi

# Build backend
echo "Building backend..."
if [ -d "PG_Application.Server" ]; then
    cd PG_Application.Server
    sudo -u ec2-user dotnet restore
    sudo -u ec2-user dotnet publish -c Release -o /opt/pgapp/publish
    cd ..
else
    echo "WARNING: Backend directory not found"
fi

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/pgapp.service << 'SERVICE'
[Unit]
Description=PG Application
After=network.target

[Service]
WorkingDirectory=/opt/pgapp/publish
ExecStart=/usr/bin/dotnet PG_Application.Server.dll
Restart=always
RestartSec=10
User=ec2-user
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000
KillSignal=SIGINT
TimeoutStopSec=90
KillMode=process

[Install]
WantedBy=multi-user.target
SERVICE

# Start the service
echo "Starting PG Application service..."
systemctl daemon-reload
systemctl enable pgapp

# Check if the published files exist before starting
if [ -f "/opt/pgapp/publish/PG_Application.Server.dll" ]; then
    systemctl start pgapp
    echo "Service started successfully"
else
    echo "ERROR: Published application files not found"
fi

# Final status check
echo "========================================="
echo "Setup completed at $(date)"
echo "========================================="
echo "System status:"
echo "- .NET version: $(dotnet --version 2>/dev/null || echo 'Not installed')"
echo "- Node.js version: $(node --version 2>/dev/null || echo 'Not installed')"
echo "- Service status: $(systemctl is-active pgapp 2>/dev/null || echo 'Not running')"
echo "========================================="
EOF

  tags = {
    Name        = "PG-Application-Server"
    Project     = "DotNetCore8-React19"
    Environment = "Development"
  }
}