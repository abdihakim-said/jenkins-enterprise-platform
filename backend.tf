terraform {
  backend "s3" {
    bucket = "jenkins-enterprise-platform-terraform-state"
    key    = "dev/terraform.tfstate"
    region = "us-east-1"
  }
}
