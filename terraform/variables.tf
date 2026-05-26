variable "vpc_id" {
  description = "The VPC to deploy into"
  type        = string
  default     = "vpc-09ef62184afb4ee56"
}

variable "subnet_id" {
  description = "The subnet to deploy into"
  type        = string
  default     = "subnet-05f710af868df1bd7"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
}

variable "my_ip" {
  description = "Your public IP in CIDR notation for SSH access (e.g. 1.2.3.4/32)"
  type        = string
}
