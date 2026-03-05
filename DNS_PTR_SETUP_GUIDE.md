# PTR Record Setup Guide for WINC-1633

## Overview

This guide explains how to configure PTR (reverse DNS) records for BYOH Windows nodes on vSphere and Nutanix platforms to resolve WINC-1633: DNS resolution failures.

## Problem Statement

BYOH Windows nodes on Nutanix/vSphere encounter DNS resolution failures because:
- MachineSet-created VMs get automatic PTR records from Machine API Operator
- BYOH nodes lack PTR records, causing WMCO errors: `no such host`
- Tests OCP-42496, OCP-42516, and related BYOH tests fail due to DNS issues

## Solution Approaches

Three implementation options are provided based on your DNS infrastructure:

### Option 1: RFC 2136 Dynamic DNS Updates (RECOMMENDED)

**Best for:** BIND DNS, Windows DNS Server, or any DNS supporting RFC 2136

**Advantages:**
- Industry standard (RFC 2136)
- Secure with TSIG authentication
- Widely supported
- Easy rollback on `terraform destroy`

**Requirements:**
- DNS server with RFC 2136 enabled
- TSIG key for authentication

### Option 2: PowerDNS API

**Best for:** Environments using PowerDNS with API enabled

**Advantages:**
- RESTful API integration
- Centralized DNS management
- Zone auto-creation

**Requirements:**
- PowerDNS server with API enabled
- API key

### Option 3: Windows DNS Server via PowerShell

**Best for:** Direct Windows DNS Server management

**Advantages:**
- No additional providers needed
- Direct DNS server control

**Requirements:**
- PowerShell remoting enabled
- Administrator credentials
- WinRM connectivity

---

## Implementation Guide

### Step 1: Choose Your DNS Approach

Based on your DNS infrastructure, choose ONE of the three options provided in:
- `vsphere/dns-ptr-records.tf`
- `nutanix/dns-ptr-records.tf`

### Step 2: Configure DNS Server (Option 1 - RFC 2136)

#### For BIND DNS Server:

1. **Generate TSIG key:**
```bash
tsig-keygen -a hmac-sha256 update-key > /etc/bind/update-key.conf
```

2. **Configure BIND zone to allow updates:**

Edit `/etc/bind/named.conf.local`:
```bind
zone "0.10.in-addr.arpa" {
    type master;
    file "/var/lib/bind/db.10.0";
    allow-update { key update-key; };
};

include "/etc/bind/update-key.conf";
```

3. **Create reverse zone file:**
```bash
sudo touch /var/lib/bind/db.10.0
sudo chown bind:bind /var/lib/bind/db.10.0
```

Edit `/var/lib/bind/db.10.0`:
```bind
$TTL 300
@       IN      SOA     ns1.example.com. admin.example.com. (
                        2024020401 ; Serial
                        3600       ; Refresh
                        1800       ; Retry
                        604800     ; Expire
                        300 )      ; Minimum TTL
        IN      NS      ns1.example.com.
```

4. **Restart BIND:**
```bash
sudo systemctl restart named
```

#### For Windows DNS Server:

1. **Create reverse lookup zone:**
```powershell
Add-DnsServerPrimaryZone -NetworkId "10.0.0.0/16" -ReplicationScope "Forest"
```

2. **Enable secure dynamic updates:**
```powershell
Set-DnsServerPrimaryZone -Name "0.10.in-addr.arpa" -DynamicUpdate Secure
```

3. **Create TSIG key (using dnssec-keygen from BIND utils):**
```powershell
# Install BIND utilities for Windows
# Then generate key:
dnssec-keygen -a hmac-sha256 -b 256 -n HOST update-key
```

4. **Configure zone for RFC 2136:**
```powershell
# Add the TSIG key to DNS server
# Note: Windows DNS native RFC 2136 support is limited
# Consider using PowerShell option (Option 3) instead
```

### Step 3: Configure Terraform Variables

Create or update your `terraform.tfvars` file:

#### vSphere Example:

```hcl
# Existing vSphere variables
winc_instance_name     = "winc-byoh"
winc_machine_hostname  = "worker-0"
vsphere_server         = "vcenter.example.com"
vsphere_user           = "administrator@vsphere.local"
vsphere_password       = "SecurePassword123"
winc_number_workers    = 2

# DNS PTR Configuration (NEW)
dns_server             = "10.0.76.5"
dns_domain             = "winc.devcluster.openshift.com"
dns_reverse_zone       = "0.10.in-addr.arpa."

# RFC 2136 Authentication (NEW)
dns_key_name           = "update-key"
dns_key_algorithm      = "hmac-sha256"
dns_key_secret         = "BASE64_ENCODED_KEY_HERE"

# Feature Flags (NEW)
enable_ptr_records     = true
validate_ptr_records   = true
```

#### Nutanix Example:

```hcl
# Existing Nutanix variables
winc_instance_name     = "winc-byoh"
winc_machine_hostname  = "worker-0"
nutanix_endpoint       = "prism-central.example.com"
nutanix_username       = "admin"
nutanix_password       = "SecurePassword123"
winc_number_workers    = 2

# DNS PTR Configuration (NEW)
dns_server             = "10.0.76.5"
dns_domain             = "winc.devcluster.openshift.com"
dns_reverse_zone       = "0.10.in-addr.arpa."

# RFC 2136 Authentication (NEW)
dns_key_name           = "update-key"
dns_key_algorithm      = "hmac-sha256"
dns_key_secret         = "BASE64_ENCODED_KEY_HERE"

# Feature Flags (NEW)
enable_ptr_records     = true
validate_ptr_records   = true
```

### Step 4: Extract TSIG Key Secret

```bash
# From BIND key file (/etc/bind/update-key.conf)
cat /etc/bind/update-key.conf
# Look for: secret "BASE64STRING";

# Or generate new key:
tsig-keygen -a hmac-sha256 update-key
```

### Step 5: Deploy Infrastructure

```bash
# Initialize Terraform
cd vsphere/  # or nutanix/
terraform init

# Plan deployment (verify PTR records will be created)
terraform plan

# Apply configuration
terraform apply

# Verify PTR records in output
terraform output ptr_records
```

### Step 6: Validate PTR Records

#### Manual Validation:

```bash
# Test PTR record resolution
nslookup 10.0.176.45 10.0.76.5

# Expected output:
# Server:  10.0.76.5
# Address: 10.0.76.5
#
# 45.176.0.10.in-addr.arpa name = winc-byoh-0.winc.devcluster.openshift.com
```

#### Automated Validation:

The Terraform configuration includes optional validation:

```hcl
variable "validate_ptr_records" {
  default = true  # Enable post-creation validation
}
```

---

## Reverse Zone Calculation

PTR records require correct reverse zone configuration:

| Subnet | Reverse Zone | Example |
|--------|--------------|---------|
| 10.0.0.0/16 | 0.10.in-addr.arpa. | 10.0.176.45 → 45.176.0.10.in-addr.arpa |
| 10.0.176.0/24 | 176.0.10.in-addr.arpa. | 10.0.176.45 → 45.176.0.10.in-addr.arpa |
| 192.168.1.0/24 | 1.168.192.in-addr.arpa. | 192.168.1.100 → 100.1.168.192.in-addr.arpa |

**Formula:** Reverse the IP address octets and append `in-addr.arpa.`

---

## CI/CD Integration (Prow)

### Environment Variables for Prow Jobs:

```yaml
# In Prow job configuration
env:
  - name: TF_VAR_dns_server
    value: "10.0.76.5"
  - name: TF_VAR_dns_domain
    value: "winc.devcluster.openshift.com"
  - name: TF_VAR_dns_reverse_zone
    value: "0.10.in-addr.arpa."
  - name: TF_VAR_dns_key_name
    value: "update-key"
  - name: TF_VAR_dns_key_algorithm
    value: "hmac-sha256"
  - name: TF_VAR_dns_key_secret
    valueFrom:
      secretKeyRef:
        name: dns-update-key
        key: tsig-secret
```

### Create Kubernetes Secret for TSIG Key:

```bash
kubectl create secret generic dns-update-key \
  --from-literal=tsig-secret="BASE64_ENCODED_KEY" \
  -n ci
```

---

## Troubleshooting

### PTR Records Not Created

1. **Check DNS server logs:**
```bash
# BIND
sudo tail -f /var/log/syslog | grep named

# Windows DNS
Get-EventLog -LogName "DNS Server" -Newest 20
```

2. **Verify TSIG key authentication:**
```bash
# Test TSIG key with nsupdate
nsupdate -k /etc/bind/update-key.conf <<EOF
server 10.0.76.5
zone 0.10.in-addr.arpa.
update add 45.0.10.in-addr.arpa. 300 PTR test.example.com.
send
EOF
```

3. **Check Terraform provider logs:**
```bash
TF_LOG=DEBUG terraform apply
```

### PTR Resolution Fails

1. **Verify DNS server is authoritative:**
```bash
dig @10.0.76.5 -x 10.0.176.45
```

2. **Check zone configuration:**
```bash
# BIND
named-checkzone 0.10.in-addr.arpa /var/lib/bind/db.10.0

# Windows DNS
Get-DnsServerZone -Name "0.10.in-addr.arpa"
```

3. **Verify PTR record exists:**
```bash
# BIND
dig @10.0.76.5 0.10.in-addr.arpa. AXFR | grep PTR

# Windows DNS
Get-DnsServerResourceRecord -ZoneName "0.10.in-addr.arpa" -RRType Ptr
```

### WMCO Still Reports DNS Errors

1. **Wait for DNS propagation (up to 5 minutes)**

2. **Check WMCO can resolve PTR:**
```bash
# From WMCO pod
oc rsh -n openshift-windows-machine-config-operator deployment/windows-machine-config-operator
nslookup 10.0.176.45
```

3. **Verify DNS server in cluster:**
```bash
oc get dns.config.openshift.io/cluster -o yaml
```

---

## Cleanup

PTR records are automatically removed when running:

```bash
terraform destroy
```

The DNS provider handles cleanup via Terraform lifecycle management.

---

## WINC-1633 Acceptance Criteria Validation

After implementation, verify:

1. ✅ **PTR records automatically provisioned:**
```bash
terraform output ptr_records
```

2. ✅ **nslookup returns expected FQDN:**
```bash
nslookup <BYOH-node-IP> <DNS-server>
```

3. ✅ **WMCO provisioning succeeds without DNS errors:**
```bash
# Check WMCO logs
oc logs -n openshift-windows-machine-config-operator deployment/windows-machine-config-operator

# Should NOT contain: "no such host"
```

4. ✅ **BYOH tests pass:**
- OCP-42496: Configure Windows instance with DNS
- OCP-42516: Configure Windows instance with both IP and DNS
- OCP-42484: Configure Windows instance with IP

---

## Security Considerations

1. **TSIG Key Protection:**
   - Store `dns_key_secret` in secure secret management (Vault, AWS Secrets Manager)
   - Never commit TSIG keys to version control
   - Rotate keys periodically

2. **DNS Access Control:**
   - Limit DNS update permissions to specific zones
   - Use firewall rules to restrict RFC 2136 access
   - Monitor DNS update logs for unauthorized changes

3. **Terraform State Security:**
   - Use remote state backend (S3, GCS, Terraform Cloud)
   - Enable state encryption
   - Restrict state file access

---

## References

- **WINC-1633:** https://issues.redhat.com/browse/WINC-1633
- **WINC-1508:** https://issues.redhat.com/browse/WINC-1508
- **RFC 2136:** Dynamic Updates in the DNS
- **Terraform DNS Provider:** https://registry.terraform.io/providers/hashicorp/dns/latest/docs
- **PowerDNS Provider:** https://registry.terraform.io/providers/pan-net/powerdns/latest/docs
