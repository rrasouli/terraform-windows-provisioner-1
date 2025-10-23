#!/bin/bash
# Configuration loading and management module
# Loads configuration from multiple sources with proper priority

# Configuration file locations
declare -r USER_CONFIG_FILE="${HOME}/.config/byoh-provisioner/config"
declare -r PROJECT_CONFIG_FILE="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/configs/defaults.conf"

# Load configuration from file
# Arguments:
#   $1 - Configuration file path
function load_config_file() {
    local config_file="$1"

    if [[ -f "$config_file" ]]; then
        log "Loading configuration from: $config_file"
        # Source the file in a safe way (only export variables)
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue

            # Remove leading/trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            # Remove quotes from value if present
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"

            # Only export if not already set in environment (environment takes precedence)
            if [[ -z "${!key:-}" ]]; then
                export "$key=$value"
            fi
        done < <(grep -v '^[[:space:]]*$' "$config_file")
    fi
}

# Get configuration value with priority order
# Priority: Environment Variable > User Config > Project Config > Default
# Arguments:
#   $1 - Variable name
#   $2 - Default value (optional)
function get_config() {
    local var_name="$1"
    local default_value="${2:-}"

    # Check if already set as environment variable
    if [[ -n "${!var_name:-}" ]]; then
        echo "${!var_name}"
        return 0
    fi

    # Return default if provided
    if [[ -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    fi

    # Return empty string if nothing found
    echo ""
}

# Load all configuration files in priority order
function load_all_configs() {
    # Load project defaults first
    if [[ -f "$PROJECT_CONFIG_FILE" ]]; then
        load_config_file "$PROJECT_CONFIG_FILE"
    fi

    # Load user config (overrides project defaults)
    if [[ -f "$USER_CONFIG_FILE" ]]; then
        load_config_file "$USER_CONFIG_FILE"
    fi

    # Environment variables take highest priority (already set)
    log "Configuration loaded successfully"
}

# Create default user config file
function create_user_config() {
    local config_dir="$(dirname "$USER_CONFIG_FILE")"

    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir" || error "Failed to create config directory: $config_dir"
    fi

    if [[ ! -f "$USER_CONFIG_FILE" ]]; then
        cat > "$USER_CONFIG_FILE" << 'EOF'
# BYOH Provisioner User Configuration
# This file is sourced by the provisioner and can override default settings

# Logging
# BYOH_LOG_LEVEL=INFO

# Terraform
# BYOH_TMP_DIR=/tmp/terraform_byoh

# Windows Credentials
# WINC_ADMIN_PASSWORD="YourSecurePassword"
# WINC_SSH_PUBLIC_KEY="ssh-rsa AAAA..."

# Windows Settings
# WINDOWS_ADMIN_USERNAME - Platform-specific (Azure: capi, Others: Administrator)
# WINDOWS_CONTAINER_LOGS_PORT=10250

# Azure-specific
# AZURE_VM_EXTENSION_HANDLER_VERSION=1.9
# AZURE_2019_IMAGE_VERSION=latest
# AZURE_2022_IMAGE_VERSION=latest

# AWS Configuration
# AWS_PROFILE - For SAML/SSO, set to your profile name (e.g., "saml")
#               Leave empty for CI/CD using environment variables
# AWS_PROFILE=saml

# Instance Tags
# ENVIRONMENT_TAG=production
# MANAGED_BY_TAG=terraform
EOF
        chmod 600 "$USER_CONFIG_FILE"
        log "Created user configuration file: $USER_CONFIG_FILE"
    else
        log "User configuration file already exists: $USER_CONFIG_FILE"
    fi
}

# Validate configuration
function validate_config() {
    log "Validating configuration..."

    # Check for required credentials
    local winc_password=$(get_config "WINC_ADMIN_PASSWORD")
    local winc_ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    if [[ -z "$winc_password" ]]; then
        log "Warning: WINC_ADMIN_PASSWORD not set. This is required for Windows instances."
    fi

    if [[ -z "$winc_ssh_key" ]]; then
        log "Warning: WINC_SSH_PUBLIC_KEY not set. This is required for SSH access."
    fi

    return 0
}
