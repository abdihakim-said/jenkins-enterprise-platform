# Security Hardening Checklist for Jenkins Golden AMI
## Story 2.5: When Vulnerabilities found, harden the Golden Image

This checklist provides a comprehensive approach to hardening the Jenkins Golden AMI based on industry best practices and compliance frameworks.

## 🎯 Overview

This hardening checklist is designed to address vulnerabilities found during security scans and implement defense-in-depth security measures for the Jenkins Golden AMI.

### Compliance Frameworks
- ✅ CIS (Center for Internet Security) Benchmarks
- ✅ NIST Cybersecurity Framework
- ✅ AWS Security Best Practices
- ✅ OWASP Top 10

---

## 🔒 System-Level Hardening

### Operating System Security

#### ✅ User Account Management
- [ ] **Disable root login via SSH**
  ```bash
  sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
  ```
- [ ] **Create dedicated service accounts with minimal privileges**
- [ ] **Implement strong password policies**
- [ ] **Configure account lockout policies**
- [ ] **Remove unnecessary user accounts**

#### ✅ SSH Hardening
- [ ] **Change default SSH port (optional)**
- [ ] **Disable password authentication (use key-based only)**
  ```bash
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  ```
- [ ] **Configure SSH key-based authentication**
- [ ] **Limit SSH access to specific users/groups**
- [ ] **Enable SSH protocol version 2 only**
- [ ] **Configure SSH idle timeout**

#### ✅ Network Security
- [ ] **Configure UFW firewall with restrictive rules**
  ```bash
  ufw --force enable
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp    # SSH
  ufw allow 8080/tcp  # Jenkins
  ufw allow 9100/tcp  # Node Exporter
  ```
- [ ] **Disable unnecessary network services**
- [ ] **Configure fail2ban for intrusion prevention**
- [ ] **Implement network segmentation**

#### ✅ File System Security
- [ ] **Set proper file permissions**
  ```bash
  chmod 600 /etc/ssh/sshd_config
  chmod 644 /etc/passwd
  chmod 640 /etc/shadow
  ```
- [ ] **Configure file integrity monitoring**
- [ ] **Enable audit logging**
- [ ] **Implement log rotation**
- [ ] **Secure temporary directories**

---

## ☕ Java Security Hardening

### JVM Security Configuration

#### ✅ JVM Security Properties
- [ ] **Configure secure random number generation**
  ```bash
  echo "securerandom.source=file:/dev/urandom" >> $JAVA_HOME/conf/security/java.security
  ```
- [ ] **Disable unnecessary Java features**
- [ ] **Configure JVM security policies**
- [ ] **Set appropriate heap and memory limits**

#### ✅ Java Security Manager
- [ ] **Enable Java Security Manager (if applicable)**
- [ ] **Configure security policy files**
- [ ] **Restrict file system access**
- [ ] **Control network permissions**

---

## 🏗️ Jenkins Security Hardening

### Jenkins Core Security

#### ✅ Authentication & Authorization
- [ ] **Enable Jenkins security**
- [ ] **Configure LDAP/Active Directory integration**
- [ ] **Implement role-based access control (RBAC)**
- [ ] **Enable two-factor authentication**
- [ ] **Configure session timeout**

#### ✅ Jenkins Configuration Security
- [ ] **Disable Jenkins CLI over remoting**
  ```groovy
  jenkins.CLI.get().setEnabled(false)
  ```
- [ ] **Configure CSRF protection**
- [ ] **Enable agent-to-master security**
- [ ] **Restrict script execution**
- [ ] **Configure build authorization**

#### ✅ Plugin Security
- [ ] **Install only necessary plugins**
- [ ] **Keep plugins updated**
- [ ] **Review plugin permissions**
- [ ] **Configure plugin security settings**

### Jenkins Environment Security

#### ✅ Build Environment
- [ ] **Isolate build environments**
- [ ] **Configure resource limits**
- [ ] **Implement build sandboxing**
- [ ] **Secure artifact storage**

#### ✅ Secrets Management
- [ ] **Use Jenkins Credentials Plugin**
- [ ] **Integrate with AWS Secrets Manager**
- [ ] **Avoid hardcoded secrets**
- [ ] **Implement secret rotation**

---

## 🐳 Container Security (Docker)

### Docker Daemon Security

#### ✅ Docker Configuration
- [ ] **Run Docker daemon in rootless mode (if possible)**
- [ ] **Configure Docker daemon with TLS**
- [ ] **Limit Docker daemon privileges**
- [ ] **Configure Docker logging**

#### ✅ Container Security
- [ ] **Use minimal base images**
- [ ] **Scan container images for vulnerabilities**
- [ ] **Implement container resource limits**
- [ ] **Configure container security contexts**

---

## 📊 Monitoring & Logging

### Security Monitoring

#### ✅ Log Management
- [ ] **Configure centralized logging**
- [ ] **Enable audit logging**
- [ ] **Set up log retention policies**
- [ ] **Implement log integrity protection**

#### ✅ Security Monitoring
- [ ] **Deploy security monitoring agents**
- [ ] **Configure intrusion detection**
- [ ] **Set up vulnerability scanning**
- [ ] **Implement file integrity monitoring**

#### ✅ Alerting
- [ ] **Configure security alerts**
- [ ] **Set up incident response procedures**
- [ ] **Implement automated responses**
- [ ] **Configure notification channels**

---

## 🔐 Encryption & Data Protection

### Data Encryption

#### ✅ Encryption at Rest
- [ ] **Enable EBS volume encryption**
- [ ] **Encrypt Jenkins home directory**
- [ ] **Secure backup encryption**
- [ ] **Configure database encryption**

#### ✅ Encryption in Transit
- [ ] **Enable HTTPS for Jenkins**
- [ ] **Configure TLS for all communications**
- [ ] **Implement certificate management**
- [ ] **Use secure protocols only**

---

## 🛡️ Vulnerability Management

### Vulnerability Assessment

#### ✅ Regular Scanning
- [ ] **Implement automated vulnerability scanning**
- [ ] **Schedule regular security assessments**
- [ ] **Configure vulnerability databases**
- [ ] **Set up scan result analysis**

#### ✅ Patch Management
- [ ] **Establish patch management process**
- [ ] **Automate security updates**
- [ ] **Test patches before deployment**
- [ ] **Maintain patch inventory**

---

## 📋 Compliance & Governance

### Compliance Requirements

#### ✅ CIS Benchmarks
- [ ] **Implement CIS Ubuntu 22.04 benchmarks**
- [ ] **Configure CIS Docker benchmarks**
- [ ] **Apply CIS Kubernetes benchmarks (if applicable)**
- [ ] **Document compliance status**

#### ✅ Audit & Documentation
- [ ] **Maintain security documentation**
- [ ] **Implement audit trails**
- [ ] **Configure compliance reporting**
- [ ] **Regular compliance assessments**

---

## 🚀 Implementation Scripts

### Automated Hardening Script

```bash
#!/bin/bash
# Jenkins Golden AMI Hardening Script

set -euo pipefail

# System hardening
harden_system() {
    echo "🔒 Applying system hardening..."
    
    # SSH hardening
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    
    # Firewall configuration
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 8080/tcp
    ufw allow 9100/tcp
    
    # File permissions
    chmod 600 /etc/ssh/sshd_config
    chmod 644 /etc/passwd
    chmod 640 /etc/shadow
    
    systemctl restart ssh
}

# Jenkins hardening
harden_jenkins() {
    echo "🏗️ Applying Jenkins hardening..."
    
    # Jenkins security configuration
    cat > /var/lib/jenkins/init.groovy.d/security.groovy << 'EOF'
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

// Enable security
if (!instance.isUseSecurity()) {
    instance.setSecurityRealm(new HudsonPrivateSecurityRealm(false))
    instance.setAuthorizationStrategy(new FullControlOnceLoggedInAuthorizationStrategy())
    instance.save()
}

// Disable CLI over remoting
jenkins.CLI.get().setEnabled(false)

// Enable CSRF protection
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))
instance.save()
EOF

    chown jenkins:jenkins /var/lib/jenkins/init.groovy.d/security.groovy
}

# Docker hardening
harden_docker() {
    echo "🐳 Applying Docker hardening..."
    
    # Docker daemon configuration
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true
}
EOF

    systemctl restart docker
}

# Main execution
main() {
    echo "🚀 Starting Jenkins Golden AMI hardening..."
    
    harden_system
    harden_jenkins
    harden_docker
    
    echo "✅ Hardening completed successfully!"
}

main "$@"
```

---

## 🧪 Validation & Testing

### Security Validation

#### ✅ Automated Testing
- [ ] **Run security scan after hardening**
- [ ] **Validate configuration changes**
- [ ] **Test security controls**
- [ ] **Verify compliance status**

#### ✅ Manual Verification
- [ ] **Review security configurations**
- [ ] **Test access controls**
- [ ] **Validate encryption settings**
- [ ] **Check monitoring functionality**

---

## 📚 References & Resources

### Security Standards
- [CIS Ubuntu 22.04 Benchmark](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [AWS Security Best Practices](https://aws.amazon.com/security/security-resources/)

### Jenkins Security
- [Jenkins Security Documentation](https://www.jenkins.io/doc/book/security/)
- [Jenkins Hardening Guide](https://www.jenkins.io/doc/book/system-administration/security/)

### Tools & Utilities
- [Trivy Vulnerability Scanner](https://github.com/aquasecurity/trivy)
- [Lynis Security Auditing Tool](https://cisofy.com/lynis/)
- [ClamAV Antivirus](https://www.clamav.net/)

---

## 📝 Implementation Tracking

### Hardening Status

| Category | Items | Completed | Status |
|----------|-------|-----------|--------|
| System Security | 15 | 0 | ⏳ Pending |
| Java Security | 8 | 0 | ⏳ Pending |
| Jenkins Security | 12 | 0 | ⏳ Pending |
| Container Security | 8 | 0 | ⏳ Pending |
| Monitoring | 10 | 0 | ⏳ Pending |
| Encryption | 8 | 0 | ⏳ Pending |
| Vulnerability Mgmt | 8 | 0 | ⏳ Pending |
| Compliance | 8 | 0 | ⏳ Pending |

### Next Steps

1. **Prioritize Critical Items**: Focus on high-impact security controls first
2. **Automate Implementation**: Create scripts for repeatable hardening
3. **Validate Changes**: Test each hardening measure thoroughly
4. **Document Process**: Maintain detailed implementation records
5. **Regular Updates**: Keep hardening measures current with threats

---

*This checklist should be reviewed and updated regularly to address new vulnerabilities and security requirements.*
