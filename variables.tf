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