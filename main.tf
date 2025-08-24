terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "ap-south-1"
}

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

# Use the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2023-ami-kernel-6.4*"]
  }
}

# EC2 Instance
resource "aws_instance" "example" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

# Update system
dnf update -y

# Install .NET 8 SDK and Node.js 20
dnf install -y wget git
wget https://packages.microsoft.com/config/centos/9/packages-microsoft-prod.rpm
dnf install -y packages-microsoft-prod.rpm
dnf install -y dotnet-sdk-8.0
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

# Create application directory
mkdir -p /opt/pgapp
cd /opt/pgapp

# Clone repository
git clone https://${var.github_user}:${var.github_token}@github.com/Zeeshan-Pasha/PG_Application.git .

# Set ownership
chown -R ec2-user:ec2-user /opt/pgapp

# Build frontend
if [ -d "pg_application.client" ]; then
  cd pg_application.client
  sudo -u ec2-user npm install --legacy-peer-deps
  sudo -u ec2-user npm run build
  cd ..
fi

# Build backend
if [ -d "PG_Application.Server" ]; then
  cd PG_Application.Server
  sudo -u ec2-user dotnet restore
  sudo -u ec2-user dotnet publish -c Release -o /opt/pgapp/publish
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
User=ec2-user
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000
KillSignal=SIGINT
TimeoutStopSec=90
KillMode=process

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable pgapp

if [ -f "/opt/pgapp/publish/PG_Application.Server.dll" ]; then
  systemctl start pgapp
fi
EOF

  tags = {
    Name        = "PG-Application-Server"
    Project     = "DotNetCore8-React20"
    Environment = "Development"
  }
}
