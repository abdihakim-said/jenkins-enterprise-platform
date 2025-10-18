#!/bin/bash
# Jenkins Backup Script
# Epic 3: Story 4.1 - Setup Jenkins Master backup (Disaster Recovery)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/jenkins/backup.log"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/jenkins-backup}"
S3_BUCKET="${S3_BUCKET:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
ENCRYPTION_ENABLED="${ENCRYPTION_ENABLED:-true}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

# Backup types
BACKUP_TYPE="${1:-full}"  # full, incremental, config
BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="jenkins-${BACKUP_TYPE}-${ENVIRONMENT}-${BACKUP_TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Error handling
error_exit() {
    log_error "$1"
    send_notification "FAILED" "$1"
    cleanup_temp_files
    exit 1
}

# Cleanup function
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    if [[ -d "${BACKUP_DIR}" ]]; then
        rm -rf "${BACKUP_DIR}"
    fi
}

# Trap for cleanup on exit
trap cleanup_temp_files EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Jenkins is running
    if ! systemctl is-active --quiet jenkins; then
        log_warn "Jenkins service is not running"
    fi
    
    # Check required commands
    local required_commands=("tar" "gzip" "aws" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error_exit "Required command '$cmd' not found"
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid"
    fi
    
    # Check S3 bucket
    if [[ -z "${S3_BUCKET}" ]]; then
        error_exit "S3_BUCKET environment variable not set"
    fi
    
    if ! aws s3 ls "s3://${S3_BUCKET}" &> /dev/null; then
        error_exit "Cannot access S3 bucket: ${S3_BUCKET}"
    fi
    
    # Check disk space
    local available_space=$(df "${BACKUP_DIR%/*}" | awk 'NR==2 {print $4}')
    local jenkins_size=$(du -s "${JENKINS_HOME}" | awk '{print $1}')
    local required_space=$((jenkins_size * 2))  # 2x for compression buffer
    
    if [[ $available_space -lt $required_space ]]; then
        error_exit "Insufficient disk space. Required: ${required_space}KB, Available: ${available_space}KB"
    fi
    
    log_success "Prerequisites check passed"
}

# Create backup directory
create_backup_dir() {
    log_info "Creating backup directory: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
    chmod 750 "${BACKUP_DIR}"
}

# Stop Jenkins gracefully
stop_jenkins() {
    log_info "Stopping Jenkins gracefully..."
    
    # Put Jenkins in quiet mode first
    if systemctl is-active --quiet jenkins; then
        log_info "Putting Jenkins in quiet mode..."
        curl -X POST "http://localhost:8080/quietDown" \
            --user "admin:$(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'admin')" \
            --silent || log_warn "Could not put Jenkins in quiet mode"
        
        # Wait for running jobs to complete (max 10 minutes)
        local wait_time=0
        local max_wait=600
        while [[ $wait_time -lt $max_wait ]]; do
            local running_jobs=$(curl -s "http://localhost:8080/api/json" \
                --user "admin:$(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'admin')" \
                | jq -r '.numExecutors // 0' 2>/dev/null || echo "0")
            
            if [[ "$running_jobs" == "0" ]]; then
                break
            fi
            
            log_info "Waiting for $running_jobs running jobs to complete..."
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        # Stop Jenkins service
        log_info "Stopping Jenkins service..."
        systemctl stop jenkins
        
        # Wait for Jenkins to fully stop
        sleep 10
    else
        log_info "Jenkins is already stopped"
    fi
}

# Start Jenkins
start_jenkins() {
    log_info "Starting Jenkins service..."
    systemctl start jenkins
    
    # Wait for Jenkins to be ready
    local wait_time=0
    local max_wait=300
    while [[ $wait_time -lt $max_wait ]]; do
        if curl -s "http://localhost:8080/login" &> /dev/null; then
            log_success "Jenkins is ready"
            return 0
        fi
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    log_warn "Jenkins may not be fully ready yet"
}

# Perform full backup
backup_full() {
    log_info "Performing full backup..."
    
    local backup_file="${BACKUP_DIR}/${BACKUP_NAME}.tar"
    
    # Create tar archive excluding unnecessary files
    tar -cf "${backup_file}" \
        -C "${JENKINS_HOME}" \
        --exclude='workspace/*' \
        --exclude='builds/*/archive' \
        --exclude='builds/*/cobertura' \
        --exclude='builds/*/htmlreports' \
        --exclude='builds/*/jacoco' \
        --exclude='builds/*/junitResult.xml' \
        --exclude='builds/*/testReport' \
        --exclude='*.log' \
        --exclude='*.tmp' \
        --exclude='cache/*' \
        --exclude='war/*' \
        --exclude='tools/*' \
        --exclude='.m2/repository/*' \
        . || error_exit "Failed to create backup archive"
    
    log_success "Full backup archive created: ${backup_file}"
    echo "${backup_file}"
}

# Perform incremental backup
backup_incremental() {
    log_info "Performing incremental backup..."
    
    local backup_file="${BACKUP_DIR}/${BACKUP_NAME}.tar"
    local last_backup_date=$(date -d "1 day ago" +"%Y-%m-%d")
    
    # Find files modified in the last 24 hours
    find "${JENKINS_HOME}" -type f -newermt "${last_backup_date}" \
        ! -path "*/workspace/*" \
        ! -path "*/builds/*/archive/*" \
        ! -name "*.log" \
        ! -name "*.tmp" \
        -print0 | tar -cf "${backup_file}" --null -T - || error_exit "Failed to create incremental backup"
    
    log_success "Incremental backup archive created: ${backup_file}"
    echo "${backup_file}"
}

# Perform configuration backup
backup_config() {
    log_info "Performing configuration backup..."
    
    local backup_file="${BACKUP_DIR}/${BACKUP_NAME}.tar"
    
    # Backup only configuration files
    tar -cf "${backup_file}" \
        -C "${JENKINS_HOME}" \
        config.xml \
        *.xml \
        users/ \
        secrets/ \
        plugins/ \
        jobs/*/config.xml \
        nodes/ \
        scriptApproval.xml \
        hudson.model.UpdateCenter.xml \
        jenkins.model.JenkinsLocationConfiguration.xml \
        2>/dev/null || error_exit "Failed to create configuration backup"
    
    log_success "Configuration backup archive created: ${backup_file}"
    echo "${backup_file}"
}

# Compress backup
compress_backup() {
    local backup_file="$1"
    log_info "Compressing backup with level ${COMPRESSION_LEVEL}..."
    
    gzip -"${COMPRESSION_LEVEL}" "${backup_file}" || error_exit "Failed to compress backup"
    
    local compressed_file="${backup_file}.gz"
    log_success "Backup compressed: ${compressed_file}"
    echo "${compressed_file}"
}

# Encrypt backup
encrypt_backup() {
    local backup_file="$1"
    
    if [[ "${ENCRYPTION_ENABLED}" != "true" ]]; then
        echo "${backup_file}"
        return 0
    fi
    
    log_info "Encrypting backup..."
    
    # Use AWS KMS for encryption
    local encrypted_file="${backup_file}.enc"
    
    aws kms encrypt \
        --key-id "alias/jenkins-${ENVIRONMENT}-backup" \
        --plaintext "fileb://${backup_file}" \
        --output text \
        --query CiphertextBlob \
        --region "${AWS_REGION}" | base64 -d > "${encrypted_file}" || error_exit "Failed to encrypt backup"
    
    # Remove unencrypted file
    rm -f "${backup_file}"
    
    log_success "Backup encrypted: ${encrypted_file}"
    echo "${encrypted_file}"
}

# Upload to S3
upload_to_s3() {
    local backup_file="$1"
    local s3_key="backups/${BACKUP_TYPE}/${BACKUP_NAME}.tar.gz"
    
    if [[ "${backup_file}" == *.enc ]]; then
        s3_key="${s3_key}.enc"
    fi
    
    log_info "Uploading backup to S3: s3://${S3_BUCKET}/${s3_key}"
    
    # Upload with metadata
    aws s3 cp "${backup_file}" "s3://${S3_BUCKET}/${s3_key}" \
        --metadata "backup-type=${BACKUP_TYPE},environment=${ENVIRONMENT},jenkins-version=$(jenkins --version 2>/dev/null || echo 'unknown'),timestamp=${BACKUP_TIMESTAMP}" \
        --storage-class STANDARD_IA \
        --region "${AWS_REGION}" || error_exit "Failed to upload backup to S3"
    
    # Verify upload
    if aws s3 ls "s3://${S3_BUCKET}/${s3_key}" &> /dev/null; then
        log_success "Backup uploaded successfully to S3"
    else
        error_exit "Backup upload verification failed"
    fi
    
    echo "s3://${S3_BUCKET}/${s3_key}"
}

# Clean old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."
    
    local cutoff_date=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d)
    
    # List and delete old backups
    aws s3api list-objects-v2 \
        --bucket "${S3_BUCKET}" \
        --prefix "backups/${BACKUP_TYPE}/" \
        --query "Contents[?LastModified<='${cutoff_date}'].Key" \
        --output text \
        --region "${AWS_REGION}" | while read -r key; do
        if [[ -n "$key" && "$key" != "None" ]]; then
            log_info "Deleting old backup: ${key}"
            aws s3 rm "s3://${S3_BUCKET}/${key}" --region "${AWS_REGION}"
        fi
    done
    
    log_success "Old backup cleanup completed"
}

# Generate backup report
generate_report() {
    local backup_s3_path="$1"
    local backup_size="$2"
    local duration="$3"
    
    local report_file="${BACKUP_DIR}/backup-report-${BACKUP_TIMESTAMP}.json"
    
    cat > "${report_file}" << EOF
{
    "backup_info": {
        "type": "${BACKUP_TYPE}",
        "environment": "${ENVIRONMENT}",
        "timestamp": "${BACKUP_TIMESTAMP}",
        "jenkins_home": "${JENKINS_HOME}",
        "s3_location": "${backup_s3_path}",
        "size_bytes": ${backup_size},
        "size_human": "$(numfmt --to=iec ${backup_size})",
        "duration_seconds": ${duration},
        "compression_level": ${COMPRESSION_LEVEL},
        "encryption_enabled": ${ENCRYPTION_ENABLED}
    },
    "system_info": {
        "hostname": "$(hostname)",
        "os": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)",
        "jenkins_version": "$(jenkins --version 2>/dev/null || echo 'unknown')",
        "disk_usage": "$(df -h ${JENKINS_HOME} | awk 'NR==2 {print $5}')",
        "aws_region": "${AWS_REGION}"
    },
    "status": "SUCCESS"
}
EOF
    
    # Upload report to S3
    aws s3 cp "${report_file}" "s3://${S3_BUCKET}/reports/backup-report-${BACKUP_TIMESTAMP}.json" \
        --region "${AWS_REGION}" || log_warn "Failed to upload backup report"
    
    log_success "Backup report generated: ${report_file}"
}

# Send notifications
send_notification() {
    local status="$1"
    local message="$2"
    
    local subject="Jenkins Backup ${status} - ${ENVIRONMENT}"
    local body="Jenkins backup ${BACKUP_TYPE} ${status,,} on $(hostname) at $(date)\n\nDetails:\n${message}"
    
    # Email notification
    if [[ -n "${NOTIFICATION_EMAIL}" ]]; then
        echo -e "${body}" | mail -s "${subject}" "${NOTIFICATION_EMAIL}" || log_warn "Failed to send email notification"
    fi
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK}" ]]; then
        local color="good"
        [[ "${status}" == "FAILED" ]] && color="danger"
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"${subject}\",\"attachments\":[{\"color\":\"${color}\",\"text\":\"${message}\"}]}" \
            "${SLACK_WEBHOOK}" || log_warn "Failed to send Slack notification"
    fi
}

# Main backup function
main() {
    local start_time=$(date +%s)
    
    log_info "Starting Jenkins backup - Type: ${BACKUP_TYPE}, Environment: ${ENVIRONMENT}"
    
    # Check prerequisites
    check_prerequisites
    
    # Create backup directory
    create_backup_dir
    
    # Stop Jenkins for consistent backup
    local jenkins_was_running=false
    if systemctl is-active --quiet jenkins; then
        jenkins_was_running=true
        stop_jenkins
    fi
    
    # Perform backup based on type
    local backup_file
    case "${BACKUP_TYPE}" in
        "full")
            backup_file=$(backup_full)
            ;;
        "incremental")
            backup_file=$(backup_incremental)
            ;;
        "config")
            backup_file=$(backup_config)
            ;;
        *)
            error_exit "Invalid backup type: ${BACKUP_TYPE}. Use: full, incremental, or config"
            ;;
    esac
    
    # Start Jenkins if it was running
    if [[ "${jenkins_was_running}" == "true" ]]; then
        start_jenkins
    fi
    
    # Compress backup
    backup_file=$(compress_backup "${backup_file}")
    
    # Encrypt backup if enabled
    backup_file=$(encrypt_backup "${backup_file}")
    
    # Get backup size
    local backup_size=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}")
    
    # Upload to S3
    local s3_path=$(upload_to_s3 "${backup_file}")
    
    # Clean old backups
    cleanup_old_backups
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Generate report
    generate_report "${s3_path}" "${backup_size}" "${duration}"
    
    # Send success notification
    local success_message="Backup completed successfully!\nType: ${BACKUP_TYPE}\nSize: $(numfmt --to=iec ${backup_size})\nDuration: ${duration}s\nLocation: ${s3_path}"
    send_notification "SUCCESS" "${success_message}"
    
    log_success "Jenkins backup completed successfully in ${duration} seconds"
    log_success "Backup location: ${s3_path}"
    log_success "Backup size: $(numfmt --to=iec ${backup_size})"
}

# Script usage
usage() {
    cat << EOF
Usage: $0 [BACKUP_TYPE]

BACKUP_TYPE:
    full         - Complete Jenkins backup (default)
    incremental  - Backup files changed in last 24 hours
    config       - Backup only configuration files

Environment Variables:
    JENKINS_HOME         - Jenkins home directory (default: /var/lib/jenkins)
    S3_BUCKET           - S3 bucket for backups (required)
    AWS_REGION          - AWS region (default: us-east-1)
    ENVIRONMENT         - Environment name (default: staging)
    RETENTION_DAYS      - Backup retention in days (default: 30)
    COMPRESSION_LEVEL   - Gzip compression level 1-9 (default: 6)
    ENCRYPTION_ENABLED  - Enable backup encryption (default: true)
    NOTIFICATION_EMAIL  - Email for notifications
    SLACK_WEBHOOK       - Slack webhook URL for notifications

Examples:
    $0 full              # Full backup
    $0 incremental       # Incremental backup
    $0 config            # Configuration backup only
EOF
}

# Handle command line arguments
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"
