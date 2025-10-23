# BYOH Provisioner - Bring Your Own Host for Windows Nodes

A generic, configurable tool for provisioning and managing Windows worker nodes across multiple cloud platforms. This project provides automated BYOH (Bring Your Own Host) Windows node deployment for Kubernetes/OpenShift clusters with support for AWS, Azure, GCP, vSphere, Nutanix, and bare metal environments.

## Features

- **Multi-Cloud Support**: Deploy Windows nodes on AWS, Azure, GCP, vSphere, Nutanix, or bare metal
- **Zero Hardcoded Values**: All configuration via files, environment variables, or auto-detection
- **Modular Architecture**: Clean separation of concerns with library modules
- **Flexible Configuration**: Multi-source configuration with priority ordering
- **Automated Credential Management**: Seamless integration with cluster secrets
- **Comprehensive Documentation**: Detailed guides for all platforms
- **Fully Parameterized**: Customize instance types, disk sizes, tags, and more

## Prerequisites

- **Kubernetes/OpenShift Cluster** with exported KUBECONFIG
- **Terraform** >= 1.0.0
- **oc** CLI tool
- **jq** for JSON processing
- **base64** command-line tool

## Quick Start

### 1. Install the Tool

```bash
git clone https://github.com/your-org/terraform-windows-provisioner.git
cd terraform-windows-provisioner
chmod +x byoh.sh
```

### 2. Configure Credentials

Create a configuration file with your Windows credentials:

```bash
mkdir -p ~/.config/byoh-provisioner
cp configs/examples/defaults.conf.example ~/.config/byoh-provisioner/config
chmod 600 ~/.config/byoh-provisioner/config
```

Edit `~/.config/byoh-provisioner/config` and set:
- `WINC_ADMIN_PASSWORD`: Your Windows administrator password
- `WINC_SSH_PUBLIC_KEY`: Your SSH public key

### 3. Deploy Windows Nodes

```bash
# Deploy 2 Windows Server 2022 nodes
./byoh.sh apply mywindows 2

# Deploy 4 Windows Server 2019 nodes
./byoh.sh apply mywindows 4 '' 2019
```

### 4. Destroy When Done

```bash
./byoh.sh destroy mywindows 2
```

## Supported Platforms

| Platform | Status | Auto-Credentials | Notes |
|----------|--------|------------------|-------|
| **AWS** | ✅ Supported | Yes | Credentials from cluster secrets |
| **Azure** | ✅ Supported | Yes | Instance names limited to 13 chars |
| **GCP** | ✅ Supported | Yes | Service account integration |
| **vSphere** | ✅ Supported | Yes | Template-based provisioning |
| **Nutanix** | ✅ Supported | Yes | Prism Central integration |
| **Bare Metal** | ✅ Supported | Local AWS config | Uses AWS credentials |

## Usage

### Basic Commands

```bash
# Create instances (default: 2x Windows Server 2022)
./byoh.sh apply [NAME] [NUM_WORKERS] [FOLDER_SUFFIX] [WINDOWS_VERSION]

# Destroy instances
./byoh.sh destroy [NAME] [NUM_WORKERS]

# Show Terraform arguments
./byoh.sh arguments [NAME] [NUM_WORKERS]

# Create/update ConfigMap only
./byoh.sh configmap

# Clean up temporary files
./byoh.sh clean

# Show help
./byoh.sh help
```

### Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `ACTION` | Operation (apply/destroy/arguments/configmap/clean/help) | apply | Yes |
| `NAME` | Base name for instances | byoh-winc | No |
| `NUM_WORKERS` | Number of workers | 2 | No |
| `FOLDER_SUFFIX` | Temporary folder suffix | "" | No |
| `WINDOWS_VERSION` | Windows Server version (2019/2022) | 2022 | No |

### Examples

```bash
# Single Windows 2019 instance
./byoh.sh apply myapp 1 '' 2019

# 4 Windows 2022 instances with custom name
./byoh.sh apply production-win 4

# Multiple deployments with suffixes
./byoh.sh apply test 2 '-env1'
./byoh.sh apply test 2 '-env2'

# Show what would be deployed without creating
./byoh.sh arguments myapp 2
```

## Configuration

### Configuration Priority

Configuration is loaded with the following priority (highest to lowest):

1. **Environment variables** (highest priority)
2. **User config file**: `~/.config/byoh-provisioner/config`
3. **Project config file**: `./configs/defaults.conf`
4. **Built-in defaults** (lowest priority)

### Required Configuration

```bash
# Windows credentials (REQUIRED)
WINC_ADMIN_PASSWORD="YourSecurePassword123!"
WINC_SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC..."
```

### Optional Configuration

See [configs/examples/](configs/examples/) for platform-specific examples:

- `aws.conf.example` - AWS-specific settings
- `azure.conf.example` - Azure-specific settings (including image versions)
- `gcp.conf.example` - GCP-specific settings
- `vsphere.conf.example` - vSphere-specific settings
- `nutanix.conf.example` - Nutanix-specific settings

### Key Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WINDOWS_ADMIN_USERNAME` | Windows administrator username | Platform-specific: Azure=`capi`, Others=`Administrator` |
| `WINDOWS_CONTAINER_LOGS_PORT` | Container logs port | 10250 |
| `AZURE_VM_EXTENSION_HANDLER_VERSION` | Azure VM extension version | 1.9 |
| `AZURE_2019_IMAGE_VERSION` | Azure Win 2019 image version | latest |
| `AZURE_2022_IMAGE_VERSION` | Azure Win 2022 image version | latest |
| `AWS_INSTANCE_TYPE` | AWS instance type | m5a.large |
| `AWS_ROOT_VOLUME_SIZE` | AWS root volume size (GB) | 120 |
| `ENVIRONMENT_TAG` | Environment tag for resources | production |
| `MANAGED_BY_TAG` | Managed-by tag for resources | terraform |

## Platform-Specific Notes

### AWS

- Credentials automatically extracted from cluster secrets
- Supports custom AMI selection
- Configurable instance types and volume sizes

### Azure

- **Instance names limited to 13 characters** (automatically truncated)
- Supports specific image versions or 'latest'
- Resource groups and prefixes from cluster configuration

### GCP

- Service account credentials from cluster secrets
- Zone and region auto-detected
- Supports custom machine types

### vSphere

- Requires pre-configured Windows templates
- vCenter credentials from cluster secrets
- Template names: `Windows-Server-2019-Template`, `Windows-Server-2022-Template`

### Nutanix

- Requires pre-configured Windows images in Prism Central
- Cluster and subnet UUIDs auto-detected
- Image names: `Windows-Server-2019`, `Windows-Server-2022`

### Bare Metal (None)

- Uses AWS credentials from `~/.aws/config` and `~/.aws/credentials`
- Platform detected as "none"
- Provisions using AWS infrastructure

## Architecture

This project uses a modular architecture with separated concerns:

```
terraform-windows-provisioner/
├── byoh.sh                 # Main entry point
├── lib/                    # Library modules
│   ├── config.sh          # Configuration loading
│   ├── credentials.sh     # Credential management
│   ├── platform.sh        # Platform detection & config
│   ├── terraform.sh       # Terraform operations
│   └── validation.sh      # Input validation
├── configs/               # Configuration files
│   ├── defaults.conf      # Default values
│   └── examples/          # Platform-specific examples
└── platforms/             # Platform-specific Terraform
    ├── aws/
    ├── azure/
    ├── gcp/
    ├── vsphere/
    ├── nutanix/
    └── none/
```

## Troubleshooting

### Check Cluster Credentials

```bash
oc get secret -n kube-system
oc get secret -n openshift-machine-api
```

### Verify Cluster Status

```bash
oc get clusterversion
oc get nodes
```

### View Terraform State

```bash
cd /tmp/terraform_byoh/<platform>
terraform show
terraform output
```

### Check ConfigMap

```bash
# Find WMCO namespace
oc get deployment --all-namespaces | grep windows-machine-config-operator

# View ConfigMap
oc get configmap windows-instances -n <wmco-namespace> -o yaml
```

### Enable Debug Logging

```bash
export BYOH_LOG_LEVEL=DEBUG
./byoh.sh apply myapp 2
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on:

- Code of conduct
- Development setup
- Pull request process
- Testing requirements

## Security

For security issues, please see [SECURITY.md](SECURITY.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

## Project Status

Version: 1.0.0

This is a production-ready, vendor-neutral project suitable for upstream use.

## Support

- **Issues**: Report bugs or request features via GitHub Issues
- **Documentation**: See [docs/](docs/) for comprehensive guides
- **Examples**: See [configs/examples/](configs/examples/) for configuration examples

## Acknowledgments

This project is designed to work seamlessly with:
- OpenShift Windows Container Support
- Windows Machine Config Operator (WMCO)
- Kubernetes Windows node support

## Roadmap

- [ ] Additional cloud platform support
- [ ] Enhanced monitoring and metrics
- [ ] Integration tests for all platforms
- [ ] Helm chart for Kubernetes deployment
- [ ] Web UI for configuration

---

**Note**: This is a generic, vendor-neutral project with no hardcoded values. All configuration is customizable via configuration files or environment variables.
