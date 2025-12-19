variable "aws_region" {
  description = "AWS region to create resources in"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "agent_count" {
  description = "Number of Jenkins agent instances to create"
  type        = number
  default     = 2
}

variable "ssh_key_name_prefix" {
  description = "Prefix for key-pair name created by Terraform"
  type        = string
  default     = "jenkins-ansible-key"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to bastion and access Jenkins (override for security)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway so private instances can access internet"
  type        = bool
  default     = true
}

