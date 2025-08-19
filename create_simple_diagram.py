#!/usr/bin/env python3
"""
Jenkins Enterprise Platform - AWS Architecture Diagram Generator
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, AutoScaling
from diagrams.aws.network import ELB, InternetGateway, NATGateway, Route53
from diagrams.aws.storage import EFS, S3
from diagrams.aws.security import IAM, KMS
from diagrams.aws.management import CloudWatch, SNS
from diagrams.aws.general import Users

with Diagram(
    "Jenkins Enterprise Platform - AWS Architecture",
    filename="docs/diagrams/jenkins_architecture",
    show=False,
    direction="TB"
):
    
    users = Users("Users")
    dns = Route53("DNS")
    igw = InternetGateway("Internet\nGateway")
    alb = ELB("Application\nLoad Balancer")
    
    with Cluster("AWS VPC (10.0.0.0/16)"):
        
        with Cluster("Public Subnets"):
            nat = NATGateway("NAT\nGateway")
        
        with Cluster("Private Subnets"):
            asg = AutoScaling("Auto Scaling\nGroup")
            
            with Cluster("Jenkins Instances"):
                jenkins1 = EC2("Jenkins\nt3.medium\nAZ-1a")
                jenkins2 = EC2("Jenkins\nt3.medium\nAZ-1b") 
                jenkins3 = EC2("Jenkins\nt3.medium\nAZ-1c")
        
        with Cluster("Storage"):
            efs = EFS("EFS\nFile System")
            s3 = S3("S3\nBackup")
        
        with Cluster("Security & Monitoring"):
            iam = IAM("IAM")
            kms = KMS("KMS")
            cw = CloudWatch("CloudWatch")
            sns = SNS("SNS")
    
    # Connections
    users >> dns >> igw >> alb >> asg
    asg >> [jenkins1, jenkins2, jenkins3]
    [jenkins1, jenkins2, jenkins3] >> efs
    [jenkins1, jenkins2, jenkins3] >> s3
    [jenkins1, jenkins2, jenkins3] >> cw
    cw >> sns

print("✅ Architecture diagram created!")
print("📁 Location: docs/diagrams/jenkins_architecture.png")
