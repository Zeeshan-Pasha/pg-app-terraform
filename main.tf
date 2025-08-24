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
  ami                         = "ami-0f918f7e67a3323f0" # Ubuntu 24.04 AMI in Mumbai
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

# Update system
apt-get update -y
apt-get upgrade -y

# Install prerequisites
apt-get install -y wget git curl software-properties-common

# Install .NET 8 SDK
wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
apt-get update -y
apt-get install -y dotnet-sdk-8.0

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Create application directory
mkdir -p /opt/pgapp
cd /opt/pgapp

# Clone repository using variables from Terraform
git clone https://${var.github_user}:${var.github_token}@github.com/Zeeshan-Pasha/PG_Application.git .

# Set ownership
chown -R ubuntu:ubuntu /opt/pgapp

# Build frontend
if [ -d "pg_application.client" ]; then
  cd pg_application.client
  sudo -u ubuntu npm install --legacy-peer-deps
  sudo -u ubuntu npm run build
  cd ..
fi

# Build backend
if [ -d "PG_Application.Server" ]; then
  cd PG_Application.Server
  sudo -u ubuntu dotnet restore
  sudo -u ubuntu dotnet publish -c Release -o /opt/pgapp/publish
  cd ..
fi

# Create systemd service
cat > /etc/systemd/system/pgapp.service << 'SERVICE'
[Unit]
Description=PG Application
After=network.target

[Service]
WorkingDirectory=/opt/pgapp/publish
ExecStart=/usr/bin/dotnet PG_Application.Server.dll
Restart=always
RestartSec=10
User=ubuntu
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable pgapp
systemctl start pgapp
EOF

  tags = {
    Name        = "PG-Application-Server"
    Project     = "DotNetCore8-React20"
    Environment = "Development"
  }
}
