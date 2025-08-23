resource "aws_instance" "example" {
  ami           = "ami-09251aa2e0071bf5e"  # Your Mumbai region AMI
  instance_type = var.instance_type
  
  # Basic security group allowing SSH and web traffic
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  # User data script to install .NET 8 and Node.js 20 for your app
  user_data = <<-EOF
#!/bin/bash
echo "Starting user-data script execution..." > /var/log/user-data.log

# Install Git first (move this earlier)
yum install -y git >> /var/log/user-data.log 2>&1

# Update system
yum update -y >> /var/log/user-data.log 2>&1

# Install Git early
yum install -y git >> /var/log/user-data.log 2>&1

# Install .NET 8 SDK
rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm >> /var/log/user-data.log 2>&1
yum install -y dotnet-sdk-8.0 >> /var/log/user-data.log 2>&1

# Install Node.js 20
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - >> /var/log/user-data.log 2>&1
yum install -y nodejs >> /var/log/user-data.log 2>&1

# Clone app
mkdir -p /opt/pgapp
cd /opt/pgapp
git clone https://github.com/Zeeshan-Pasha/PG_Application.git . >> /var/log/user-data.log 2>&1
chown -R ec2-user:ec2-user /opt/pgapp

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
  dotnet publish -c Release -o ../publish >> /var/log/user-data.log 2>&1
  cd ../publish
  nohup dotnet PG_Application.Server.dll > /opt/pgapp/app.log 2>&1 &
fi

echo "User-data script completed" >> /var/log/user-data.log
EOF
  
  tags = {
    Name = "PG-Application-Server"
    Project = "DotNetCore8-React19"
    Environment = "Development"
  }
}

# Security Group for web application
resource "aws_security_group" "web_sg" {
  name_prefix = "pg-app-sg"
  description = "Security group for PG Application (.NET 8 + React 19)"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # .NET 8 application port (matches your Dockerfile EXPOSE)
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = ".NET 8 application port"
  }

  # Vite dev server port (for development)
  ingress {
    from_port   = 5173
    to_port     = 5173
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Vite dev server port"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "PG-App-Security-Group"
    Project = "DotNetCore8-React19"
  }
}