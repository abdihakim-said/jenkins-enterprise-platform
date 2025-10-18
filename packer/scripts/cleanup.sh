#!/bin/bash
# Cleanup script for Golden AMI

set -e

echo "=== Golden AMI Cleanup Started ==="

# Clean package cache
sudo apt autoremove -y
sudo apt autoclean
sudo apt clean

# Clear logs
sudo truncate -s 0 /var/log/*log
sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;

# Clear bash history
history -c
cat /dev/null > ~/.bash_history

# Clear temporary files
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Clear SSH keys (will be regenerated)
sudo rm -f /home/ubuntu/.ssh/authorized_keys
sudo rm -f /root/.ssh/authorized_keys

# Clear machine-id (will be regenerated)
sudo truncate -s 0 /etc/machine-id

# Clear cloud-init
sudo cloud-init clean --logs

echo "✅ Golden AMI cleanup completed"
