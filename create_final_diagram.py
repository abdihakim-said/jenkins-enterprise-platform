#!/usr/bin/env python3
"""
Jenkins Enterprise Platform - Enhanced AWS Architecture Diagram
Based on comprehensive ARCHITECTURE-DIAGRAM.md specifications
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, AutoScaling
from diagrams.aws.network import ELB, InternetGateway, NATGateway, Route53
from diagrams.aws.storage import EFS, S3
from diagrams.aws.security import IAM, KMS
from diagrams.aws.general import Users, General
from diagrams.onprem.network import Internet

# Professional diagram configuration
graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "1.2",
    "splines": "ortho",
    "nodesep": "1.2",
    "ranksep": "2.0",
    "dpi": "300"
}

node_attr = {
    "fontsize": "12",
    "fontname": "Arial Bold",
    "margin": "0.2"
}

edge_attr = {
    "fontsize": "10",
    "fontname": "Arial",
    "color": "#4B9CD3",
    "penwidth": "2"
}

with Diagram(
    "Jenkins Enterprise Platform - AWS Architecture",
    filename="docs/diagrams/jenkins_enterprise_detailed_architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr
):
    
    # External users and internet
    users = Users("Users\nDevelopers & DevOps")
    internet = Internet("Internet")
    
    with Cluster("AWS Cloud - Region: us-east-1", graph_attr={"bgcolor": "#E3F2FD", "style": "rounded,bold", "penwidth": "3"}):
        
        # DNS and Gateway layer
        route53 = Route53("Route 53\nDNS Resolution\nHealth Checks")
        igw = InternetGateway("Internet Gateway\nigw-032928ad\nPublic Access")
        
        # Application Load Balancer
        alb = ELB("Application Load Balancer\nstaging-jenkins-alb\nHTTP:80 | HTTPS:443\nSSL Termination")
        
        with Cluster("VPC (10.0.0.0/16)\nvpc-0b221819e694d4c66", graph_attr={"bgcolor": "#F1F8E9", "style": "rounded,bold", "penwidth": "2"}):
            
            # Public Subnets Cluster
            with Cluster("Public Subnets - Multi-AZ", graph_attr={"bgcolor": "#E8F5E8", "style": "rounded"}):
                nat_gw = NATGateway("NAT Gateway\nnat-04382c9beb\nOutbound Internet")
                pub_subnet_1b = General("Public Subnet\nus-east-1b\n10.0.2.0/24")
                pub_subnet_1c = General("Public Subnet\nus-east-1c\n10.0.3.0/24")
            
            # Private Subnets with Jenkins Infrastructure
            with Cluster("Private Subnets - Multi-AZ Deployment", graph_attr={"bgcolor": "#FFF3E0", "style": "rounded,bold"}):
                
                # Auto Scaling Group
                asg = AutoScaling("Auto Scaling Group\nMin: 1, Max: 3, Desired: 1\nCPU-based Scaling\nHealth Checks")
                
                # Jenkins Instances Cluster
                with Cluster("Jenkins Master Instances", graph_attr={"bgcolor": "#FFECB3", "style": "rounded"}):
                    jenkins_1a = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1a\nJava 17")
                    jenkins_1b = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1b\nJava 17")
                    jenkins_1c = EC2("Jenkins Master\nt3.medium\nGolden AMI\nus-east-1c\nJava 17")
                    
                    jenkins_instances = [jenkins_1a, jenkins_1b, jenkins_1c]
            
            # Storage Infrastructure
            with Cluster("Storage Layer", graph_attr={"bgcolor": "#FCE4EC", "style": "rounded"}):
                efs = EFS("EFS File System\nfs-091ff726614879a63\nMulti-AZ Mount Targets\nGeneral Purpose\nPersistent Jenkins Data")
                s3_backup = S3("S3 Backup Bucket\nJenkins Data Backup\nVersioning Enabled\nCross-Region Replication")
                s3_logs = S3("S3 Access Logs\nALB Access Logs\nCloudTrail Logs\nCompliance & Audit")
        
        # Security & Identity Management
        with Cluster("Security & Identity", graph_attr={"bgcolor": "#FFEBEE", "style": "rounded,bold"}):
            iam = IAM("IAM\nRoles & Policies\nLeast Privilege\nJenkins Instance Role")
            kms = KMS("KMS\nCustomer Managed Keys\nData Encryption\nAt Rest & In Transit")
            
            # Security Services
            guardduty = General("GuardDuty\nThreat Detection\nMalware Protection\nAnomaly Detection")
            config = General("AWS Config\nCompliance Monitoring\nConfiguration Drift\nCIS Benchmarks")
            cloudtrail = General("CloudTrail\nAPI Audit Logging\nGovernance\nCompliance")
        
        # Monitoring & Operations
        with Cluster("Monitoring & Alerting", graph_attr={"bgcolor": "#F3E5F5", "style": "rounded,bold"}):
            cloudwatch = General("CloudWatch\nMetrics & Logs\nCustom Dashboards\nPerformance Monitoring")
            sns = General("SNS\nAlert Notifications\nEmail & Slack\nCritical Events")
            vpc_logs = General("VPC Flow Logs\nNetwork Traffic\nSecurity Analysis\nThreat Detection")
    
    # Primary traffic flow
    users >> Edge(label="HTTPS Requests", style="bold", color="#2E7D32") >> internet
    internet >> Edge(label="DNS Lookup", color="#2E7D32") >> route53
    route53 >> Edge(label="Route to AWS", color="#2E7D32") >> igw
    igw >> Edge(label="Public Traffic", style="bold", color="#2E7D32") >> alb
    
    # Load balancing and auto scaling
    alb >> Edge(label="Load Balanced\nHealth Checked\nSticky Sessions", style="bold", color="#1976D2") >> asg
    asg >> Edge(label="Instance Management\nAuto Scaling", color="#1976D2") >> jenkins_instances
    
    # Outbound internet access
    jenkins_instances >> Edge(label="Package Updates\nPlugin Downloads", style="dashed", color="#FF9800") >> nat_gw
    nat_gw >> Edge(label="Outbound Internet", style="dashed", color="#FF9800") >> igw
    
    # Storage connections
    jenkins_instances >> Edge(label="Jenkins Home\nWorkspace Data\nBuild Artifacts", style="dotted", color="#E65100", penwidth="3") >> efs
    jenkins_instances >> Edge(label="Automated Backups\nDisaster Recovery", style="dotted", color="#E65100") >> s3_backup
    alb >> Edge(label="Access Logs\nRequest Tracking", style="dotted", color="#E65100") >> s3_logs
    
    # Security and access control
    jenkins_instances >> Edge(label="IAM Role\nPermissions\nAccess Control", style="dotted", color="#D32F2F") >> iam
    [efs, s3_backup, s3_logs] >> Edge(label="KMS Encryption\nData Protection", style="dotted", color="#D32F2F") >> kms
    
    # Monitoring and alerting
    jenkins_instances >> Edge(label="Application Metrics\nSystem Logs\nPerformance Data", style="dotted", color="#7B1FA2") >> cloudwatch
    alb >> Edge(label="Load Balancer Metrics\nResponse Times", style="dotted", color="#7B1FA2") >> cloudwatch
    cloudwatch >> Edge(label="Critical Alerts\nThreshold Breaches", style="dotted", color="#7B1FA2") >> sns
    
    # Security monitoring integration
    [guardduty, config, cloudtrail] >> Edge(label="Security Events\nCompliance Data\nAudit Logs", style="dotted", color="#7B1FA2") >> cloudwatch
    vpc_logs >> Edge(label="Network Analysis\nThreat Intelligence", style="dotted", color="#7B1FA2") >> guardduty

print("✅ Enhanced Jenkins Enterprise Platform architecture diagram created!")
print("📁 Location: docs/diagrams/jenkins_enterprise_detailed_architecture.png")
print("")
print("🎨 Enhanced Features:")
print("   ✅ High-resolution (300 DPI) for professional presentation")
print("   ✅ Color-coded service clusters for visual organization")
print("   ✅ Detailed component specifications and descriptions")
print("   ✅ Complete data flow visualization with labeled connections")
print("   ✅ Security, monitoring, and storage layers clearly defined")
print("   ✅ Multi-AZ deployment architecture representation")
print("   ✅ Professional AWS styling with proper spacing")
print("")
print("🏗️ Architecture Highlights:")
print("   • Multi-AZ deployment across 3 availability zones")
print("   • Auto-scaling Jenkins instances with Golden AMI")
print("   • Comprehensive security with GuardDuty, Config, CloudTrail")
print("   • Persistent storage with EFS and S3 backup strategy")
print("   • Complete monitoring with CloudWatch and SNS alerting")
print("   • Enterprise-grade security with IAM and KMS encryption")
