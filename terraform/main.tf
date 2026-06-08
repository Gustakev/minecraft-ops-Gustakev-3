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

resource "aws_security_group" "minecraft" {
  name        = "minecraft-k8s-sg"
  description = "Allow SSH and Minecraft"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from known source"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "minecraft" {
  ami                         = "ami-05cf1e9f73fbad2e2" # Ubuntu 24.04 LTS us-east-1
  instance_type               = "t3.large" # 8GB RAM: This provides headroom for k3s, Minecraft, and a monitoring stack
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  iam_instance_profile        = "LabInstanceProfile"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/cloud-init.sh", {
    ecr_registry = "767398024557.dkr.ecr.us-east-1.amazonaws.com"
    image_name   = "767398024557.dkr.ecr.us-east-1.amazonaws.com/minecraft-server"
    image_tag    = "v1.0.0"
    s3_bucket    = "minecraft-world-767398024557"
    motd         = "Kevin Gustafson: 934-499-457"
  })

  tags = {
    Name = "minecraft-k8s"
  }
}

output "public_ip" {
  value = aws_instance.minecraft.public_ip
}
