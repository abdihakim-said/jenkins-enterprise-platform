#!/usr/bin/env python3
"""
Jenkins Enterprise Platform - Enhanced AWS Architecture Diagram
Creates a comprehensive visual diagram based on ARCHITECTURE-DIAGRAM.md specifications
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, AutoScaling
from diagrams.aws.network import ELB, InternetGateway, NATGateway, Route53, VPC
from diagrams.aws.storage import EFS, S3
from diagrams.aws.security import IAM, KMS
from diagrams.aws.management import Cloudwatch, SNS
from diagrams.aws.general import Users, General
from diagrams.onprem.network import Internet

# Enhanced diagram configuration
graph_attr = {
    "fontsize": "18",
    "bgcolor": "white",
    "pad": "1.0",
    "splines": "ortho",
    "nodesep": "1.0",
    "ranksep": "1.5",
    "dpi": "300"
}

node_attr = {
    "fontsize": "11",
    "fontname": "Arial Bold",
    "margin": "0.1"
}

edge_attr = {
    "fontsize": "9",
    "fontname": "Arial",
    "color": "#4B9CD3"
}

with Diagram(
    "Jenkins Enterprise Platform - AWS Architecture",
    filename="docs/diagrams/jenkins_enterprise_comprehensive_architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr
):
    
    # External layer
    users = Users("Users")
    internet = Internet("Internet")
    
    with Cluster("AWS Cloud - Region: us-east-1", graph_attr={"bgcolor": "#E3F2FD", "style": "rounded"}):
        
        # DNS and Gateway
        route53 = Route53("Route 53\nDNS Resolution")
        igw = InternetGateway("Internet Gateway\nigw-032928ad")
        
        # Load Balancer
        alb = ELB("Application Load Balancer\nstaging-jenkins-alb\nHTTP:80 | HTTPS:443")
        
        with Cluster("VPC (10.0.0.0/16)\nvpc-0b221819e694d4c66", graph_attr={"bgcolor": "#F1F8E9", "style": "rounded"}):
            
            # Public Subnets
            with Cluster("Public Subnets", graph_attr={"bgcolor": "#E8F5E8", "style": "rounded"}):
                with Cluster("us-east-1a\n10.0.1.0/24"):
                    nat_gw = NATGateway("NAT Gateway\nnat-04382c9beb")
                
                pub_subnet_b = General("Public Subnet\nus-east-1b\n10.0.2.0/24")
                pub_subnet_c = General("Public Subnet\nus-east-1c\n10.0.3.0/24")
            
            # Private Subnets with Jenkins
            with Cluster("Private Subnets (Multi-AZ)", graph_attr={"bgcolor": "#FFF3E0", "style": "rounded"}):
                
                # Auto Scaling Group
                asg = AutoScaling("Auto Scaling Group\n1-3 instances\nHealth Checks")
                
                with Cluster("Jenkins Instances", graph_attr={"bgcolor": "#FFECB3", "style": "rounded"}):
                    jenkins_1a = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1a")
                    jenkins_1b = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1b")
                    jenkins_1c = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1c")
                    
                    jenkins_instances = [jenkins_1a, jenkins_1b, jenkins_1c]
            
            # Storage Layer
            with Cluster("Storage Layer", graph_attr={"bgcolor": "#FCE4EC", "style": "rounded"}):
                efs = EFS("EFS File System\nfs-091ff726614879a63\nMulti-AZ Mount Targets\nPersistent Storage")
                s3_backup = S3("S3 Backup Bucket\nJenkins Data\nCross-Region Backup")
                s3_logs = S3("S3 Access Logs\nALB Logs\nAudit Trail")
        
        # Security & Identity Services
        with Cluster("Security & Identity", graph_attr={"bgcolor": "#FFEBEE", "style": "rounded"}):
            iam = IAM("IAM\nRoles & Policies\nLeast Privilege")
            kms = KMS("KMS\nEncryption Keys\nData Protection")
            
            # Additional security services (represented as general icons)
            guardduty = General("GuardDuty\nThreat Detection")
            config = General("AWS Config\nCompliance Monitoring")
            cloudtrail = General("CloudTrail\nAPI Audit Logging")
        
        # Monitoring & Management
        with Cluster("Monitoring & Alerting", graph_attr={"bgcolor": "#F3E5F5", "style": "rounded"}):
            cloudwatch = Cloudwatch("CloudWatch\nMetrics & Logs\nCustom Dashboards")
            sns = SNS("SNS\nAlert Notifications\nEmail & Slack")
            
            # VPC Flow Logs
            vpc_logs = General("VPC Flow Logs\nNetwork Monitoring")
    
    # Define the traffic flow
    users >> Edge(label="HTTPS Traffic", style="bold") >> internet
    internet >> Edge(label="DNS Resolution") >> route53
    route53 >> Edge(label="Route Traffic") >> igw
    igw >> Edge(label="Internet Access") >> alb
    
    # Load balancer to instances
    alb >> Edge(label="Load Balanced\nHealth Checked", style="bold") >> asg
    asg >> Edge(label="Manages Instances") >> jenkins_instances
    
    # NAT Gateway for outbound
    nat_gw >> Edge(label="Outbound Internet", style="dashed") >> igw
    jenkins_instances >> Edge(label="Updates & Packages", style="dashed") >> nat_gw
    
    # Storage connections
    jenkins_instances >> Edge(label="Persistent Data\nJenkins Home", style="dotted", color="#FF9800") >> efs
    jenkins_instances >> Edge(label="Backup Data", style="dotted", color="#FF9800") >> s3_backup
    alb >> Edge(label="Access Logs", style="dotted", color="#FF9800") >> s3_logs
    
    # Security connections
    jenkins_instances >> Edge(label="Access Control", style="dotted", color="#F44336") >> iam
    [efs, s3_backup, s3_logs] >> Edge(label="Encryption", style="dotted", color="#F44336") >> kms
    
    # Monitoring connections
    jenkins_instances >> Edge(label="Metrics & Logs", style="dotted", color="#9C27B0") >> cloudwatch
    alb >> Edge(label="Performance Metrics", style="dotted", color="#9C27B0") >> cloudwatch
    cloudwatch >> Edge(label="Alerts", style="dotted", color="#9C27B0") >> sns
    
    # Security monitoring
    [guardduty, config, cloudtrail] >> Edge(label="Security Events", style="dotted", color="#9C27B0") >> cloudwatch
    vpc_logs >> Edge(label="Network Analysis", style="dotted", color="#9C27B0") >> guardduty

print("✅ Enhanced Jenkins Enterprise Platform architecture diagram created!")
print("📁 Location: docs/diagrams/jenkins_enterprise_comprehensive_architecture.png")
print("🎨 Features:")
print("   - High-resolution (300 DPI)")
print("   - Color-coded service clusters")
print("   - Detailed component specifications")
print("   - Professional AWS styling")
print("   - Complete data flow visualization")
