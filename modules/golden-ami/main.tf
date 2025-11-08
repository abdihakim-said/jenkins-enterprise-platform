# Golden AMI Module - Story 2.4: Terraform calling Packer
# Author: Abdihakim Said

resource "null_resource" "golden_ami_build" {
  triggers = {
    setup_script_hash  = filemd5("${path.root}/packer/scripts/setup.sh")
    packer_config_hash = filemd5("${path.root}/packer/jenkins-ami.pkr.hcl")
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.root}/packer
      packer init jenkins-ami.pkr.hcl
      packer build \
        -var "environment=${var.environment}" \
        jenkins-ami.pkr.hcl
    EOT
  }
}

data "aws_ami" "jenkins_golden_latest" {
  depends_on = [null_resource.golden_ami_build]

  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["jenkins-golden-ami-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
