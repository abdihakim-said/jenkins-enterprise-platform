output "ami_id" {
  description = "ID of the built Golden AMI"
  value       = data.aws_ami.jenkins_golden_latest.id
}

output "ami_name" {
  description = "Name of the built Golden AMI"
  value       = data.aws_ami.jenkins_golden_latest.name
}
