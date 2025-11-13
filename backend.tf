terraform {
  backend "s3" {
    bucket         = "jenkins-tf-state-979033443535"
    key            = "jenkins/dev/terraform.tfstate"  # Correct path with actual infrastructure
    region         = "us-east-1"
    dynamodb_table = "jenkins-terraform-locks"
    encrypt        = true
  }
}
