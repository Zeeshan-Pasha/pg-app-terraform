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
  ami                    = "ami-09251aa2e0071bf5e" # Mumbai Amazon Linux 2 AMI
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail
echo "Starting setup..." > /var/log/user-data.log

yum update -y >> /var/log/user-data.log 2>&1
yum install -y git >> /var/log/user-data.log 2>&1

# Install .NET 8
rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm >> /var/log/user-data.log 2>&1 || true
yum install -y dotnet-sdk-8.0 >> /var/log/user-data.log 2>&1

# Install Node.js 20
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >> /var/log/user-data.log 2>&1
yum install -y nodejs >> /var/log/user-data.log 2>&1

# Clone app
mkdir -p /opt/pgapp && cd /opt/pgapp
git clone https://${var.github_user}:${urlencode(var.github_token)}@github.com/Zeeshan-Pasha/PG_Application.git . >> /var/log/user-data.log 2>&1

# Build frontend
if [ -d "pg_application.client" ]; then
  cd pg_application.client
  npm install --legacy-peer-deps >> /var/log/user-data.log 2>&1
  npm run build >> /var/log/user-data.log 2>&1
  cd ..
fi

# Build backend
if [ -d "PG_Application.Server" ]; then
  cd PG_Application.Server
  dotnet restore >> /var/log/user-data.log 2>&1
  dotnet publish -c Release -o /opt/pgapp/publish >> /var/log/user-data.log 2>&1
fi

# Create systemd service
cat >/etc/systemd/system/pgapp.service <<SERVICE
[Unit]
Description=PG Application
After=network.target

[Service]
WorkingDirectory=/opt/pgapp/publish
ExecStart=/usr/bin/dotnet PG_Application.Server.dll
Restart=always
User=ec2-user
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
    Project     = "DotNetCore8-React19"
    Environment = "Development"
  }
}
