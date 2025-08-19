#!/usr/bin/env python3
"""
Jenkins Enterprise Platform - AWS Architecture Diagram Generator
Creates a professional architecture diagram similar to the Robot Shop EKS diagram
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, AutoScaling, ApplicationLoadBalancer
from diagrams.aws.network import VPC, InternetGateway, NATGateway, Route53
from diagrams.aws.storage import EFS, S3
from diagrams.aws.security import IAM, KMS, GuardDuty, Config, CloudTrail
from diagrams.aws.management import CloudWatch, SNS
from diagrams.aws.general import Users
from diagrams.onprem.ci import Jenkins

# Configure diagram attributes
graph_attr = {
    "fontsize": "16",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
    "nodesep": "0.8",
    "ranksep": "1.0"
}

node_attr = {
    "fontsize": "12",
    "fontname": "Arial"
}

edge_attr = {
    "fontsize": "10",
    "fontname": "Arial"
}

with Diagram(
    "Jenkins Enterprise Platform - AWS Architecture",
    filename="docs/jenkins_enterprise_platform_architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr
):
    
    # Users
    users = Users("Users")
    
    # DNS and Internet Gateway
    dns = Route53("Route 53\nDNS")
    igw = InternetGateway("Internet Gateway\nigw-032928ad")
    
    # Application Load Balancer
    alb = ApplicationLoadBalancer("Application Load Balancer\nstaging-jenkins-alb")
    
    with Cluster("AWS Region: us-east-1"):
        
        with Cluster("VPC (10.0.0.0/16)\nvpc-0b221819e694d4c66"):
            
            # Public Subnets
            with Cluster("Public Subnets"):
                nat_gw = NATGateway("NAT Gateway\nnat-04382c9b")
            
            # Private Subnets with Jenkins Instances
            with Cluster("Private Subnets (Multi-AZ)"):
                
                # Auto Scaling Group
                asg = AutoScaling("Auto Scaling Group\n1-3 instances")
                
                # Jenkins Instances
                with Cluster("Jenkins Instances"):
                    jenkins_1 = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1a")
                    jenkins_2 = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1b")
                    jenkins_3 = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1c")
                    
                    jenkins_instances = [jenkins_1, jenkins_2, jenkins_3]
            
            # Storage
            with Cluster("Storage Layer"):
                efs = EFS("EFS File System\nfs-091ff726614879a63\nMulti-AZ Mounts")
                s3_backup = S3("S3 Backup\nJenkins Data")
                s3_logs = S3("S3 ALB Logs\nAccess Logs")
        
        # Security Services
        with Cluster("Security & Identity"):
            iam = IAM("IAM\nRoles & Policies")
            kms = KMS("KMS\nEncryption Keys")
            guardduty = GuardDuty("GuardDuty\nThreat Detection")
            config = Config("AWS Config\nCompliance")
            cloudtrail = CloudTrail("CloudTrail\nAPI Auditing")
        
        # Monitoring Services
        with Cluster("Monitoring & Alerting"):
            cloudwatch = CloudWatch("CloudWatch\nMetrics & Logs")
            sns = SNS("SNS\nAlert Notifications")
    
    # Define connections with labels
    users >> Edge(label="HTTPS") >> dns
    dns >> Edge(label="DNS Resolution") >> igw
    igw >> Edge(label="Internet Traffic") >> alb
    alb >> Edge(label="Load Balanced") >> asg
    asg >> Edge(label="Manages") >> jenkins_instances
    
    # Storage connections
    jenkins_instances >> Edge(label="Persistent Data", style="dashed") >> efs
    jenkins_instances >> Edge(label="Backup", style="dashed") >> s3_backup
    alb >> Edge(label="Access Logs", style="dashed") >> s3_logs
    
    # Security connections
    jenkins_instances >> Edge(label="Encrypted", style="dotted") >> kms
    jenkins_instances >> Edge(label="Access Control", style="dotted") >> iam
    
    # Monitoring connections
    jenkins_instances >> Edge(label="Metrics & Logs", style="dotted") >> cloudwatch
    cloudwatch >> Edge(label="Alerts", style="dotted") >> sns
    
    # Security monitoring
    guardduty >> Edge(label="Threat Analysis", style="dotted") >> cloudwatch
    config >> Edge(label="Compliance", style="dotted") >> cloudwatch
    cloudtrail >> Edge(label="Audit Logs", style="dotted") >> cloudwatch

print("✅ Architecture diagram generated successfully!")
print("📁 Location: docs/jenkins_enterprise_platform_architecture.png")
print("🎨 Professional AWS architecture diagram created with official icons")
