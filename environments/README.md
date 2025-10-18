# Environment Configurations

This directory contains environment-specific configurations for the Jenkins Enterprise Platform.

## Available Environments

### Development (`dev/`)
- **Purpose**: Development and testing
- **Instance Type**: t3.small (cost-optimized)
- **VPC CIDR**: 10.1.0.0/16
- **Features**: Single NAT Gateway, minimal monitoring, 7-day retention

### Staging (`staging/`)
- **Purpose**: Pre-production testing
- **Instance Type**: t3.medium (production-like)
- **VPC CIDR**: 10.2.0.0/16
- **Features**: Single NAT Gateway, full monitoring, 14-day retention

### Production (`production/`)
- **Purpose**: Live production workloads
- **Instance Type**: t3.large (high availability)
- **VPC CIDR**: 10.3.0.0/16
- **Features**: Multi-AZ NAT Gateways, full monitoring, 90-day retention

## Deployment

Deploy to specific environment:
```bash
./deploy-env.sh dev
./deploy-env.sh staging
./deploy-env.sh production
```

## Configuration Differences

| Feature | Dev | Staging | Production |
|---------|-----|---------|------------|
| Instance Type | t3.small | t3.medium | t3.large |
| Min Instances | 1 | 1 | 2 |
| Max Instances | 2 | 3 | 5 |
| NAT Gateways | 1 | 1 | 3 |
| Log Retention | 7 days | 14 days | 30 days |
| Backup Retention | 7 days | 14 days | 90 days |
| Monitoring | Basic | Full | Full |
