terraform {
  required_version = ">= 1.8.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.46.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.5"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = "../terraform.tfstate"
  }
}