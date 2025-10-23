# Prow CI Integration Guide

This guide explains how to integrate the BYOH Provisioner into OpenShift Prow CI for automated Windows node testing.

## Overview

The BYOH Provisioner can be run in Prow CI jobs to:
- Automatically provision Windows BYOH nodes during CI runs
- Test Windows node upgrades (N+1 scenarios)
- Validate Windows workloads across different platforms
- Clean up resources after tests complete

## Prerequisites

1. Access to [openshift/release](https://github.com/openshift/release) repository
2. Container image published to OpenShift CI registry
3. Cluster credentials configured as CI secrets
4. Windows credentials configured as CI secrets

## Container Image

### Building the Image

The provisioner includes a `Dockerfile` that creates a container with all dependencies:

```bash
# Build the image
podman build -t quay.io/openshift/byoh-provisioner:latest .

# Or using Docker
docker build -t quay.io/openshift/byoh-provisioner:latest .
```

### Image Contents

The container includes:
- ✅ Terraform (pinned version for reproducibility)
- ✅ `oc` CLI (from OpenShift base image)
- ✅ `jq` for JSON processing
- ✅ BYOH provisioner scripts
- ✅ All platform Terraform configurations

### Publishing to OpenShift CI Registry

Images for Prow CI should be published to the OpenShift CI registry:

```yaml
# In openshift/release repo
# ci-operator/config/openshift/terraform-windows-provisioner/...
build_root:
  image_stream_tag:
    name: release
    namespace: openshift
    tag: golang-1.21

images:
- dockerfile_path: Dockerfile
  to: byoh-provisioner
```

## Prow Job Configuration

### Example Periodic Job

Create a periodic job that provisions Windows nodes and runs tests:

```yaml
# ci-operator/jobs/openshift/windows-machine-config-operator/...
periodics:
- name: periodic-ci-windows-byoh-upgrade-test
  interval: 24h
  cluster: build01
  decorate: true
  decoration_config:
    timeout: 4h
  spec:
    serviceAccountName: ci-operator
    containers:
    - name: test
      image: quay.io/openshift/byoh-provisioner:latest
      command:
      - /bin/bash
      - -c
      - |
        set -euo pipefail

        # Export credentials from CI secrets
        export WINC_ADMIN_PASSWORD="${WINDOWS_ADMIN_PASSWORD}"
        export WINC_SSH_PUBLIC_KEY="${WINDOWS_SSH_PUBLIC_KEY}"

        # Provision 2 Windows nodes
        /usr/local/bin/byoh.sh apply ci-test 2

        # Run your tests here
        # ...

        # Cleanup
        /usr/local/bin/byoh.sh destroy ci-test 2
      env:
      - name: KUBECONFIG
        value: /tmp/kubeconfig
      - name: WINDOWS_ADMIN_PASSWORD
        valueFrom:
          secretKeyRef:
            name: windows-credentials
            key: admin-password
      - name: WINDOWS_SSH_PUBLIC_KEY
        valueFrom:
          secretKeyRef:
            name: windows-credentials
            key: ssh-public-key
      volumeMounts:
      - name: cluster-profile
        mountPath: /tmp/cluster-profile
    volumes:
    - name: cluster-profile
      secret:
        secretName: cluster-profile
```

### Example Presubmit Job

For PR testing in the WMCO repository:

```yaml
presubmits:
  openshift/windows-machine-config-operator:
  - name: pull-ci-wmco-byoh-e2e
    always_run: true
    optional: false
    cluster: build01
    decorate: true
    decoration_config:
      timeout: 3h
    spec:
      serviceAccountName: ci-operator
      containers:
      - name: test
        image: quay.io/openshift/byoh-provisioner:latest
        command:
        - /bin/bash
        - -c
        - |
          # Provision, test, cleanup
          /usr/local/bin/byoh.sh apply pr-${PULL_NUMBER} 2
          make test-e2e-byoh
          /usr/local/bin/byoh.sh destroy pr-${PULL_NUMBER} 2
        env:
        - name: PULL_NUMBER
          value: "$(PULL_NUMBER)"
```

## Configuration for CI

### Using Environment Variables

In CI, configure via environment variables (highest priority):

```bash
# Windows credentials
export WINC_ADMIN_PASSWORD="<from-vault>"
export WINC_SSH_PUBLIC_KEY="<from-vault>"

# Platform-specific settings
export ENVIRONMENT_TAG="ci-prow"
export MANAGED_BY_TAG="prow-ci"

# Azure specific
export AZURE_VM_EXTENSION_HANDLER_VERSION="1.9"
export AZURE_2019_IMAGE_VERSION="latest"
export AZURE_2022_IMAGE_VERSION="latest"
```

### CI Secrets Setup

Create secrets in the Prow CI cluster:

```bash
# Create Windows credentials secret
oc create secret generic windows-credentials \
  -n ci \
  --from-literal=admin-password='YourPassword123!' \
  --from-file=ssh-public-key=~/.ssh/id_rsa.pub

# Label for CI use
oc label secret windows-credentials \
  -n ci \
  ci.openshift.io/secret=true
```

## Platform-Specific CI Jobs

### AWS CI Job Example

```yaml
- name: periodic-ci-wmco-aws-byoh
  interval: 12h
  cluster: build01
  spec:
    containers:
    - name: test
      image: quay.io/openshift/byoh-provisioner:latest
      command:
      - /bin/bash
      - -c
      - |
        export AWS_INSTANCE_TYPE="m5a.xlarge"
        export AWS_ROOT_VOLUME_SIZE="150"
        /usr/local/bin/byoh.sh apply aws-ci 4
        # Run AWS-specific tests
        /usr/local/bin/byoh.sh destroy aws-ci 4
```

### Azure CI Job Example

```yaml
- name: periodic-ci-wmco-azure-byoh
  interval: 12h
  cluster: build01
  spec:
    containers:
    - name: test
      image: quay.io/openshift/byoh-provisioner:latest
      command:
      - /bin/bash
      - -c
      - |
        export AZURE_INSTANCE_SIZE="Standard_D4s_v3"
        export AZURE_2022_IMAGE_VERSION="20348.1787.230621"
        /usr/local/bin/byoh.sh apply azure-ci 4 '' 2022
        # Run Azure-specific tests
        /usr/local/bin/byoh.sh destroy azure-ci 4
```

## Multi-Platform Test Matrix

Create a matrix of jobs testing different configurations:

```yaml
# Test matrix: Platform x Windows Version x Instance Count
periodics:
- name: periodic-ci-wmco-aws-2019-2nodes
  # AWS + Win2019 + 2 nodes

- name: periodic-ci-wmco-aws-2022-4nodes
  # AWS + Win2022 + 4 nodes

- name: periodic-ci-wmco-azure-2019-2nodes
  # Azure + Win2019 + 2 nodes

- name: periodic-ci-wmco-azure-2022-4nodes
  # Azure + Win2022 + 4 nodes
```

## Best Practices for CI

### 1. Resource Cleanup

Always clean up resources, even on failure:

```bash
#!/bin/bash
set -euo pipefail

# Trap to ensure cleanup
cleanup() {
  echo "Cleaning up resources..."
  /usr/local/bin/byoh.sh destroy ci-test 2 || true
}
trap cleanup EXIT

# Provision
/usr/local/bin/byoh.sh apply ci-test 2

# Run tests
make test-e2e
```

### 2. Unique Instance Names

Use unique names to avoid conflicts:

```bash
# Use job ID or timestamp
INSTANCE_NAME="ci-${BUILD_ID}-${RANDOM}"
/usr/local/bin/byoh.sh apply "${INSTANCE_NAME}" 2
```

### 3. Timeout Handling

Set appropriate timeouts:

```yaml
decoration_config:
  timeout: 4h  # Full job timeout
  grace_period: 30m  # Time for cleanup
```

### 4. Logging

Enable verbose logging in CI:

```bash
export BYOH_LOG_LEVEL=DEBUG
/usr/local/bin/byoh.sh apply ci-test 2
```

### 5. Artifacts Collection

Collect Terraform state and logs:

```bash
# Save artifacts
mkdir -p "${ARTIFACTS}"
cp -r /tmp/terraform_byoh/* "${ARTIFACTS}/" || true
```

## Upgrade Testing Workflow

Example workflow for N+1 upgrade testing (WINC-1473 use case):

```bash
#!/bin/bash
set -euo pipefail

# 1. Provision Windows nodes on current version
/usr/local/bin/byoh.sh apply upgrade-test 2

# 2. Deploy workloads
oc apply -f test-workloads.yaml

# 3. Trigger cluster upgrade
# (your upgrade logic here)

# 4. Wait for upgrade to complete
oc wait --for=condition=Upgraded clusterversion/version --timeout=60m

# 5. Verify Windows nodes and workloads
make test-e2e-upgrade

# 6. Cleanup
/usr/local/bin/byoh.sh destroy upgrade-test 2
```

## Monitoring and Alerting

### Prometheus Metrics

Consider adding metrics for CI monitoring:

```yaml
# Number of provisioned nodes
byoh_provisioner_nodes_total{platform="aws",status="success"}

# Provisioning duration
byoh_provisioner_duration_seconds{platform="azure",operation="apply"}

# Failure rate
byoh_provisioner_failures_total{platform="gcp",reason="terraform_error"}
```

### Slack Notifications

Configure Prow to send notifications on failures:

```yaml
slack_reporter_configs:
  'openshift/windows-machine-config-operator':
  - job_names:
    - periodic-ci-wmco-byoh-upgrade-test
    channel: windows-ci-alerts
    report_template: 'Job *{{.Spec.Job}}* failed'
```

## Integration with ci-operator

For full integration with ci-operator:

```yaml
# ci-operator/config/...
tests:
- as: e2e-byoh
  cluster_claim:
    architecture: amd64
    cloud: aws
    owner: openshift-ci
    product: ocp
    timeout: 4h
    version: "4.17"
  steps:
    test:
    - as: provision-and-test
      from: byoh-provisioner
      commands: |
        export WINC_ADMIN_PASSWORD="${WINDOWS_ADMIN_PASSWORD}"
        export WINC_SSH_PUBLIC_KEY="${WINDOWS_SSH_PUBLIC_KEY}"

        byoh.sh apply ci-test 2
        make test-e2e-byoh
        byoh.sh destroy ci-test 2
      credentials:
      - mount_path: /tmp/secrets
        name: windows-credentials
        namespace: test-credentials
```

## Troubleshooting

### Common Issues

1. **Terraform state conflicts**: Use unique temp directories
2. **Credential errors**: Verify secrets are properly mounted
3. **Timeout errors**: Increase job timeout or reduce node count
4. **Network issues**: Check cluster network policies

### Debug Mode

Run in debug mode to troubleshoot:

```bash
export BYOH_LOG_LEVEL=DEBUG
export TF_LOG=DEBUG
/usr/local/bin/byoh.sh apply ci-test 2
```

## Next Steps

1. Build and publish the container image
2. Create Prow job definitions in openshift/release
3. Configure CI secrets
4. Test with a simple periodic job
5. Expand to full test matrix

## References

- [OpenShift Release Repository](https://github.com/openshift/release)
- [Prow Documentation](https://docs.prow.k8s.io/)
- [ci-operator Documentation](https://docs.ci.openshift.org/docs/architecture/ci-operator/)
- [WINC-1473](https://issues.redhat.com/browse/WINC-1473) - Original epic

## Support

For issues with Prow integration:
- OpenShift CI: `#forum-ocp-testplatform` on Slack
- WMCO Team: `#windows-containers` on Slack
