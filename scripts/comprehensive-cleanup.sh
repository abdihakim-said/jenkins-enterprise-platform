#!/bin/bash
# Comprehensive Jenkins Platform Cleanup Script
# Cleans AMIs, snapshots, volumes, and other leftover resources

set -e

# Configuration
PROJECT_NAME="jenkins-enterprise-platform"
ENVIRONMENT=${1:-"dev"}
MAX_AMIS=${2:-3}
DRY_RUN=${3:-false}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Dry run check
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = "true" ]; then
        warning "[DRY RUN] Would execute: $description"
        echo "Command: $cmd"
    else
        log "Executing: $description"
        eval "$cmd"
    fi
}

log "🧹 Starting comprehensive cleanup for ${PROJECT_NAME} (${ENVIRONMENT})"
log "Max AMIs to keep: $MAX_AMIS"
log "Dry run mode: $DRY_RUN"

# 1. Clean up old AMIs and snapshots
log "📀 Cleaning up AMIs and snapshots..."

# Get all Jenkins AMIs sorted by creation date (newest first)
AMIS=$(aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=jenkins-golden-ami-*" \
              "Name=tag:Environment,Values=${ENVIRONMENT}" \
              "Name=state,Values=available" \
    --query 'Images[*].[ImageId,CreationDate,Name,BlockDeviceMappings[0].Ebs.SnapshotId]' \
    --output text | sort -k2 -r)

if [ -z "$AMIS" ]; then
    warning "No AMIs found for cleanup"
else
    echo "Found AMIs:"
    echo "$AMIS" | while read ami_id creation_date name snapshot_id; do
        echo "  $ami_id | $creation_date | $name | $snapshot_id"
    done
    
    TOTAL_AMIS=$(echo "$AMIS" | wc -l)
    log "Total AMIs: $TOTAL_AMIS"
    
    if [ $TOTAL_AMIS -gt $MAX_AMIS ]; then
        log "Cleaning up old AMIs (keeping latest $MAX_AMIS)"
        
        # Get AMIs to delete (skip first MAX_AMIS)
        AMIS_TO_DELETE=$(echo "$AMIS" | tail -n +$((MAX_AMIS + 1)))
        
        echo "$AMIS_TO_DELETE" | while read ami_id creation_date name snapshot_id; do
            execute_command "aws ec2 deregister-image --image-id $ami_id" "Deregister AMI $ami_id"
            
            if [ "$snapshot_id" != "None" ] && [ "$snapshot_id" != "" ]; then
                execute_command "aws ec2 delete-snapshot --snapshot-id $snapshot_id" "Delete snapshot $snapshot_id"
            fi
        done
        
        success "AMI cleanup completed"
    else
        success "No AMI cleanup needed (${TOTAL_AMIS} <= ${MAX_AMIS})"
    fi
fi

# 2. Clean up orphaned snapshots
log "📸 Cleaning up orphaned snapshots..."

ORPHANED_SNAPSHOTS=$(aws ec2 describe-snapshots \
    --owner-ids self \
    --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
              "Name=tag:Environment,Values=${ENVIRONMENT}" \
    --query 'Snapshots[?State==`completed`].[SnapshotId,StartTime,Description]' \
    --output text)

if [ -z "$ORPHANED_SNAPSHOTS" ]; then
    success "No orphaned snapshots found"
else
    log "Found snapshots to review:"
    echo "$ORPHANED_SNAPSHOTS"
    
    # Check if snapshots are still referenced by AMIs
    echo "$ORPHANED_SNAPSHOTS" | while read snapshot_id start_time description; do
        # Check if snapshot is used by any AMI
        AMI_USING_SNAPSHOT=$(aws ec2 describe-images \
            --owners self \
            --filters "Name=block-device-mapping.snapshot-id,Values=${snapshot_id}" \
            --query 'Images[0].ImageId' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$AMI_USING_SNAPSHOT" = "None" ]; then
            execute_command "aws ec2 delete-snapshot --snapshot-id $snapshot_id" "Delete orphaned snapshot $snapshot_id"
        else
            log "Snapshot $snapshot_id is used by AMI $AMI_USING_SNAPSHOT - keeping"
        fi
    done
fi

# 3. Clean up unused EBS volumes
log "💾 Cleaning up unused EBS volumes..."

UNUSED_VOLUMES=$(aws ec2 describe-volumes \
    --filters "Name=status,Values=available" \
              "Name=tag:Project,Values=${PROJECT_NAME}" \
              "Name=tag:Environment,Values=${ENVIRONMENT}" \
    --query 'Volumes[*].[VolumeId,CreateTime,Size,VolumeType]' \
    --output text)

if [ -z "$UNUSED_VOLUMES" ]; then
    success "No unused volumes found"
else
    log "Found unused volumes:"
    echo "$UNUSED_VOLUMES"
    
    echo "$UNUSED_VOLUMES" | while read volume_id create_time size volume_type; do
        execute_command "aws ec2 delete-volume --volume-id $volume_id" "Delete unused volume $volume_id (${size}GB)"
    done
fi

# 4. Clean up old launch templates
log "🚀 Cleaning up old launch templates..."

OLD_LAUNCH_TEMPLATES=$(aws ec2 describe-launch-template-versions \
    --filters "Name=launch-template-name,Values=${PROJECT_NAME}-*" \
    --query 'LaunchTemplateVersions[?DefaultVersion==`false`].[LaunchTemplateName,Version,CreateTime]' \
    --output text | sort -k3 | head -n -5)  # Keep latest 5 versions

if [ -z "$OLD_LAUNCH_TEMPLATES" ]; then
    success "No old launch templates found"
else
    log "Found old launch template versions:"
    echo "$OLD_LAUNCH_TEMPLATES"
    
    echo "$OLD_LAUNCH_TEMPLATES" | while read template_name version create_time; do
        execute_command "aws ec2 delete-launch-template-version --launch-template-name $template_name --versions $version" "Delete launch template version $template_name:$version"
    done
fi

# 5. Clean up old CloudWatch logs
log "📊 Cleaning up old CloudWatch logs..."

OLD_LOG_STREAMS=$(aws logs describe-log-streams \
    --log-group-name "/jenkins/${ENVIRONMENT}/application" \
    --order-by LastEventTime \
    --descending \
    --query 'logStreams[30:].[logStreamName,lastEventTime]' \
    --output text 2>/dev/null || echo "")

if [ -z "$OLD_LOG_STREAMS" ]; then
    success "No old log streams found"
else
    log "Found old log streams to clean:"
    echo "$OLD_LOG_STREAMS" | head -10  # Show first 10
    
    echo "$OLD_LOG_STREAMS" | while read stream_name last_event_time; do
        execute_command "aws logs delete-log-stream --log-group-name '/jenkins/${ENVIRONMENT}/application' --log-stream-name '$stream_name'" "Delete log stream $stream_name"
    done
fi

# 6. Clean up S3 old objects (if backup bucket exists)
log "🪣 Cleaning up old S3 objects..."

BACKUP_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-backup"
if aws s3 ls "s3://${BACKUP_BUCKET}" >/dev/null 2>&1; then
    # Delete objects older than 90 days
    CUTOFF_DATE=$(date -d '90 days ago' '+%Y-%m-%d')
    
    execute_command "aws s3api list-objects-v2 --bucket $BACKUP_BUCKET --query 'Contents[?LastModified<\`${CUTOFF_DATE}\`].[Key]' --output text | xargs -I {} aws s3 rm s3://${BACKUP_BUCKET}/{}" "Delete S3 objects older than 90 days"
else
    log "Backup bucket $BACKUP_BUCKET not found - skipping S3 cleanup"
fi

# 7. Clean up unused security groups
log "🔒 Cleaning up unused security groups..."

UNUSED_SG=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
              "Name=tag:Environment,Values=${ENVIRONMENT}" \
    --query 'SecurityGroups[*].[GroupId,GroupName]' \
    --output text)

if [ -z "$UNUSED_SG" ]; then
    success "No security groups found for review"
else
    echo "$UNUSED_SG" | while read sg_id sg_name; do
        # Check if security group is in use
        SG_IN_USE=$(aws ec2 describe-instances \
            --filters "Name=instance.group-id,Values=${sg_id}" \
                      "Name=instance-state-name,Values=running,pending,stopping,stopped" \
            --query 'Reservations[*].Instances[*].InstanceId' \
            --output text)
        
        if [ -z "$SG_IN_USE" ]; then
            # Check if it's referenced by other security groups
            SG_REFERENCED=$(aws ec2 describe-security-groups \
                --filters "Name=ip-permission.group-id,Values=${sg_id}" \
                --query 'SecurityGroups[*].GroupId' \
                --output text)
            
            if [ -z "$SG_REFERENCED" ] && [[ "$sg_name" != "default" ]]; then
                execute_command "aws ec2 delete-security-group --group-id $sg_id" "Delete unused security group $sg_id ($sg_name)"
            else
                log "Security group $sg_id is referenced by other groups - keeping"
            fi
        else
            log "Security group $sg_id is in use - keeping"
        fi
    done
fi

# 8. Summary report
log "📋 Cleanup Summary Report"
echo "=================================="
echo "Environment: $ENVIRONMENT"
echo "Max AMIs kept: $MAX_AMIS"
echo "Dry run mode: $DRY_RUN"
echo "Cleanup completed at: $(date)"
echo "=================================="

if [ "$DRY_RUN" = "true" ]; then
    warning "This was a DRY RUN - no resources were actually deleted"
    warning "Run with 'false' as third parameter to execute cleanup"
else
    success "Comprehensive cleanup completed successfully!"
fi

log "💡 Usage: $0 [environment] [max_amis] [dry_run]"
log "Example: $0 dev 3 false"
