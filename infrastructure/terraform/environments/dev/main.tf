terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cloudprojetofinal-tf-state-966289686735"
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "cloudprojetofinal-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
}

module "queue" {
  source      = "../../modules/queue"
  project     = var.project
  environment = var.environment
}

module "database" {
  source               = "../../modules/database"
  project              = var.project
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  db_security_group_id = module.vpc.db_security_group_id
  db_password          = var.db_password
}

module "compute" {
  source                = "../../modules/compute"
  project               = var.project
  environment           = var.environment
  public_subnet_ids     = module.vpc.public_subnet_ids
  app_security_group_id = module.vpc.app_security_group_id
  key_name              = var.key_name
  queue_arns            = [module.queue.order_created_queue_arn, module.queue.order_dlq_arn]
}