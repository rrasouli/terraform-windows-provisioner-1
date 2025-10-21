#!/bin/bash
# Credential management module
# Handles loading credentials from multiple sources

# Load Windows credentials from environment or config file
function load_windows_credentials() {
    local winc_password=$(get_config "WINC_ADMIN_PASSWORD")
    local winc_ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    if [[ -z "$winc_password" || -z "$winc_ssh_key" ]]; then
        log "Windows credentials not found in environment or config file"
        log "Checking legacy credentials file..."

        # Check legacy credentials file for backward compatibility
        local legacy_creds_file="${HOME}/.config/winc/credentials"
        if [[ -f "$legacy_creds_file" ]]; then
            log "Loading credentials from legacy file: $legacy_creds_file"
            source "$legacy_creds_file"
            winc_password=$(get_config "WINC_ADMIN_PASSWORD")
            winc_ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
        fi
    fi

    # Validate credentials are loaded
    if [[ -z "$winc_password" ]]; then
        error "WINC_ADMIN_PASSWORD is required but not set. Please set it via environment variable or config file."
    fi

    if [[ -z "$winc_ssh_key" ]]; then
        error "WINC_SSH_PUBLIC_KEY is required but not set. Please set it via environment variable or config file."
    fi

    # Export for use in Terraform
    export WINC_ADMIN_PASSWORD="$winc_password"
    export WINC_SSH_PUBLIC_KEY="$winc_ssh_key"

    log "Windows credentials loaded successfully"
}

# Export cloud provider credentials from cluster secrets
function export_cloud_credentials() {
    local platform="$1"

    log "Exporting cloud credentials for platform: $platform"

    case $platform in
        "aws")
            export_aws_credentials
            ;;
        "gcp")
            export_gcp_credentials
            ;;
        "azure")
            export_azure_credentials
            ;;
        "vsphere")
            export_vsphere_credentials
            ;;
        "nutanix")
            export_nutanix_credentials
            ;;
        "none")
            validate_aws_local_credentials
            ;;
        *)
            error "Platform ${platform} not supported for credential export"
            ;;
    esac

    log "Cloud credentials exported successfully for platform: $platform"
}

# AWS credential export
function export_aws_credentials() {
    if [[ -z "${AWS_ACCESS_KEY:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log "AWS credentials not in environment, attempting to load from cluster secrets..."

        local aws_key=$(oc -n kube-system get secret aws-creds -o=jsonpath='{.data.aws_access_key_id}' 2>/dev/null | base64 -d)
        local aws_secret=$(oc -n kube-system get secret aws-creds -o=jsonpath='{.data.aws_secret_access_key}' 2>/dev/null | base64 -d)

        if [[ -z "$aws_key" ]] || [[ -z "$aws_secret" ]]; then
            error "Failed to load AWS credentials from cluster secrets"
        fi

        export AWS_ACCESS_KEY="$aws_key"
        export AWS_SECRET_ACCESS_KEY="$aws_secret"
    fi
}

# GCP credential export
function export_gcp_credentials() {
    if [[ -z "${GOOGLE_CREDENTIALS:-}" ]]; then
        log "GCP credentials not in environment, attempting to load from cluster secrets..."

        local gcp_creds=$(oc -n openshift-machine-api get secret gcp-cloud-credentials -o=jsonpath='{.data.service_account\.json}' 2>/dev/null | base64 -d)

        if [[ -z "$gcp_creds" ]]; then
            error "Failed to load GCP credentials from cluster secrets"
        fi

        export GOOGLE_CREDENTIALS="$gcp_creds"
    fi
}

# Azure credential export
function export_azure_credentials() {
    if [[ -z "${ARM_CLIENT_ID:-}" ]] || [[ -z "${ARM_CLIENT_SECRET:-}" ]]; then
        log "Azure credentials not in environment, attempting to load from cluster secrets..."

        local creds=$(oc -n kube-system get secret azure-credentials -o json 2>/dev/null)

        if [[ -z "$creds" ]]; then
            error "Failed to load Azure credentials from cluster secrets"
        fi

        local client_id=$(echo "$creds" | jq -r '.data.azure_client_id' | base64 -d)
        local client_secret=$(echo "$creds" | jq -r '.data.azure_client_secret' | base64 -d)
        local subscription_id=$(echo "$creds" | jq -r '.data.azure_subscription_id' | base64 -d)
        local tenant_id=$(echo "$creds" | jq -r '.data.azure_tenant_id' | base64 -d)
        local resource_prefix=$(echo "$creds" | jq -r '.data.azure_resource_prefix' | base64 -d)
        local resourcegroup=$(echo "$creds" | jq -r '.data.azure_resourcegroup' | base64 -d)

        export ARM_CLIENT_ID="$client_id"
        export ARM_CLIENT_SECRET="$client_secret"
        export ARM_SUBSCRIPTION_ID="$subscription_id"
        export ARM_TENANT_ID="$tenant_id"
        export ARM_RESOURCE_PREFIX="$resource_prefix"
        export ARM_RESOURCEGROUP="$resourcegroup"
    fi
}

# vSphere credential export
function export_vsphere_credentials() {
    if [[ -z "${VSPHERE_USER:-}" ]] || [[ -z "${VSPHERE_PASSWORD:-}" ]]; then
        log "vSphere credentials not in environment, attempting to load from cluster secrets..."

        local vsphere_user=$(oc -n kube-system get secret vsphere-creds -o=jsonpath='{.data.vcenter\.username}' 2>/dev/null | base64 -d)
        local vsphere_password=$(oc -n kube-system get secret vsphere-creds -o=jsonpath='{.data.vcenter\.password}' 2>/dev/null | base64 -d)
        local vsphere_server=$(oc -n kube-system get secret vsphere-creds -o=jsonpath='{.data.vcenter\.server}' 2>/dev/null | base64 -d)

        if [[ -z "$vsphere_user" ]] || [[ -z "$vsphere_password" ]] || [[ -z "$vsphere_server" ]]; then
            error "Failed to load vSphere credentials from cluster secrets"
        fi

        export VSPHERE_USER="$vsphere_user"
        export VSPHERE_PASSWORD="$vsphere_password"
        export VSPHERE_SERVER="$vsphere_server"
    fi
}

# Nutanix credential export
function export_nutanix_credentials() {
    if [[ -z "${NUTANIX_USERNAME:-}" ]] || [[ -z "${NUTANIX_PASSWORD:-}" ]]; then
        log "Nutanix credentials not in environment, attempting to load from cluster secrets..."

        local nutanix_creds=$(oc -n openshift-machine-api get secret nutanix-credentials -o=jsonpath='{.data.credentials}' 2>/dev/null | base64 -d)

        if [[ -z "$nutanix_creds" ]]; then
            error "Failed to load Nutanix credentials from cluster secrets"
        fi

        local nutanix_user=$(echo "$nutanix_creds" | jq -r '.[0].data.prismCentral.username')
        local nutanix_pass=$(echo "$nutanix_creds" | jq -r '.[0].data.prismCentral.password')

        export NUTANIX_USERNAME="$nutanix_user"
        export NUTANIX_PASSWORD="$nutanix_pass"
    fi
}

# Validate local AWS credentials for baremetal deployment
function validate_aws_local_credentials() {
    if [[ ! -f "$HOME/.aws/config" ]] || [[ ! -f "$HOME/.aws/credentials" ]]; then
        error "AWS credentials not found at ~/.aws/config or ~/.aws/credentials. Configure your AWS account following: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html"
    fi
    log "AWS local credentials validated"
}
