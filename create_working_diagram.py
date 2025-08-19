#!/usr/bin/env python3
"""
Jenkins Enterprise Platform - AWS Architecture Diagram
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, AutoScaling
from diagrams.aws.network import ELB, InternetGateway, NATGateway
from diagrams.aws.storage import EFS, S3
from diagrams.aws.security import IAM
from diagrams.aws.general import Users

# Create the architecture diagram
with Diagram(
    "Jenkins Enterprise Platform - AWS Architecture",
    filename="docs/diagrams/jenkins_enterprise_architecture",
    show=False,
    direction="TB",
    graph_attr={
        "fontsize": "16",
        "bgcolor": "white",
        "pad": "0.5"
    }
):
    
    # External users
    users = Users("Users")
    
    # Internet Gateway
    igw = InternetGateway("Internet Gateway")
    
    # Load Balancer
    alb = ELB("Application\nLoad Balancer\nstaging-jenkins-alb")
    
    # Main AWS infrastructure
    with Cluster("AWS Region: us-east-1", graph_attr={"bgcolor": "lightblue"}):
        
        with Cluster("VPC (10.0.0.0/16)", graph_attr={"bgcolor": "lightgreen"}):
            
            # Public subnet with NAT
            with Cluster("Public Subnets"):
                nat = NATGateway("NAT Gateway")
            
            # Private subnets with Jenkins
            with Cluster("Private Subnets (Multi-AZ)", graph_attr={"bgcolor": "lightyellow"}):
                
                # Auto Scaling Group
                asg = AutoScaling("Auto Scaling Group\n(1-3 instances)")
                
                # Jenkins instances
                with Cluster("Jenkins Instances"):
                    jenkins_1 = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1a")
                    jenkins_2 = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1b")
                    jenkins_3 = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1c")
            
            # Storage layer
            with Cluster("Storage Layer"):
                efs = EFS("EFS File System\nfs-091ff726614879a63\nPersistent Storage")
                s3_backup = S3("S3 Bucket\nBackup Storage")
                s3_logs = S3("S3 Bucket\nALB Access Logs")
        
        # Security and monitoring
        with Cluster("Security & Management", graph_attr={"bgcolor": "lightcoral"}):
            iam = IAM("IAM\nRoles & Policies")
    
    # Define the flow
    users >> Edge(label="HTTPS Traffic") >> igw
    igw >> Edge(label="Route Traffic") >> alb
    alb >> Edge(label="Load Balance") >> asg
    asg >> Edge(label="Manages") >> [jenkins_1, jenkins_2, jenkins_3]
    
    # Storage connections
    [jenkins_1, jenkins_2, jenkins_3] >> Edge(label="Persistent Data", style="dashed") >> efs
    [jenkins_1, jenkins_2, jenkins_3] >> Edge(label="Backup Data", style="dashed") >> s3_backup
    alb >> Edge(label="Access Logs", style="dashed") >> s3_logs
    
    # Security
    [jenkins_1, jenkins_2, jenkins_3] >> Edge(label="Access Control", style="dotted") >> iam

print("✅ Jenkins Enterprise Platform architecture diagram created!")
print("📁 File: docs/diagrams/jenkins_enterprise_architecture.png")
print("🎨 Professional AWS architecture with official icons")
