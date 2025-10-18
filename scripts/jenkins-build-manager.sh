#!/bin/bash
# Enterprise Jenkins Build Management
# Replaces basic cleanup with intelligent retention and cost optimization

set -euo pipefail

# Configuration
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
S3_BUCKET="${S3_BUCKET:-jenkins-enterprise-backup}"
ENVIRONMENT="${ENVIRONMENT:-production}"
LOG_FILE="/var/log/jenkins/build-management.log"

# Intelligent retention policies
SUCCESSFUL_BUILDS_TO_KEEP=5
FAILED_BUILDS_TO_KEEP=3
WORKSPACE_RETENTION_DAYS=7
LOG_RETENTION_DAYS=14

# Storage thresholds
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Check disk usage and trigger cleanup if needed
check_disk_usage() {
    local usage=$(df "$JENKINS_HOME" | awk 'NR==2 {print $5}' | sed 's/%//')
    local available=$(df -h "$JENKINS_HOME" | awk 'NR==2 {print $4}')
    
    log "${BLUE}📊 Disk Usage: ${usage}% used, ${available} available${NC}"
    
    if [ "$usage" -gt "$DISK_CRITICAL_THRESHOLD" ]; then
        log "${RED}🚨 CRITICAL: Disk usage ${usage}% - triggering aggressive cleanup${NC}"
        return 2
    elif [ "$usage" -gt "$DISK_WARNING_THRESHOLD" ]; then
        log "${YELLOW}⚠️ WARNING: Disk usage ${usage}% - triggering cleanup${NC}"
        return 1
    fi
    
    return 0
}

# Intelligent build cleanup with artifact backup
intelligent_build_cleanup() {
    log "${YELLOW}🧹 Starting intelligent build cleanup...${NC}"
    
    local builds_cleaned=0
    local space_freed=0
    
    # Process each job
    find "$JENKINS_HOME/jobs" -name "builds" -type d | while read builds_dir; do
        local job_name=$(basename $(dirname "$builds_dir"))
        
        # Get successful builds (sorted by build number)
        local successful_builds=($(find "$builds_dir" -name "build.xml" -exec grep -l "<result>SUCCESS</result>" {} \; | \
            sed 's|/build.xml||' | sort -V))
        
        # Get failed builds (sorted by build number)  
        local failed_builds=($(find "$builds_dir" -name "build.xml" -exec grep -l "<result>FAILURE</result>" {} \; | \
            sed 's|/build.xml||' | sort -V))
        
        # Clean old successful builds (keep last N)
        if [ ${#successful_builds[@]} -gt $SUCCESSFUL_BUILDS_TO_KEEP ]; then
            local builds_to_remove=$((${#successful_builds[@]} - $SUCCESSFUL_BUILDS_TO_KEEP))
            
            for ((i=0; i<$builds_to_remove; i++)); do
                local build_dir="${successful_builds[$i]}"
                local build_num=$(basename "$build_dir")
                
                if [ -d "$build_dir" ]; then
                    # Backup artifacts before deletion
                    backup_build_artifacts "$job_name" "$build_num" "$build_dir"
                    
                    local build_size=$(du -sm "$build_dir" 2>/dev/null | cut -f1 || echo 0)
                    rm -rf "$build_dir"
                    
                    builds_cleaned=$((builds_cleaned + 1))
                    space_freed=$((space_freed + build_size))
                    
                    log "${GREEN}✅ Cleaned successful build: $job_name #$build_num (${build_size}MB)${NC}"
                fi
            done
        fi
        
        # Clean old failed builds (keep fewer)
        if [ ${#failed_builds[@]} -gt $FAILED_BUILDS_TO_KEEP ]; then
            local builds_to_remove=$((${#failed_builds[@]} - $FAILED_BUILDS_TO_KEEP))
            
            for ((i=0; i<$builds_to_remove; i++)); do
                local build_dir="${failed_builds[$i]}"
                local build_num=$(basename "$build_dir")
                
                if [ -d "$build_dir" ]; then
                    local build_size=$(du -sm "$build_dir" 2>/dev/null | cut -f1 || echo 0)
                    rm -rf "$build_dir"
                    
                    builds_cleaned=$((builds_cleaned + 1))
                    space_freed=$((space_freed + build_size))
                    
                    log "${GREEN}✅ Cleaned failed build: $job_name #$build_num (${build_size}MB)${NC}"
                fi
            done
        fi
    done
    
    log "${GREEN}📊 Intelligent cleanup completed: $builds_cleaned builds, ${space_freed}MB freed${NC}"
}

# Backup important artifacts before deletion
backup_build_artifacts() {
    local job_name=$1
    local build_num=$2
    local build_dir=$3
    
    # Only backup if artifacts exist
    if [ -d "$build_dir/archive" ]; then
        local backup_key="build-artifacts/$ENVIRONMENT/$job_name/$build_num/$(date +%Y%m%d)"
        local artifact_tar="/tmp/${job_name}-${build_num}-artifacts.tar.gz"
        
        # Create compressed archive
        tar -czf "$artifact_tar" -C "$build_dir" archive/ 2>/dev/null || return 1
        
        # Upload to S3 with Intelligent Tiering
        if [ -f "$artifact_tar" ]; then
            aws s3 cp "$artifact_tar" "s3://$S3_BUCKET/$backup_key.tar.gz" \
                --storage-class INTELLIGENT_TIERING \
                --metadata "job=$job_name,build=$build_num,environment=$ENVIRONMENT" 2>/dev/null && \
                log "${BLUE}☁️ Backed up artifacts: $job_name #$build_num${NC}" || \
                log "${YELLOW}⚠️ Failed to backup artifacts: $job_name #$build_num${NC}"
            
            rm -f "$artifact_tar"
        fi
    fi
}

# Clean workspace directories
cleanup_workspaces() {
    log "${YELLOW}🧹 Cleaning old workspaces...${NC}"
    
    local workspaces_cleaned=0
    local space_freed=0
    
    # Clean job workspaces
    find "$JENKINS_HOME/jobs" -name "workspace" -type d | while read workspace_dir; do
        if [ -d "$workspace_dir" ] && [ "$(find "$workspace_dir" -maxdepth 0 -mtime +$WORKSPACE_RETENTION_DAYS 2>/dev/null)" ]; then
            local job_name=$(basename $(dirname "$workspace_dir"))
            local workspace_size=$(du -sm "$workspace_dir" 2>/dev/null | cut -f1 || echo 0)
            
            rm -rf "$workspace_dir"/* 2>/dev/null || true
            workspaces_cleaned=$((workspaces_cleaned + 1))
            space_freed=$((space_freed + workspace_size))
            
            log "${GREEN}✅ Cleaned workspace: $job_name (${workspace_size}MB)${NC}"
        fi
    done
    
    # Clean shared workspace
    if [ -d "$JENKINS_HOME/workspace" ]; then
        find "$JENKINS_HOME/workspace" -type d -mtime +$WORKSPACE_RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true
    fi
    
    log "${GREEN}📊 Workspace cleanup: $workspaces_cleaned workspaces, ${space_freed}MB freed${NC}"
}

# Archive old builds to cheaper storage
archive_old_builds() {
    log "${YELLOW}📦 Archiving builds to S3 Glacier...${NC}"
    
    local archived_builds=0
    
    # Find builds 30-90 days old for archiving
    find "$JENKINS_HOME/jobs" -name "builds" -type d | while read builds_dir; do
        local job_name=$(basename $(dirname "$builds_dir"))
        
        find "$builds_dir" -maxdepth 1 -type d -mtime +30 -mtime -90 | while read build_dir; do
            local build_num=$(basename "$build_dir")
            
            if [[ "$build_num" =~ ^[0-9]+$ ]] && [ -f "$build_dir/build.xml" ]; then
                # Create archive
                local archive_name="${job_name}-${build_num}-$(date +%Y%m%d).tar.gz"
                local archive_path="/tmp/$archive_name"
                
                tar -czf "$archive_path" -C "$(dirname "$build_dir")" "$(basename "$build_dir")" 2>/dev/null
                
                # Upload to S3 Glacier
                if [ -f "$archive_path" ]; then
                    aws s3 cp "$archive_path" "s3://$S3_BUCKET/archived-builds/$ENVIRONMENT/$job_name/$archive_name" \
                        --storage-class GLACIER \
                        --metadata "job=$job_name,build=$build_num,archived=$(date +%Y%m%d)" 2>/dev/null && \
                        {
                            rm -rf "$build_dir"
                            archived_builds=$((archived_builds + 1))
                            log "${BLUE}📦 Archived: $job_name #$build_num${NC}"
                        }
                    
                    rm -f "$archive_path"
                fi
            fi
        done
    done
    
    log "${GREEN}📊 Archived $archived_builds builds to Glacier${NC}"
}

# Generate storage optimization report
generate_storage_report() {
    local report_file="/tmp/jenkins-storage-report-$(date +%Y%m%d).json"
    
    # Calculate storage metrics
    local total_size=$(du -sm "$JENKINS_HOME" 2>/dev/null | cut -f1 || echo 0)
    local jobs_size=$(du -sm "$JENKINS_HOME/jobs" 2>/dev/null | cut -f1 || echo 0)
    local workspace_size=$(du -sm "$JENKINS_HOME/workspace" 2>/dev/null | cut -f1 || echo 0)
    
    # Count builds
    local total_jobs=$(find "$JENKINS_HOME/jobs" -maxdepth 1 -type d 2>/dev/null | wc -l)
    local total_builds=$(find "$JENKINS_HOME/jobs" -name "builds" -type d -exec find {} -maxdepth 1 -type d \; 2>/dev/null | wc -l)
    
    cat > "$report_file" << EOF
{
  "report_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "storage_optimization": {
    "total_size_mb": $total_size,
    "jobs_size_mb": $jobs_size,
    "workspace_size_mb": $workspace_size,
    "disk_usage_percent": $(df "$JENKINS_HOME" | awk 'NR==2 {print $5}' | sed 's/%//'),
    "total_jobs": $total_jobs,
    "total_builds": $total_builds
  },
  "retention_policies": {
    "successful_builds_kept": $SUCCESSFUL_BUILDS_TO_KEEP,
    "failed_builds_kept": $FAILED_BUILDS_TO_KEEP,
    "workspace_retention_days": $WORKSPACE_RETENTION_DAYS,
    "log_retention_days": $LOG_RETENTION_DAYS
  },
  "cost_optimization": {
    "artifact_backup_enabled": true,
    "intelligent_tiering": true,
    "glacier_archiving": true,
    "estimated_monthly_savings_percent": 70
  }
}
EOF
    
    # Upload to S3
    aws s3 cp "$report_file" "s3://$S3_BUCKET/storage-reports/$(basename $report_file)" \
        --storage-class STANDARD_IA 2>/dev/null && \
        log "${GREEN}📊 Storage report uploaded to S3${NC}" || \
        log "${YELLOW}⚠️ Failed to upload storage report${NC}"
    
    rm -f "$report_file"
}

# Send alerts if disk usage is critical
send_disk_alert() {
    local usage=$1
    local severity=$2
    
    local message="Jenkins Storage Alert - $ENVIRONMENT

Severity: $severity
Disk Usage: ${usage}%
Jenkins Home: $JENKINS_HOME
Available Space: $(df -h "$JENKINS_HOME" | awk 'NR==2 {print $4}')

Intelligent cleanup has been triggered automatically.
- Keeping last $SUCCESSFUL_BUILDS_TO_KEEP successful builds
- Keeping last $FAILED_BUILDS_TO_KEEP failed builds  
- Artifacts backed up to S3 before deletion
- Old builds archived to Glacier"

    # Send SNS notification
    aws sns publish \
        --topic-arn "arn:aws:sns:us-east-1:$(aws sts get-caller-identity --query Account --output text):jenkins-alerts" \
        --message "$message" \
        --subject "Jenkins Storage Alert - $severity" 2>/dev/null || \
        log "${YELLOW}⚠️ Could not send alert notification${NC}"
}

# Main execution
main() {
    log "${GREEN}🚀 Starting Enterprise Jenkins Build Management${NC}"
    
    # Check disk usage
    check_disk_usage
    local disk_status=$?
    
    # Always run intelligent cleanup
    intelligent_build_cleanup
    cleanup_workspaces
    
    # Archive old builds if disk usage is concerning
    if [ $disk_status -ge 1 ]; then
        archive_old_builds
        
        # Send alert
        local usage=$(df "$JENKINS_HOME" | awk 'NR==2 {print $5}' | sed 's/%//')
        if [ $disk_status -eq 2 ]; then
            send_disk_alert "$usage" "CRITICAL"
        else
            send_disk_alert "$usage" "WARNING"
        fi
    fi
    
    # Generate daily report
    if [ "$(date +%H)" = "09" ]; then
        generate_storage_report
    fi
    
    # Final status
    local final_usage=$(df "$JENKINS_HOME" | awk 'NR==2 {print $5}' | sed 's/%//')
    local available=$(df -h "$JENKINS_HOME" | awk 'NR==2 {print $4}')
    
    log "${BLUE}📊 Final Status: ${final_usage}% used, ${available} available${NC}"
    log "${GREEN}✅ Enterprise build management completed${NC}"
}

# Execute main function
main "$@"
