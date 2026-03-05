#!/bin/bash
# ==============================================================================
# BIND DNS Server Setup for WINC-1633 PTR Record Management
# ==============================================================================
# This script configures BIND DNS server to accept RFC 2136 dynamic updates
# for PTR record creation by Terraform
#
# Usage: sudo ./setup-bind-dns.sh <reverse-zone> <dns-domain>
# Example: sudo ./setup-bind-dns.sh "0.10.in-addr.arpa" "winc.devcluster.openshift.com"
# ==============================================================================

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root"
  exit 1
fi

# Check arguments
if [ $# -ne 2 ]; then
  echo "Usage: $0 <reverse-zone> <dns-domain>"
  echo "Example: $0 '0.10.in-addr.arpa' 'winc.devcluster.openshift.com'"
  exit 1
fi

REVERSE_ZONE="$1"
DNS_DOMAIN="$2"
KEY_NAME="update-key"
BIND_DIR="/etc/bind"
ZONE_DIR="/var/lib/bind"

echo "=========================================="
echo "BIND DNS Setup for PTR Records"
echo "=========================================="
echo "Reverse Zone: $REVERSE_ZONE"
echo "DNS Domain: $DNS_DOMAIN"
echo "Key Name: $KEY_NAME"
echo ""

# Step 1: Install BIND if not present
echo "[1/6] Checking BIND installation..."
if ! command -v named &> /dev/null; then
  echo "Installing BIND9..."
  apt-get update
  apt-get install -y bind9 bind9utils bind9-doc
else
  echo "✓ BIND9 already installed"
fi

# Step 2: Generate TSIG key
echo ""
echo "[2/6] Generating TSIG key for RFC 2136 authentication..."
KEY_FILE="${BIND_DIR}/${KEY_NAME}.conf"

if [ -f "$KEY_FILE" ]; then
  echo "⚠ Key file already exists: $KEY_FILE"
  read -p "Regenerate key? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Using existing key..."
  else
    rm -f "$KEY_FILE"
    tsig-keygen -a hmac-sha256 "$KEY_NAME" > "$KEY_FILE"
    chmod 640 "$KEY_FILE"
    chown root:bind "$KEY_FILE"
    echo "✓ New TSIG key generated"
  fi
else
  tsig-keygen -a hmac-sha256 "$KEY_NAME" > "$KEY_FILE"
  chmod 640 "$KEY_FILE"
  chown root:bind "$KEY_FILE"
  echo "✓ TSIG key generated: $KEY_FILE"
fi

# Extract key secret for Terraform
KEY_SECRET=$(grep "secret" "$KEY_FILE" | cut -d'"' -f2)
echo ""
echo "=========================================="
echo "IMPORTANT: Save this TSIG key secret for Terraform:"
echo "dns_key_secret = \"$KEY_SECRET\""
echo "=========================================="
echo ""

# Step 3: Create reverse zone file
echo "[3/6] Creating reverse zone file..."
ZONE_FILE="${ZONE_DIR}/db.${REVERSE_ZONE}"

if [ -f "$ZONE_FILE" ]; then
  echo "⚠ Zone file already exists: $ZONE_FILE"
else
  SERIAL=$(date +%Y%m%d01)
  cat > "$ZONE_FILE" <<EOF
\$TTL 300
@       IN      SOA     ns1.${DNS_DOMAIN}. admin.${DNS_DOMAIN}. (
                        ${SERIAL} ; Serial
                        3600      ; Refresh
                        1800      ; Retry
                        604800    ; Expire
                        300 )     ; Minimum TTL
        IN      NS      ns1.${DNS_DOMAIN}.
EOF
  chmod 644 "$ZONE_FILE"
  chown bind:bind "$ZONE_FILE"
  echo "✓ Zone file created: $ZONE_FILE"
fi

# Step 4: Configure BIND zone
echo ""
echo "[4/6] Configuring BIND zone..."
ZONE_CONF="${BIND_DIR}/named.conf.local"

# Backup existing config
cp "$ZONE_CONF" "${ZONE_CONF}.backup.$(date +%Y%m%d-%H%M%S)"

# Check if zone already configured
if grep -q "zone \"${REVERSE_ZONE}\"" "$ZONE_CONF"; then
  echo "⚠ Zone already configured in $ZONE_CONF"
else
  cat >> "$ZONE_CONF" <<EOF

// WINC-1633: PTR record zone for BYOH Windows nodes
zone "${REVERSE_ZONE}" {
    type master;
    file "${ZONE_FILE}";
    allow-update { key ${KEY_NAME}; };
    allow-query { any; };
};

// Include TSIG key for RFC 2136 updates
include "${KEY_FILE}";
EOF
  echo "✓ Zone configuration added to $ZONE_CONF"
fi

# Step 5: Validate configuration
echo ""
echo "[5/6] Validating BIND configuration..."
if named-checkconf; then
  echo "✓ BIND configuration is valid"
else
  echo "✗ BIND configuration has errors"
  exit 1
fi

if named-checkzone "$REVERSE_ZONE" "$ZONE_FILE"; then
  echo "✓ Zone file is valid"
else
  echo "✗ Zone file has errors"
  exit 1
fi

# Step 6: Restart BIND
echo ""
echo "[6/6] Restarting BIND service..."
systemctl restart named
systemctl status named --no-pager

echo ""
echo "=========================================="
echo "✓ BIND DNS Setup Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. Add the TSIG key secret to your terraform.tfvars:"
echo "   dns_key_secret = \"$KEY_SECRET\""
echo ""
echo "2. Configure Terraform variables:"
echo "   dns_server       = \"$(hostname -I | awk '{print $1}')\""
echo "   dns_domain       = \"$DNS_DOMAIN\""
echo "   dns_reverse_zone = \"$REVERSE_ZONE\""
echo "   dns_key_name     = \"$KEY_NAME\""
echo "   dns_key_algorithm = \"hmac-sha256\""
echo ""
echo "3. Test DNS update with nsupdate:"
echo "   nsupdate -k $KEY_FILE <<EOF"
echo "   server $(hostname -I | awk '{print $1}')"
echo "   zone $REVERSE_ZONE"
echo "   update add 99.${REVERSE_ZONE} 300 PTR test.${DNS_DOMAIN}."
echo "   send"
echo "   EOF"
echo ""
echo "4. Verify PTR record:"
echo "   nslookup test.${DNS_DOMAIN}"
echo ""
echo "5. Run Terraform:"
echo "   cd terraform-windows-provisioner/vsphere  # or nutanix"
echo "   terraform init"
echo "   terraform apply"
echo ""
echo "=========================================="
