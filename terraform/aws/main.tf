terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Generate SSH private & public key locally
resource "tls_private_key" "ansible_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload Public key to AWS
resource "aws_key_pair" "ansible" {
  key_name   = "${var.ssh_key_name_prefix}-${terraform.workspace}"
  public_key = tls_private_key.ansible_key.public_key_openssh
}

# Save the private key locally as a .pem file
resource "local_file" "private_key_pem" {
  content         = tls_private_key.ansible_key.private_key_pem
  filename        = "${path.module}/ssh/${aws_key_pair.ansible.key_name}.pem"
  file_permission = "0600"
}

# Create VPC and subnets (public + private)
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = { Name = "jenkins-vpc-${terraform.workspace}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "jenkins-igw-${terraform.workspace}" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  tags                    = { Name = "jenkins-public-${terraform.workspace}" }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_cidr
  tags       = { Name = "jenkins-private-${terraform.workspace}" }
}

# Public route table and route
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "jenkins-public-rt-${terraform.workspace}" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway for private subnet internet access (optional)
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0
}

resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.enable_nat_gateway ? aws_nat_gateway.nat[0].id : aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# IAM role for EC2 to allow SSM and other actions
resource "aws_iam_role" "ec2_role" {
  name               = "jenkins-ec2-role-${terraform.workspace}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "jenkins-ec2-profile-${terraform.workspace}"
  role = aws_iam_role.ec2_role.name
}

# Security groups: bastion (public), controller (private), agent (private)
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg-${terraform.workspace}"
  description = "Bastion SG allowing SSH from admin CIDR"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "controller_sg" {
  name        = "controller-sg-${terraform.workspace}"
  description = "Controller SG allowing Jenkins (8080) from admin CIDR and agent port from agents SG"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    from_port       = 50000
    to_port         = 50000
    protocol        = "tcp"
    security_groups = [aws_security_group.agents_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "agents_sg" {
  name        = "agents-sg-${terraform.workspace}"
  description = "Agents SG allowing outbound to controller agent port and SSH from bastion"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Bastion host in public subnet
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ansible.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  tags                        = { Name = "bastion-${terraform.workspace}" }
  associate_public_ip_address = true
  user_data                   = <<-EOF
              #!/bin/bash
              set -euo pipefail
              # Bootstrap bastion: create non-root 'ansible' user and enable sudo
              apt-get update -y
              apt-get install -y python3 python3-pip sudo openssh-server

              ANSIBLE_PUBKEY="${tls_private_key.ansible_key.public_key_openssh}"

              if ! id -u ansible >/dev/null 2>&1; then
                useradd -m -s /bin/bash ansible
                mkdir -p /home/ansible/.ssh
                echo "$${ANSIBLE_PUBKEY}" > /home/ansible/.ssh/authorized_keys
                chown -R ansible:ansible /home/ansible/.ssh
                chmod 700 /home/ansible/.ssh
                chmod 600 /home/ansible/.ssh/authorized_keys
                usermod -aG sudo ansible
              fi

              # SSH hardening: disable password auth
              sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || true
              sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
              systemctl restart ssh || true
              EOF
}

# Controller instance (private)
resource "aws_instance" "controller" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ansible.key_name
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.controller_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  # Allow optionally assigning a public IP for the controller (useful for demos)
  associate_public_ip_address = var.controller_public
  tags                        = { Name = "jenkins-controller-${terraform.workspace}" }
  user_data                   = <<-EOF
              #!/bin/bash
              set -euo pipefail
              # Bootstrap for Ansible management (SSM + python) and create 'ansible' user
              apt-get update -y
              apt-get install -y python3 python3-apt python3-distutils python3-pip ca-certificates apt-transport-https sudo
              python3 -m pip install --upgrade pip setuptools || true
              # Try to install SSM agent if available
              apt-get install -y amazon-ssm-agent || true

              ANSIBLE_PUBKEY="${tls_private_key.ansible_key.public_key_openssh}"
              if ! id -u ansible >/dev/null 2>&1; then
                useradd -m -s /bin/bash ansible
                mkdir -p /home/ansible/.ssh
                echo "$${ANSIBLE_PUBKEY}" > /home/ansible/.ssh/authorized_keys
                chown -R ansible:ansible /home/ansible/.ssh
                chmod 700 /home/ansible/.ssh
                chmod 600 /home/ansible/.ssh/authorized_keys
                usermod -aG sudo ansible
              fi

              # SSH hardening
              sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || true
              sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
              systemctl restart ssh || true
              EOF
}

# Agent instances (private)
resource "aws_instance" "agents" {
  count                       = var.agent_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ansible.key_name
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.agents_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = false
  tags                        = { Name = "jenkins-agent-${count.index + 1}-${terraform.workspace}" }
  user_data                   = <<-EOF
              #!/bin/bash
              set -euo pipefail
              apt-get update -y
              apt-get install -y python3 python3-apt python3-distutils python3-pip ca-certificates apt-transport-https sudo
              python3 -m pip install --upgrade pip setuptools || true
              apt-get install -y amazon-ssm-agent || true

              ANSIBLE_PUBKEY="${tls_private_key.ansible_key.public_key_openssh}"
              if ! id -u ansible >/dev/null 2>&1; then
                useradd -m -s /bin/bash ansible
                mkdir -p /home/ansible/.ssh
                echo "$${ANSIBLE_PUBKEY}" > /home/ansible/.ssh/authorized_keys
                chown -R ansible:ansible /home/ansible/.ssh
                chmod 700 /home/ansible/.ssh
                chmod 600 /home/ansible/.ssh/authorized_keys
                usermod -aG sudo ansible
              fi

              sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || true
              sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || true
              systemctl restart ssh || true
              EOF
}
