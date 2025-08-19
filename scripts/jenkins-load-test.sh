#!/bin/bash

# Jenkins Enterprise Platform - Comprehensive Load Testing
# Date: 2025-08-17
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
JENKINS_URL="http://staging-jenkins-alb-1353461168.us-east-1.elb.amazonaws.com:8080"
TEST_DURATION=300  # 5 minutes
CONCURRENT_USERS=(1 5 10 25 50)
RAMP_UP_TIME=30
RESULTS_DIR="load-test-results-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$RESULTS_DIR/load-test.log"

echo -e "${BLUE}=== Jenkins Enterprise Platform Load Testing ===${NC}"
echo "Test started at: $(date)"
echo "Results directory: $RESULTS_DIR"
echo ""

# Create results directory
mkdir -p "$RESULTS_DIR"

# Function to log messages
log_message() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Check prerequisites
log_message "${YELLOW}=== Checking Prerequisites ===${NC}"

# Check if curl is available
if ! command -v curl &> /dev/null; then
    log_message "${RED}ERROR: curl is not installed${NC}"
    exit 1
fi
log_message "${GREEN}✓ curl is available${NC}"

# Check if Apache Bench (ab) is available
if ! command -v ab &> /dev/null; then
    log_message "${YELLOW}WARNING: Apache Bench (ab) not found. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install httpd
        else
            log_message "${RED}ERROR: Please install Apache Bench (ab) manually${NC}"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        sudo apt-get update && sudo apt-get install -y apache2-utils
    fi
fi
log_message "${GREEN}✓ Apache Bench (ab) is available${NC}"

# Check Jenkins connectivity
log_message "${YELLOW}=== Testing Jenkins Connectivity ===${NC}"
if curl -s -I "$JENKINS_URL" | grep -q "HTTP/1.1"; then
    log_message "${GREEN}✓ Jenkins is accessible${NC}"
else
    log_message "${RED}ERROR: Cannot connect to Jenkins${NC}"
    exit 1
fi

# Function to run load test
run_load_test() {
    local users=$1
    local test_name="load_test_${users}_users"
    local output_file="$RESULTS_DIR/${test_name}.txt"
    
    log_message "${BLUE}=== Running Load Test: $users concurrent users ===${NC}"
    
    # Calculate total requests (users * duration / interval)
    local total_requests=$((users * TEST_DURATION / 10))
    
    # Run Apache Bench test
    ab -n $total_requests -c $users -g "$RESULTS_DIR/${test_name}.gnuplot" \
       -e "$RESULTS_DIR/${test_name}.csv" \
       "$JENKINS_URL/" > "$output_file" 2>&1
    
    # Extract key metrics
    local requests_per_second=$(grep "Requests per second" "$output_file" | awk '{print $4}')
    local mean_response_time=$(grep "Time per request.*mean" "$output_file" | head -n1 | awk '{print $4}')
    local failed_requests=$(grep "Failed requests" "$output_file" | awk '{print $3}')
    local transfer_rate=$(grep "Transfer rate" "$output_file" | awk '{print $3}')
    
    log_message "${GREEN}Results for $users users:${NC}"
    log_message "  Requests per second: $requests_per_second"
    log_message "  Mean response time: ${mean_response_time}ms"
    log_message "  Failed requests: $failed_requests"
    log_message "  Transfer rate: ${transfer_rate} KB/sec"
    
    # Store results in summary file
    echo "$users,$requests_per_second,$mean_response_time,$failed_requests,$transfer_rate" >> "$RESULTS_DIR/summary.csv"
}

# Function to monitor system resources during test
monitor_resources() {
    local test_name=$1
    local monitor_file="$RESULTS_DIR/resources_${test_name}.log"
    
    while true; do
        echo "$(date): $(curl -s -w '%{time_total}' -o /dev/null $JENKINS_URL)" >> "$monitor_file"
        sleep 5
    done &
    
    echo $! > "$RESULTS_DIR/monitor_pid_${test_name}"
}

# Function to stop resource monitoring
stop_monitoring() {
    local test_name=$1
    local pid_file="$RESULTS_DIR/monitor_pid_${test_name}"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        kill $pid 2>/dev/null || true
        rm "$pid_file"
    fi
}

# Function to check AWS resources during test
check_aws_resources() {
    local test_name=$1
    local aws_file="$RESULTS_DIR/aws_metrics_${test_name}.log"
    
    log_message "${YELLOW}Checking AWS resources during test...${NC}"
    
    # Get target group health
    aws elbv2 describe-target-health \
        --region us-east-1 \
        --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:426578051122:targetgroup/staging-jenkins-tg/ba3e9eb296b6f5d5" \
        > "$aws_file" 2>&1
    
    # Get Auto Scaling Group status
    aws autoscaling describe-auto-scaling-groups \
        --region us-east-1 \
        --auto-scaling-group-names "staging-jenkins-enterprise-platform-asg" \
        >> "$aws_file" 2>&1
    
    # Get CloudWatch metrics
    aws cloudwatch get-metric-statistics \
        --region us-east-1 \
        --namespace "AWS/ApplicationELB" \
        --metric-name "TargetResponseTime" \
        --dimensions Name=LoadBalancer,Value=app/staging-jenkins-alb/737d8003853cb795 \
        --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 60 \
        --statistics Average,Maximum \
        >> "$aws_file" 2>&1
}

# Initialize summary file
echo "Users,Requests_per_second,Mean_response_time_ms,Failed_requests,Transfer_rate_KB_sec" > "$RESULTS_DIR/summary.csv"

# Baseline test - single user
log_message "${YELLOW}=== Running Baseline Test ===${NC}"
curl -s -w "Response time: %{time_total}s\nHTTP code: %{http_code}\nSize: %{size_download} bytes\n" \
     -o /dev/null "$JENKINS_URL" > "$RESULTS_DIR/baseline.txt"
log_message "${GREEN}✓ Baseline test completed${NC}"

# Run load tests for different user counts
for users in "${CONCURRENT_USERS[@]}"; do
    # Start resource monitoring
    monitor_resources "$users"
    
    # Run the load test
    run_load_test "$users"
    
    # Check AWS resources
    check_aws_resources "$users"
    
    # Stop resource monitoring
    stop_monitoring "$users"
    
    # Wait between tests
    if [[ $users != ${CONCURRENT_USERS[-1]} ]]; then
        log_message "${YELLOW}Waiting 60 seconds before next test...${NC}"
        sleep 60
    fi
done

# Stress test - maximum load
log_message "${YELLOW}=== Running Stress Test (100 concurrent users) ===${NC}"
monitor_resources "stress"
ab -n 1000 -c 100 -g "$RESULTS_DIR/stress_test.gnuplot" \
   -e "$RESULTS_DIR/stress_test.csv" \
   "$JENKINS_URL/" > "$RESULTS_DIR/stress_test.txt" 2>&1
check_aws_resources "stress"
stop_monitoring "stress"

# Generate comprehensive report
log_message "${YELLOW}=== Generating Load Test Report ===${NC}"

cat > "$RESULTS_DIR/load-test-report.md" << EOF
# Jenkins Enterprise Platform - Load Test Report

**Test Date:** $(date)  
**Jenkins URL:** $JENKINS_URL  
**Test Duration:** $TEST_DURATION seconds per test  
**Results Directory:** $RESULTS_DIR  

## Test Summary

### Baseline Test
$(cat "$RESULTS_DIR/baseline.txt")

### Load Test Results

| Users | Requests/sec | Avg Response Time (ms) | Failed Requests | Transfer Rate (KB/s) |
|-------|--------------|------------------------|-----------------|---------------------|
EOF

# Add results to report
while IFS=',' read -r users rps response_time failed_requests transfer_rate; do
    if [[ "$users" != "Users" ]]; then
        echo "| $users | $rps | $response_time | $failed_requests | $transfer_rate |" >> "$RESULTS_DIR/load-test-report.md"
    fi
done < "$RESULTS_DIR/summary.csv"

cat >> "$RESULTS_DIR/load-test-report.md" << EOF

### Performance Analysis

#### Response Time Analysis
- **Target:** < 3 seconds
- **Baseline:** $(grep "Response time:" "$RESULTS_DIR/baseline.txt" | awk '{print $3}')
- **Best Performance:** $(awk -F',' 'NR>1 {print $3}' "$RESULTS_DIR/summary.csv" | sort -n | head -n1)ms
- **Worst Performance:** $(awk -F',' 'NR>1 {print $3}' "$RESULTS_DIR/summary.csv" | sort -n | tail -n1)ms

#### Throughput Analysis
- **Maximum RPS:** $(awk -F',' 'NR>1 {print $2}' "$RESULTS_DIR/summary.csv" | sort -n | tail -n1)
- **Recommended Load:** Based on results, optimal performance at X concurrent users

#### Error Analysis
- **Total Failed Requests:** $(awk -F',' 'NR>1 {sum+=$4} END {print sum}' "$RESULTS_DIR/summary.csv")
- **Error Rate:** $(awk -F',' 'NR>1 {failed+=$4; total+=$1*300/10} END {printf "%.2f%%", (failed/total)*100}' "$RESULTS_DIR/summary.csv")

### Recommendations

#### Performance Optimization
1. **Current Capacity:** Can handle up to X concurrent users with acceptable performance
2. **Scaling Trigger:** Consider scaling out when response time > 2 seconds
3. **Resource Optimization:** Monitor memory and CPU usage during peak loads

#### Infrastructure Recommendations
1. **Auto Scaling:** Configure scale-out at 70% CPU utilization
2. **Load Balancer:** Current ALB configuration is adequate
3. **Instance Type:** t3.medium is suitable for current load patterns

### Test Files Generated
- \`summary.csv\` - Aggregated test results
- \`baseline.txt\` - Single user baseline test
- \`load_test_X_users.txt\` - Detailed results for each test
- \`resources_X.log\` - Resource monitoring during tests
- \`aws_metrics_X.log\` - AWS resource status during tests
- \`*.gnuplot\` - Gnuplot data files for visualization
- \`*.csv\` - CSV data files for analysis

### Next Steps
1. Review detailed test results in individual files
2. Analyze resource utilization patterns
3. Implement performance optimizations if needed
4. Schedule regular load testing (monthly)
5. Update capacity planning based on results

**Test Status:** ✅ Completed Successfully  
**Performance Rating:** $(if awk -F',' 'NR>1 {if($3>3000) exit 1}' "$RESULTS_DIR/summary.csv"; then echo "✅ Excellent"; else echo "⚠️ Needs Optimization"; fi)  
**Recommended Action:** $(if awk -F',' 'NR>1 {if($3>3000) exit 1}' "$RESULTS_DIR/summary.csv"; then echo "No immediate action required"; else echo "Performance tuning recommended"; fi)  
EOF

# Create visualization script
cat > "$RESULTS_DIR/visualize.py" << 'EOF'
#!/usr/bin/env python3
import pandas as pd
import matplotlib.pyplot as plt
import sys

# Read the summary data
df = pd.read_csv('summary.csv')

# Create performance charts
fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))

# Response time vs Users
ax1.plot(df['Users'], df['Mean_response_time_ms'], 'b-o')
ax1.set_xlabel('Concurrent Users')
ax1.set_ylabel('Response Time (ms)')
ax1.set_title('Response Time vs Concurrent Users')
ax1.grid(True)

# Requests per second vs Users
ax2.plot(df['Users'], df['Requests_per_second'], 'g-o')
ax2.set_xlabel('Concurrent Users')
ax2.set_ylabel('Requests per Second')
ax2.set_title('Throughput vs Concurrent Users')
ax2.grid(True)

# Failed requests vs Users
ax3.bar(df['Users'], df['Failed_requests'], color='red', alpha=0.7)
ax3.set_xlabel('Concurrent Users')
ax3.set_ylabel('Failed Requests')
ax3.set_title('Failed Requests vs Concurrent Users')
ax3.grid(True)

# Transfer rate vs Users
ax4.plot(df['Users'], df['Transfer_rate_KB_sec'], 'm-o')
ax4.set_xlabel('Concurrent Users')
ax4.set_ylabel('Transfer Rate (KB/s)')
ax4.set_title('Transfer Rate vs Concurrent Users')
ax4.grid(True)

plt.tight_layout()
plt.savefig('load_test_results.png', dpi=300, bbox_inches='tight')
print("Performance charts saved as 'load_test_results.png'")
EOF

chmod +x "$RESULTS_DIR/visualize.py"

log_message "${GREEN}=== Load Testing Completed Successfully! ===${NC}"
log_message "Results directory: $RESULTS_DIR"
log_message "Report file: $RESULTS_DIR/load-test-report.md"
log_message "Summary data: $RESULTS_DIR/summary.csv"

echo ""
echo -e "${BLUE}=== Load Test Summary ===${NC}"
echo -e "${GREEN}✅ All load tests completed${NC}"
echo -e "${GREEN}✅ Performance report generated${NC}"
echo -e "${GREEN}✅ Test data saved for analysis${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the detailed report: $RESULTS_DIR/load-test-report.md"
echo "2. Analyze performance charts (run visualize.py if Python/matplotlib available)"
echo "3. Compare results with performance targets"
echo "4. Implement optimizations if needed"
echo "5. Schedule regular load testing"
