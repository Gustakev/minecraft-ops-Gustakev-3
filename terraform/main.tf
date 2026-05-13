terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Security group: controls what traffic is allowed in/out
resource "aws_security_group" "minecraft" {
  name        = "minecraft-sg"
  description = "Allow SSH and Minecraft"
  vpc_id      = var.vpc_id

  # SSH: so Ansible can log in and configure the server
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Minecraft client port
  ingress {
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (needed to pull from ECR, S3)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The EC2 instance: the actual server
resource "aws_instance" "minecraft" {
  ami                         = "ami-05cf1e9f73fbad2e2" # Ubuntu 24.04 LTS us-east-1
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  # Attach the pre-existing LabInstanceProfile so the server can access ECR and S3
  iam_instance_profile = "LabInstanceProfile"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "minecraft-server"
  }
}

# Output the public IP so we know where to connect
output "public_ip" {
  value = aws_instance.minecraft.public_ip
}
