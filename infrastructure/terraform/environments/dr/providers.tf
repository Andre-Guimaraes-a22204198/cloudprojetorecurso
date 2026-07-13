# =============================================================
# Ambiente DR :: providers das tres regioes usadas
#   - primary : regiao que serve trafego normalmente
#   - standby : regiao de recuperacao (pilot-light)
#   - useast1 : Route 53 e as metricas dos health checks vivem
#               sempre em us-east-1, por isso o alarme fica aqui
# =============================================================

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket         = "cloudprojetofinal-tf-state-966289686735"
    key            = "envs/dr/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "cloudprojetofinal-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = {
      Project   = var.project
      Component = "dr"
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  alias  = "standby"
  region = var.standby_region
  default_tags {
    tags = {
      Project   = var.project
      Component = "dr"
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = var.project
      Component = "dr"
      ManagedBy = "terraform"
    }
  }
}
