terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-northeast-1"
  profile = "tw-beach"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.prefix}-test-vpc"
  cidr = "10.0.0.0/16"

  azs = data.aws_availability_zones.azs.names
  database_subnets = ["10.0.4.0/24"]
  private_subnets = ["10.0.3.0/24"]
  public_subnets = ["10.0.2.0/24", "10.0.10.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false

  create_database_subnet_group = false
  create_database_nat_gateway_route = false
  create_database_subnet_route_table = true

  tags = {
    Owner = "lu"
  }
}

module "public_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name = "${var.prefix}-public-sg"
  description = "security-group for web tier"
  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "internal"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 22
      to_port     = 80
      protocol    = "tcp"
      description = "ssh and nginx port"
      cidr_blocks = var.my-ip
    },
    {
      from_port   = 8000
      to_port     = 10000
      protocol    = "tcp"
      description = "Service name"
      cidr_blocks = var.my-ip
    }
    ]

    egress_with_cidr_blocks = [
      {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "egress"
      cidr_blocks = "0.0.0.0/0"
    }
    ]
}

module "private_sg" {
  source = "terraform-aws-modules/security-group/aws"
  
  name = "${var.prefix}-private-sg"
  description = "security-group for app tier"
  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "tcp"
      description = "internal"
      cidr_blocks = module.vpc.vpc_cidr_block
    }
    ]

    egress_with_cidr_blocks = [
      {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "egress"
      cidr_blocks = "0.0.0.0/0"
    }
    ]
}

module "db_sg" {
  source = "terraform-aws-modules/security-group/aws"
  
  name = "${var.prefix}-db-sg"
  description = "security-group for db tier"
  vpc_id = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "tcp"
      description = "internal"
      cidr_blocks = module.vpc.vpc_cidr_block
    }
    ]

    egress_with_cidr_blocks = [
      {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "internal"
      cidr_blocks = module.vpc.vpc_cidr_block
    }
    ]
}

module "web_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"

  name = "${var.prefix}-web-autoscaling"

  min_size = 1
  max_size = 3
  desired_capacity = 1
  wait_for_capacity_timeout = 0
  default_instance_warmup = 300
  health_check_type = "EC2"
  vpc_zone_identifier = [module.vpc.public_subnets[0]]

  launch_template_name = "${var.prefix}-web-template"
  launch_template_description = "${var.prefix} web machine launch template"

  image_id = var.ami
  instance_type = "t3.micro"
  user_data = filebase64("${path.module}/web_init.sh")
  security_groups = [module.public_sg.security_group_id]
  key_name = "lu-aws"

  block_device_mappings = [
    {
      device_name = "/dev/sda1"

      ebs = {
        volume_size = 10
      }
    }
  ]

  cpu_options = {
    core_count       = 1
    threads_per_core = 2
  }

  network_interfaces = [
    {
      delete_on_termination = true
      description = "eth0"
      device_index = 0
      associate_public_ip_address = true
      subnet_id = module.vpc.public_subnets[0]
      security_groups = [module.public_sg.security_group_id]
    }
  ]

  tag_specifications = [
    {
      resource_type = "instance"
      tags = { Owner = "lu" }
    }
  ]

  scaling_policies = {
    avg-cpu-policy-greater-than-50 = {
      policy_type               = "TargetTrackingScaling"
      estimated_instance_warmup = 300
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = 50.0
      }
    }
  }
}