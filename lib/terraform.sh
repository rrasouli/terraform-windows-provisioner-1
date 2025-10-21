#!/bin/bash
# Terraform operations module

# Handle templates directory setup
function handle_templates_dir() {
    local templates_dir="$1"
    local action="$2"
    local platform="$3"
    local script_dir="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

    if [[ "$action" == "apply" ]]; then
        if [[ -d "$templates_dir" ]]; then
            log "Warning: Directory ${templates_dir} already exists"
            log "This may contain Terraform state from a previous run"
            log "Do you want to remove it and start fresh? (yes/no)"
            read -p "Answer: " answer

            case $answer in
                "yes")
                    log "Removing existing directory: ${templates_dir}"
                    rm -rf "$templates_dir" || error "Failed to remove directory: ${templates_dir}"
                    mkdir -p "$templates_dir" || error "Failed to create directory: ${templates_dir}"
                    cp -R "${script_dir}/${platform}/." "$templates_dir" || error "Failed to copy templates"
                    ;;
                "no")
                    log "Using existing directory: ${templates_dir}"
                    log "Terraform will reuse existing state"
                    ;;
                *)
                    error "Invalid answer: ${answer}. Please answer 'yes' or 'no'"
                    ;;
            esac
        else
            log "Creating templates directory: ${templates_dir}"
            mkdir -p "$templates_dir" || error "Failed to create directory: ${templates_dir}"
            cp -R "${script_dir}/${platform}/." "$templates_dir" || error "Failed to copy templates"
        fi
    fi
}

# Create ConfigMap for Windows instances
function create_configmap() {
    local templates_dir="$1"
    local platform="$2"

    log "Creating ConfigMap for Windows instances..."

    local wmco_namespace
    wmco_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}")

    if [[ -z "$wmco_namespace" ]]; then
        error "Failed to get WMCO namespace. Is the Windows Machine Config Operator installed?"
    fi

    log "WMCO namespace: $wmco_namespace"

    local config_file="${templates_dir}/byoh_cm.yaml"

    # Change to templates directory to run terraform output
    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    # Create ConfigMap YAML
    cat > "$config_file" << EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: windows-instances
  namespace: ${wmco_namespace}
data:
EOF

    # Add instance IPs to ConfigMap
    local instance_ips=$(terraform output -json instance_ip 2>/dev/null | jq -r '.[]')

    if [[ -z "$instance_ips" ]]; then
        error "Failed to get instance IPs from Terraform output"
    fi

    local username=$(get_user_name "$platform")

    for ip in $instance_ips; do
        # Remove quotes if present
        ip="${ip%\"}"
        ip="${ip#\"}"

        cat >> "$config_file" << EOF
  ${ip}: |-
    username=${username}
EOF
    done

    log "ConfigMap file created: ${config_file}"

    # Apply ConfigMap
    if oc get configmap windows-instances -n "$wmco_namespace" &>/dev/null; then
        log "ConfigMap already exists, deleting and recreating..."
        oc delete configmap windows-instances -n "$wmco_namespace" || log "Warning: Failed to delete existing ConfigMap"
    fi

    oc create -f "$config_file" || error "Failed to create ConfigMap"

    log "ConfigMap created successfully"
}

# Run Terraform init
function terraform_init() {
    local templates_dir="$1"

    log "Initializing Terraform in: ${templates_dir}"

    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    if ! terraform init; then
        error "Terraform init failed"
    fi

    log "Terraform initialized successfully"
}

# Run Terraform apply
function terraform_apply() {
    local templates_dir="$1"
    local terraform_args="$2"

    log "Running Terraform apply with arguments: ${terraform_args}"

    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    # shellcheck disable=SC2086
    if ! terraform apply --auto-approve $terraform_args; then
        error "Terraform apply failed"
    fi

    log "Terraform apply completed successfully"
}

# Run Terraform destroy
function terraform_destroy() {
    local templates_dir="$1"
    local terraform_args="$2"

    log "Running Terraform destroy with arguments: ${terraform_args}"

    cd "$templates_dir" || error "Failed to change to templates directory: ${templates_dir}"

    # shellcheck disable=SC2086
    if ! terraform destroy --auto-approve $terraform_args; then
        error "Terraform destroy failed"
    fi

    log "Terraform destroy completed successfully"
}

# Clean up templates directory
function cleanup_templates_dir() {
    local templates_dir="$1"

    if [[ -d "$templates_dir" ]]; then
        log "Removing templates directory: ${templates_dir}"
        rm -rf "$templates_dir" || error "Failed to remove directory: ${templates_dir}"
        log "Cleanup completed successfully"
    else
        log "Nothing to clean: ${templates_dir} does not exist"
    fi
}

# Delete ConfigMap
function delete_configmap() {
    local templates_dir="$1"

    log "Deleting ConfigMap..."

    local config_file="${templates_dir}/byoh_cm.yaml"

    if [[ ! -f "$config_file" ]]; then
        log "ConfigMap file not found: ${config_file}"
        return 0
    fi

    local wmco_namespace
    wmco_namespace=$(oc get deployment --all-namespaces -o=jsonpath="{.items[?(@.metadata.name=='windows-machine-config-operator')].metadata.namespace}")

    if [[ -n "$wmco_namespace" ]] && oc get configmap windows-instances -n "$wmco_namespace" &>/dev/null; then
        oc delete -f "$config_file" || log "Warning: Failed to delete ConfigMap"
        log "ConfigMap deleted successfully"
    else
        log "ConfigMap does not exist, skipping deletion"
    fi
}
