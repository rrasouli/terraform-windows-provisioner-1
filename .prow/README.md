# Prow CI Job Configurations

This directory contains example Prow CI job configurations for the BYOH Provisioner.

## Quick Start for CI Integration

### 1. Build and Publish Container Image

```bash
# Build the image
make build

# Push to quay.io (requires authentication)
make push IMAGE_REGISTRY=quay.io IMAGE_ORG=openshift

# Or push to OpenShift CI registry
make build-ci
```

### 2. Set Up CI Secrets

Create a secret with Windows credentials in your Prow cluster:

```bash
kubectl create secret generic windows-ci-credentials \
  -n ci \
  --from-literal=admin-password='YourSecurePassword123!' \
  --from-file=ssh-public-key=$HOME/.ssh/id_rsa.pub

# Label for CI use
kubectl label secret windows-ci-credentials \
  -n ci \
  ci.openshift.io/secret=true
```

### 3. Add to openshift/release Repository

Copy the example job configuration to the appropriate location in the [openshift/release](https://github.com/openshift/release) repository:

```bash
# For periodic jobs
cp .prow/example-periodic-job.yaml \
  <openshift-release-repo>/ci-operator/jobs/openshift/windows-machine-config-operator/...
```

### 4. Configure ci-operator

Create a ci-operator configuration if needed:

```yaml
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

## Available Example Jobs

### `example-periodic-job.yaml`

Contains three example periodic jobs:

1. **periodic-ci-wmco-aws-byoh-windows2022-e2e**
   - Runs every 24 hours
   - Provisions 2 Windows 2022 nodes on AWS
   - Runs e2e tests
   - Cleans up resources

2. **periodic-ci-wmco-azure-byoh-windows2022-e2e**
   - Runs every 24 hours
   - Provisions 2 Windows 2022 nodes on Azure
   - Runs e2e tests
   - Cleans up resources

3. **periodic-ci-wmco-byoh-upgrade-test**
   - Runs every 48 hours
   - Provisions 4 Windows nodes
   - Deploys workloads
   - Triggers cluster upgrade (N+1)
   - Verifies workloads post-upgrade
   - This addresses **WINC-1473** requirements

## Customizing Jobs

### Changing Instance Count

```yaml
/usr/local/bin/byoh.sh apply test-name 4  # Change from 2 to 4 nodes
```

### Changing Windows Version

```yaml
/usr/local/bin/byoh.sh apply test-name 2 '' 2019  # Use Windows 2019
```

### Platform-Specific Configuration

Use environment variables to customize:

```yaml
env:
- name: AWS_INSTANCE_TYPE
  value: "m5a.xlarge"  # Larger instance
- name: AWS_ROOT_VOLUME_SIZE
  value: "200"  # Larger disk
- name: AZURE_INSTANCE_SIZE
  value: "Standard_D4s_v3"
- name: AZURE_2022_IMAGE_VERSION
  value: "20348.1787.230621"  # Specific version
```

## Job Structure

Each job should follow this pattern:

```bash
#!/bin/bash
set -euo pipefail

# 1. Define cleanup function
cleanup() {
  /usr/local/bin/byoh.sh destroy <name> <count> || true
  # Save artifacts
}
trap cleanup EXIT

# 2. Set credentials and configuration
export WINC_ADMIN_PASSWORD="${WINDOWS_ADMIN_PASSWORD}"
export WINC_SSH_PUBLIC_KEY="${WINDOWS_SSH_PUBLIC_KEY}"

# 3. Provision nodes
/usr/local/bin/byoh.sh apply <name> <count> <suffix> <version>

# 4. Wait for readiness
sleep 120

# 5. Run tests
make test-e2e-byoh

# 6. Cleanup happens automatically via trap
```

## Resource Requirements

Recommended resource limits:

```yaml
resources:
  requests:
    cpu: "1"
    memory: "2Gi"
  limits:
    cpu: "2"
    memory: "4Gi"
```

For upgrade tests or larger deployments, increase:

```yaml
resources:
  requests:
    cpu: "2"
    memory: "4Gi"
  limits:
    cpu: "4"
    memory: "8Gi"
```

## Timeouts

Recommended timeouts:

- **Simple e2e test**: 3-4 hours
- **Upgrade test**: 6 hours
- **Grace period**: 30 minutes (for cleanup)

```yaml
decoration_config:
  timeout: 4h0m
  grace_period: 30m
```

## Artifact Collection

The jobs automatically collect:
- Terraform state files
- Terraform logs
- Cluster version info
- Node information

Artifacts are saved to `/tmp/artifacts` (mapped to `$ARTIFACTS` in Prow).

## Testing Jobs Locally

You can test job logic locally using the container:

```bash
# Build image
make build

# Run with your kubeconfig
podman run -it --rm \
  -v ~/.kube:/root/.kube:ro \
  -e KUBECONFIG=/root/.kube/config \
  -e WINC_ADMIN_PASSWORD='YourPassword' \
  -e WINC_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  quay.io/openshift/byoh-provisioner:latest \
  apply test 1
```

## Integration with WMCO Tests

To integrate with Windows Machine Config Operator tests:

```yaml
- name: test
  image: quay.io/openshift/byoh-provisioner:latest
  command:
  - /bin/bash
  - -c
  - |
    # Provision nodes
    /usr/local/bin/byoh.sh apply wmco-test 2

    # Clone WMCO repo
    git clone https://github.com/openshift/windows-machine-config-operator
    cd windows-machine-config-operator

    # Run WMCO e2e tests
    make test-e2e-byoh

    # Cleanup
    cd ..
    /usr/local/bin/byoh.sh destroy wmco-test 2
```

## Monitoring

Monitor job success/failure rates in Prow:

- **Deck**: https://deck-ci.apps.ci.l2s4.p1.openshiftapps.com/
- **Job History**: https://prow.ci.openshift.org/job-history/...

## Debugging Failed Jobs

1. Check Prow logs in Deck
2. Download artifacts (Terraform state, logs)
3. Check for resource cleanup issues
4. Verify credentials are properly mounted
5. Check timeout settings

## Slack Notifications

Configure in openshift/release:

```yaml
slack_reporter_configs:
  'openshift/windows-machine-config-operator':
  - job_names:
    - periodic-ci-wmco-byoh-upgrade-test
    channel: windows-ci-alerts
    report_template: 'Job *{{.Spec.Job}}* {{.Status.State}}'
```

## Next Steps

1. Review and customize example jobs for your needs
2. Submit PR to openshift/release repository
3. Test with `/pj-rehearse` command
4. Monitor initial runs
5. Adjust timeouts and resource limits as needed

## Support

- **Prow Issues**: `#forum-ocp-testplatform` on Slack
- **BYOH Provisioner**: File issues in this repository
- **WMCO Integration**: `#windows-containers` on Slack

## References

- [Prow Documentation](https://docs.prow.k8s.io/)
- [OpenShift CI Documentation](https://docs.ci.openshift.org/)
- [WINC-1473](https://issues.redhat.com/browse/WINC-1473)
- [Full Prow CI Integration Guide](../docs/PROW_CI_INTEGRATION.md)
