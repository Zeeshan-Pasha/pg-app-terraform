variable "aws_region" {
  description = "AWS region to deploy infrastructure"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "Instance type for EC2"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = "pg-app-key" # Change to your key pair
}

variable "docker_image" {
  description = "Docker image name for the application"
  type        = string
  default     = "zeeshan781/pg-application:latest"
}