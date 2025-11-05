#!/usr/bin/env python3
"""
Jenkins Enterprise Platform - Complete Blue-Green Architecture Diagram
Generates comprehensive enterprise architecture with all AWS services
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, AutoScaling, Lambda, EC2Instance, AMI
from diagrams.aws.network import ALB, VPC, PrivateSubnet, PublicSubnet, NATGateway, InternetGateway, RouteTable
from diagrams.aws.storage import EFS, EBS, S3
from diagrams.aws.management import Cloudwatch, CloudwatchLogs, CloudwatchAlarm, SystemsManager, Config, Cloudtrail
from diagrams.aws.security import IAM, KMS
from diagrams.aws.integration import SNS, Eventbridge
from diagrams.aws.devtools import Codebuild
from diagrams.aws.general import Users

def generate_enterprise_architecture():
    """Generate complete Jenkins Enterprise Platform architecture"""
    
    graph_attr = {
        "fontsize": "16",
        "bgcolor": "white",
        "pad": "1.0",
        "splines": "ortho",
        "nodesep": "1.0",
        "ranksep": "1.5"
    }
    
    with Diagram(
        "Jenkins Enterprise Platform - Complete Blue-Green Architecture",
        show=False,
        direction="TB",
        filename="jenkins_enterprise_complete_architecture",
        graph_attr=graph_attr
    ):
        
        # External Users
        with Cluster("External Access", graph_attr={"bgcolor": "lightgray", "style": "filled"}):
            users = Users("Development Team")
            internet_gw = InternetGateway("Internet Gateway")
        
        # Load Balancing Layer
        with Cluster("Load Balancing & Traffic Management", graph_attr={"bgcolor": "lightyellow", "style": "filled"}):
            alb = ALB("Application Load Balancer\ndev-jenkins-alb")
            target_group_blue = ALB("Target Group Blue")
            target_group_green = ALB("Target Group Green")
        
        # Blue Environment (Active)
        with Cluster("Blue Environment - ACTIVE", graph_attr={"bgcolor": "lightblue", "style": "filled"}):
            blue_asg = AutoScaling("Blue Auto Scaling Group\nDesired: 1, Min: 0, Max: 2")
            blue_launch_template = AMI("Launch Template Blue\nami-042ee7b7335ccb795")
            blue_instance = EC2Instance("Jenkins Master Blue\nt3.small - ACTIVE")
            blue_ebs = EBS("EBS Volume Blue\n20GB GP3")
        
        # Green Environment (Standby)
        with Cluster("Green Environment - STANDBY", graph_attr={"bgcolor": "lightgreen", "style": "filled"}):
            green_asg = AutoScaling("Green Auto Scaling Group\nDesired: 0, Min: 0, Max: 2")
            green_launch_template = AMI("Launch Template Green\nami-042ee7b7335ccb795")
            green_instance = EC2Instance("Jenkins Master Green\nt3.small - STANDBY")
            green_ebs = EBS("EBS Volume Green\n20GB GP3")
        
        # VPC Networking
        with Cluster("VPC Networking Infrastructure", graph_attr={"bgcolor": "lightcyan", "style": "filled"}):
            vpc = VPC("VPC\n10.0.0.0/16")
            private_subnet_1a = PrivateSubnet("Private Subnet 1a\n10.0.1.0/24")
            private_subnet_1b = PrivateSubnet("Private Subnet 1b\n10.0.2.0/24")
            public_subnet_1a = PublicSubnet("Public Subnet 1a\n10.0.101.0/24")
            public_subnet_1b = PublicSubnet("Public Subnet 1b\n10.0.102.0/24")
            nat_gateway = NATGateway("NAT Gateway\nCost Optimized")
            route_tables = RouteTable("Route Tables")
        
        # Shared Storage
        with Cluster("Shared Storage Layer", graph_attr={"bgcolor": "wheat", "style": "filled"}):
            efs = EFS("Elastic File System\nJenkins Data & Workspaces")
            efs_access_point = EFS("EFS Access Point\n/var/lib/jenkins")
        
        # Lambda Orchestration
        with Cluster("Lambda Orchestration & Automation", graph_attr={"bgcolor": "lightyellow", "style": "filled"}):
            deployment_orchestrator = Lambda("Deployment Orchestrator\nBlue-Green Controller")
            vertical_scaler = Lambda("Vertical Scaler\nAuto-scaling Logic")
            health_checker = Lambda("Health Checker\nEndpoint Validation")
            traffic_controller = Lambda("Traffic Controller\nALB Target Groups")
            eventbridge_rule = Eventbridge("EventBridge Rules\nScheduled & Manual")
        
        # Security & IAM
        with Cluster("Security & Identity Management", graph_attr={"bgcolor": "mistyrose", "style": "filled"}):
            iam_roles = IAM("IAM Roles & Policies\nEC2 + Lambda Roles")
            ssm_parameters = SystemsManager("SSM Parameter Store\nSecrets & Config")
            kms_encryption = KMS("KMS Encryption Keys\nEFS & EBS Encryption")
        
        # Monitoring & Observability
        with Cluster("Cost-Optimized Observability", graph_attr={"bgcolor": "lightcoral", "style": "filled"}):
            cloudwatch_dashboard = Cloudwatch("CloudWatch Dashboard\nEnterprise Metrics")
            cloudwatch_logs = CloudwatchLogs("Centralized Logs\nApplication & System")
            cloudwatch_alarms = CloudwatchAlarm("Smart Alarms\nDeployment & Health")
            custom_metrics = Cloudwatch("Custom Metrics\nBusiness KPIs")
            sns_notifications = SNS("SNS Notifications\nSlack & Email Alerts")
        
        # Security & Compliance
        with Cluster("Security Scanning & Compliance", graph_attr={"bgcolor": "lavender", "style": "filled"}):
            inspector = SystemsManager("AWS Inspector V2\nVulnerability Scanning")
            config_service = Config("AWS Config\nCompliance Monitoring")
            cloudtrail_audit = Cloudtrail("CloudTrail\nAPI Audit Logging")
        
        # Backup & Disaster Recovery
        with Cluster("Backup & Disaster Recovery", graph_attr={"bgcolor": "lightsteelblue", "style": "filled"}):
            aws_backup = SystemsManager("AWS Backup\nEFS Daily Backups")
            s3_backup_bucket = S3("S3 Backup Bucket\nConfiguration Backups")
            s3_alb_logs = S3("S3 ALB Access Logs\nTraffic Analysis")
            dr_region = EC2("DR Region (us-west-2)\nAMI Replication")
        
        # Golden AMI Pipeline
        with Cluster("Golden AMI Pipeline", graph_attr={"bgcolor": "lightgoldenrodyellow", "style": "filled"}):
            packer_builder = Codebuild("Packer AMI Builder\nQuarterly Automation")
            ami_repository = AMI("Golden AMI Repository\nVersioned AMIs")
            security_scanning = SystemsManager("Security Scanning\nTrivy + Inspector")
        
        # Cost Optimization
        with Cluster("Cost Optimization", graph_attr={"bgcolor": "lightseagreen", "style": "filled"}):
            cost_optimizer = SystemsManager("Cost Optimizer\nResource Right-sizing")
            lifecycle_policies = S3("S3 Lifecycle Policies\nIA → Glacier → Deep Archive")
        
        # === TRAFFIC FLOW (Dynamic Arrows) ===
        
        # User Traffic Flow
        users >> Edge(color="blue", style="bold", label="HTTPS") >> internet_gw
        internet_gw >> Edge(color="blue", style="bold") >> alb
        
        # Active Traffic (Solid Blue)
        alb >> Edge(color="blue", style="bold", label="Active Traffic") >> target_group_blue
        target_group_blue >> Edge(color="blue", style="bold") >> blue_instance
        
        # Standby Traffic (Dashed Gray)
        alb >> Edge(color="gray", style="dashed", label="Standby") >> target_group_green
        target_group_green >> Edge(color="gray", style="dashed") >> green_instance
        
        # === STORAGE CONNECTIONS ===
        
        # Shared EFS Storage
        blue_instance >> Edge(color="green", style="bold", label="NFS") >> efs_access_point
        green_instance >> Edge(color="green", style="dashed") >> efs_access_point
        efs_access_point >> Edge(color="green", style="bold") >> efs
        
        # Individual EBS Volumes
        blue_instance >> Edge(color="orange", style="bold") >> blue_ebs
        green_instance >> Edge(color="orange", style="dashed") >> green_ebs
        
        # === LAMBDA ORCHESTRATION FLOW ===
        
        # EventBridge Triggers
        eventbridge_rule >> Edge(color="purple", style="bold", label="5min Schedule") >> deployment_orchestrator
        
        # Lambda Control Flow
        deployment_orchestrator >> Edge(color="purple", style="bold") >> [vertical_scaler, health_checker, traffic_controller]
        
        # ASG Control
        deployment_orchestrator >> Edge(color="red", style="bold", label="Scale Up/Down") >> blue_asg
        deployment_orchestrator >> Edge(color="red", style="dashed", label="Scale Up/Down") >> green_asg
        
        # Traffic Switching
        traffic_controller >> Edge(color="purple", style="bold", label="Switch Traffic") >> alb
        
        # Health Validation
        health_checker >> Edge(color="green", style="dotted", label="Health Check") >> [blue_instance, green_instance]
        
        # === LAUNCH TEMPLATE CONNECTIONS ===
        blue_asg >> Edge(color="blue", style="bold") >> blue_launch_template
        green_asg >> Edge(color="green", style="dashed") >> green_launch_template
        
        # === SECURITY FLOW ===
        
        # IAM & Security
        [blue_instance, green_instance] >> Edge(color="red", style="dotted", label="IAM") >> iam_roles
        [blue_instance, green_instance] >> Edge(color="red", style="dotted", label="Secrets") >> ssm_parameters
        efs >> Edge(color="red", style="dotted", label="Encryption") >> kms_encryption
        
        # === MONITORING FLOW ===
        
        # Logs Collection
        [blue_instance, green_instance] >> Edge(color="orange", style="dotted", label="Logs") >> cloudwatch_logs
        deployment_orchestrator >> Edge(color="orange", style="dotted") >> cloudwatch_logs
        
        # Metrics Collection
        [blue_asg, green_asg, alb] >> Edge(color="orange", style="dotted", label="Metrics") >> cloudwatch_dashboard
        cloudwatch_dashboard >> Edge(color="orange", style="bold") >> custom_metrics
        
        # Alerting
        cloudwatch_dashboard >> Edge(color="red", style="bold", label="Triggers") >> cloudwatch_alarms
        cloudwatch_alarms >> Edge(color="red", style="bold", label="Alerts") >> sns_notifications
        
        # === SECURITY SCANNING ===
        [blue_instance, green_instance] >> Edge(color="purple", style="dotted", label="Scan") >> inspector
        [blue_instance, green_instance] >> Edge(color="purple", style="dotted", label="Audit") >> cloudtrail_audit
        
        # === BACKUP & DR FLOW ===
        
        # Backup Operations
        efs >> Edge(color="brown", style="bold", label="Daily Backup") >> aws_backup
        [blue_instance, green_instance] >> Edge(color="brown", style="dotted", label="Config Backup") >> s3_backup_bucket
        alb >> Edge(color="brown", style="dotted", label="Access Logs") >> s3_alb_logs
        
        # DR Replication
        ami_repository >> Edge(color="brown", style="bold", label="Cross-Region Sync") >> dr_region
        
        # === GOLDEN AMI PIPELINE ===
        
        # AMI Creation Flow
        packer_builder >> Edge(color="gold", style="bold", label="Build") >> security_scanning
        security_scanning >> Edge(color="gold", style="bold", label="Scan Pass") >> ami_repository
        ami_repository >> Edge(color="gold", style="bold", label="Deploy") >> [blue_launch_template, green_launch_template]
        
        # === COST OPTIMIZATION ===
        
        # Cost Management
        [blue_asg, green_asg] >> Edge(color="green", style="dotted", label="Optimize") >> cost_optimizer
        [s3_backup_bucket, s3_alb_logs] >> Edge(color="green", style="dotted", label="Lifecycle") >> lifecycle_policies
        
        # === NETWORK FLOW ===
        
        # Instance Placement
        blue_instance >> Edge(color="cyan", style="dotted") >> private_subnet_1a
        green_instance >> Edge(color="cyan", style="dotted") >> private_subnet_1b
        
        # ALB Placement
        alb >> Edge(color="cyan", style="dotted") >> [public_subnet_1a, public_subnet_1b]
        
        # Internet Access
        [private_subnet_1a, private_subnet_1b] >> Edge(color="cyan", style="dotted") >> nat_gateway
        nat_gateway >> Edge(color="cyan", style="bold") >> internet_gw

if __name__ == "__main__":
    print("🏗️  Generating Jenkins Enterprise Platform Architecture...")
    generate_enterprise_architecture()
    print("✅ Complete! Check: jenkins_enterprise_complete_architecture.png")
    print("📊 Diagram includes:")
    print("   • Blue-Green Deployment with Lambda Orchestration")
    print("   • 23+ AWS Services with Official Icons")
    print("   • Dynamic Arrows (Active/Standby/Control flows)")
    print("   • Cost-Optimized Observability ($105/month savings)")
    print("   • Security Scanning & Compliance")
    print("   • Backup & Disaster Recovery")
    print("   • Golden AMI Pipeline")
    print("   • Complete VPC Networking")
