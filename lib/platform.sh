#!/bin/bash
# Platform detection and configuration module

# Supported platforms
declare -ra SUPPORTED_PLATFORMS=("aws" "gcp" "azure" "vsphere" "nutanix" "none")

# Detect platform from cluster
function get_platform() {
    local platform

    platform=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.type}" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if [[ -z "$platform" ]]; then
        error "Failed to detect platform from cluster"
    fi

    if [[ ! " ${SUPPORTED_PLATFORMS[@]} " =~ " ${platform} " ]]; then
        error "Platform ${platform} not supported. Supported platforms: ${SUPPORTED_PLATFORMS[*]}"
    fi

    echo "$platform"
}

# Get platform-specific username
function get_user_name() {
    local platform="$1"

    case $platform in
        "aws"|"gcp"|"vsphere"|"none"|"nutanix")
            echo "$(get_config 'WINDOWS_ADMIN_USERNAME' 'Administrator')"
            ;;
        "azure")
            echo "$(get_config 'WINDOWS_ADMIN_USERNAME' 'capi')"
            ;;
        *)
            error "Platform ${platform} not supported for username resolution"
            ;;
    esac
}

# Get Terraform arguments for platform
function get_terraform_arguments() {
    local platform="$1"
    local byoh_name="$2"
    local num_byoh="$3"
    local win_version="$4"

    local terraform_args=""

    case $platform in
        "aws")
            terraform_args=$(get_aws_terraform_args "$byoh_name" "$num_byoh")
            ;;
        "gcp")
            terraform_args=$(get_gcp_terraform_args "$byoh_name" "$num_byoh")
            ;;
        "azure")
            terraform_args=$(get_azure_terraform_args "$byoh_name" "$num_byoh" "$win_version")
            ;;
        "vsphere")
            terraform_args=$(get_vsphere_terraform_args "$byoh_name" "$num_byoh" "$win_version")
            ;;
        "nutanix")
            terraform_args=$(get_nutanix_terraform_args "$byoh_name" "$num_byoh" "$win_version")
            ;;
        "none")
            terraform_args=$(get_none_terraform_args "$byoh_name" "$num_byoh")
            ;;
        *)
            error "Platform ${platform} not supported for Terraform arguments"
            ;;
    esac

    echo "$terraform_args"
}

# AWS Terraform arguments
function get_aws_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}")
    local windows_ami=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.ami.id}")
    local cluster_name=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].metadata.labels.machine\.openshift\.io\/cluster-api-cluster}")
    local region=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.aws.region}")

    # Get configuration values
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local instance_type=$(get_config "AWS_INSTANCE_TYPE" "m5a.large")
    local volume_size=$(get_config "AWS_ROOT_VOLUME_SIZE" "120")
    local volume_type=$(get_config "AWS_ROOT_VOLUME_TYPE" "gp2")
    local env_tag=$(get_config "ENVIRONMENT_TAG" "production")
    local managed_by=$(get_config "MANAGED_BY_TAG" "terraform")
    local container_port=$(get_config "WINDOWS_CONTAINER_LOGS_PORT" "10250")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_worker_ami=${windows_ami} --var winc_cluster_name=${cluster_name} --var winc_region=${region} --var winc_instance_type='${instance_type}' --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}' --var root_volume_size=${volume_size} --var root_volume_type='${volume_type}' --var environment_tag='${env_tag}' --var managed_by_tag='${managed_by}' --var container_logs_port=${container_port}"
}

# GCP Terraform arguments
function get_gcp_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}" | cut -d "." -f1)
    local zone=$(oc get machine.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[0].metadata.labels.machine\.openshift\.io\/zone}")
    local region=$(oc get infrastructure cluster -o=jsonpath="{.status.platformStatus.gcp.region}")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_zone=${zone} --var winc_region=${region} --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}

# Azure Terraform arguments
function get_azure_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"
    local win_version="$3"

    # Azure computer name can't take more than 15 characters
    if [[ ${#byoh_name} -gt 13 ]]; then
        log "Warning: Azure instance names longer than 13 characters will be truncated"
        byoh_name="${byoh_name:0:13}"
    fi

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")
    local resource_group="${ARM_RESOURCEGROUP}"
    local resource_prefix="${ARM_RESOURCE_PREFIX}"
    local sku="2022-datacenter-smalldisk"

    if [[ "$win_version" == "2019" ]]; then
        sku="2019-datacenter-smalldisk"
    fi

    # Get configuration values
    local admin_username=$(get_user_name "azure")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")
    local instance_type=$(get_config "AZURE_INSTANCE_SIZE" "Standard_D2s_v3")
    local vm_extension_version=$(get_config "AZURE_VM_EXTENSION_HANDLER_VERSION" "1.9")
    local env_tag=$(get_config "ENVIRONMENT_TAG" "production")
    local managed_by=$(get_config "MANAGED_BY_TAG" "terraform")
    local container_port=$(get_config "WINDOWS_CONTAINER_LOGS_PORT" "10250")

    # Determine image version based on Windows version
    local image_version
    if [[ "$win_version" == "2019" ]]; then
        image_version=$(get_config "AZURE_2019_IMAGE_VERSION" "latest")
    else
        image_version=$(get_config "AZURE_2022_IMAGE_VERSION" "latest")
    fi

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_resource_group=${resource_group} --var winc_resource_prefix=${resource_prefix} --var winc_worker_sku=${sku} --var winc_instance_type='${instance_type}' --var admin_username='${admin_username}' --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}' --var vm_extension_handler_version='${vm_extension_version}' --var windows_image_version='${image_version}' --var environment_tag='${env_tag}' --var managed_by_tag='${managed_by}' --var container_logs_port=${container_port}"
}

# vSphere Terraform arguments
function get_vsphere_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"
    local win_version="$3"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")
    local datacenter=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.workspace.datacenter}")
    local datastore=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.workspace.datastore}")
    local folder=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.workspace.folder}")
    local network=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.network.devices[0].networkName}")
    local template="Windows-Server-${win_version}-Template"
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_datacenter=${datacenter} --var winc_datastore=${datastore} --var winc_folder=${folder} --var winc_network=${network} --var winc_template=${template} --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}

# Nutanix Terraform arguments
function get_nutanix_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"
    local win_version="$3"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker,windowsmachineconfig.openshift.io/byoh!=true" -o=jsonpath="{.items[0].metadata.name}")
    local cluster_uuid=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.cluster.uuid}")
    local subnet_uuid=$(oc get machineset.machine.openshift.io -n openshift-machine-api -o=jsonpath="{.items[?(@.spec.template.metadata.labels.machine\.openshift\.io\/os-id=='Windows')].spec.template.spec.providerSpec.value.subnets[0].uuid}")
    local image_name="Windows-Server-${win_version}"
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_cluster_uuid=${cluster_uuid} --var winc_subnet_uuid=${subnet_uuid} --var winc_image_name=${image_name} --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}

# None (Baremetal) Terraform arguments
function get_none_terraform_args() {
    local byoh_name="$1"
    local num_byoh="$2"

    local win_machine_hostname=$(oc get nodes -l "node-role.kubernetes.io/worker" -o=jsonpath="{.items[0].status.addresses[?(@.type=='Hostname')].address}")
    local region=$(get_config "AWS_DEFAULT_REGION" "us-east-1")
    local admin_password=$(get_config "WINC_ADMIN_PASSWORD")
    local ssh_key=$(get_config "WINC_SSH_PUBLIC_KEY")

    echo "--var winc_number_workers=${num_byoh} --var winc_machine_hostname=${win_machine_hostname} --var winc_instance_name=${byoh_name} --var winc_region=${region} --var admin_password='${admin_password}' --var ssh_public_key='${ssh_key}'"
}
