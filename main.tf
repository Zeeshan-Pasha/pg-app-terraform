resource "aws_instance" "example" {
  ami           = "ami-09251aa2e0071bf5e"  # Your Mumbai region AMI
  instance_type = var.instance_type
  
  # Basic security group allowing SSH and web traffic
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  # User data script to install .NET 8 and Node.js 20 for your app
  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              echo "Starting user-data script execution..."
              
              # Update system
              yum update -y
              
              # Install .NET 8 SDK
              echo "Installing .NET 8 SDK..."
              rpm -Uvh https://packages.microsoft.com/config/centos/7/packages-microsoft-prod.rpm
              yum install -y dotnet-sdk-8.0
              
              # Verify .NET installation
              dotnet --version && echo ".NET installed successfully" || echo ".NET installation failed"
              
              # Install Node.js 20
              echo "Installing Node.js 20..."
              curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
              yum install -y nodejs
              
              # Verify Node.js installation
              node --version && echo "Node.js installed successfully" || echo "Node.js installation failed"
              npm --version && echo "npm installed successfully" || echo "npm installation failed"
              
              # Install Git
              echo "Installing Git..."
              yum install -y git
              
              # Create app directory
              echo "Creating app directory..."
              mkdir -p /opt/pgapp
              chown ec2-user:ec2-user /opt/pgapp
              cd /opt/pgapp
              
              # Clone your application with better error handling
              echo "Cloning application repository..."
              if git clone https://github.com/Zeeshan-Pasha/PG_Application.git temp; then
                  echo "Repository cloned successfully"
                  mv temp/* . 2>/dev/null || true
                  mv temp/.* . 2>/dev/null || true
                  rm -rf temp
                  chown -R ec2-user:ec2-user /opt/pgapp
                  echo "Repository files moved and ownership changed"
              else
                  echo "Failed to clone repository - creating empty structure"
                  mkdir -p pg_application.client PG_Application.Server
                  chown -R ec2-user:ec2-user /opt/pgapp
              fi
              
              # List what we have
              echo "Contents of /opt/pgapp:"
              ls -la /opt/pgapp/
              
              # Create startup script
              echo "Creating startup script..."
              cat > /opt/pgapp/start-app.sh << 'SCRIPT'
#!/bin/bash
cd /opt/pgapp

echo "Building React frontend..."
if [ -d "pg_application.client" ]; then
    cd pg_application.client
    npm install --legacy-peer-deps
    npm run build
    cd ..
    echo "React frontend built successfully"
else
    echo "Frontend directory not found"
fi

echo "Building .NET backend..."
if [ -d "PG_Application.Server" ]; then
    cd PG_Application.Server
    dotnet restore
    dotnet publish -c Release -o ../publish
    cd ../publish
    echo ".NET backend built successfully"
else
    echo "Backend directory not found"
    exit 1
fi

echo "Starting .NET application..."
export ASPNETCORE_URLS=http://0.0.0.0:5000
nohup dotnet PG_Application.Server.dll > /opt/pgapp/app.log 2>&1 &
echo $! > /opt/pgapp/app.pid

echo "Application started on port 5000"
SCRIPT

              chmod +x /opt/pgapp/start-app.sh
              
              # Create systemd service for auto-start
              echo "Creating systemd service..."
              cat > /etc/systemd/system/pgapp.service << 'SERVICE'
[Unit]
Description=PG Application (.NET 8 + React 19)
After=network.target

[Service]
Type=forking
User=ec2-user
WorkingDirectory=/opt/pgapp
ExecStart=/opt/pgapp/start-app.sh
ExecStop=/bin/kill -TERM $MAINPID
PIDFile=/opt/pgapp/app.pid
Restart=always
RestartSec=10
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000

[Install]
WantedBy=multi-user.target
SERVICE

              systemctl daemon-reload
              systemctl enable pgapp
              
              echo "Waiting 60 seconds before starting application..."
              sleep 60
              
              echo "Starting pgapp service..."
              systemctl start pgapp
              
              echo "Checking service status..."
              systemctl status pgapp
              
              echo "User-data script completed!"
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