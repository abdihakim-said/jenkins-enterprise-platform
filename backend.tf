terraform {
  # Partial backend configuration - supply bucket/table at init time:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example.
  backend "s3" {
    key     = "jenkins/dev/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
