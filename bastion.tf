# Bastion Host for Jenkins Access
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu_bastion.id
  instance_type          = "t3.micro"
  key_name               = "dev-jenkins-enterprise-platform-key"
  subnet_id              = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.environment}-jenkins-bastion"
  }
}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.environment}-bastion-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Allow bastion to access Jenkins
resource "aws_security_group_rule" "bastion_to_jenkins" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = module.security_groups.jenkins_security_group_id
}

data "aws_ami" "ubuntu_bastion" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

output "bastion_ip" {
  value = aws_instance.bastion.public_ip
}
