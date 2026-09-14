terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "bret-terraform-state-2026"
    key          = "identity/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
    profile      = "security-admin"
  }
}

resource "aws_s3_object" "screenshots" {
  bucket = "bret-terraform-state-2026"
  key    = "identity/server-screenshot.png"
  etag   = filemd5("server-screenshot.png")
}