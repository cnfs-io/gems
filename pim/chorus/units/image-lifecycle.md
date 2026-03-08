---
objective: "Evolve PIM's image management from a flat build-artifact registry into a lifecycle-aware image catalog."
status: complete
---

# Image Lifecycle — Inventory, Provisioning Labels, and Deployment

## Objective

Evolve PIM's image management from a flat build-artifact registry into a lifecycle-aware image catalog with lineage tracking, provisioning metadata, configurable labeling policies, and deployment to real targets (Proxmox, AWS).

## Background

### Current state

The `Pim::Registry` is a single YAML file (`~/.local/share/pim/images/registry.yml`) keyed by `profile-arch`. It tracks path, ISO, cache key, build time, and has stub support for deployment history. There's no concept of image variants, provisioning metadata, or lifecycle status.

The vm-runner tier added `pim vm run --run script.sh` which creates CoW overlays and provisions them, but the provisioned overlays are ephemeral — they aren't tracked in the registry.

### Multi-layer context

PIM projects operate at different infrastructure layers:

| Layer | Role | Builds | Deploys to |
|-------|------|--------|-----------|
| L1 (colo provider) | Bare metal OS images | Proxmox hosts, TrueNAS, switches | PXE/USB/IPMI |
| L2 (cloud provider) | VM templates for the cluster | Tenant base images | Proxmox template storage |
| L3 (cloud consumer) | Application workload VMs | App-specific images | Proxmox (via PCS), AWS, GCP, DO |

Each layer has its own PIM project. An L3 consumer might target both a PCS-managed Proxmox cluster and AWS. The image lifecycle needs to work cleanly at all layers.

### Design principles

1. **Images are first-class objects** — not just side effects of builds
2. **Lineage is tracked** — every image knows its parent (golden build or another image)
3. **Provisioning metadata is attached** — what script ran, what label, when
4. **Labeling policy is configurable per project** — some projects require labels on provision, others auto-generate
5. **Publish flattens overlays** — configurable: require explicit publish or auto-flatten on deploy
6. **Deploy is target-polymorphic** — same command, different targets (Proxmox, AWS, local)

## Architecture

### Image as a model

Replace the flat registry hash with an `Image` model backed by the existing registry YAML (not FlatRecord — images are machine-local state, not project data). Each image has:

```yaml
# ~/.local/share/pim/images/registry.yml
version: 2
images:
  default-arm64:
    id: default-arm64
    profile: default
    arch: arm64
    path: /home/user/.local/share/pim/images/default-arm64.qcow2
    iso: debian-13-arm64
    status: verified          # built → verified → provisioned → published
    build_time: "2026-02-25T10:00:00Z"
    cache_key: abc123
    size: 1234567890
    parent_id: null           # golden images have no parent
    label: null               # set by provisioning
    provisioned_with: null    # script path
    provisioned_at: null
    published_at: null
    deployments: []

  default-arm64-k8s-node:
    id: default-arm64-k8s-node
    profile: default
    arch: arm64
    path: /home/user/.local/share/pim/vms/default-arm64-k8s-node.qcow2
    status: provisioned
    build_time: "2026-02-25T10:00:00Z"
    parent_id: default-arm64
    label: k8s-node
    provisioned_with: resources/scripts/setup-k8s.sh
    provisioned_at: "2026-02-25T11:00:00Z"
    published_at: null
    deployments: []
```

### Config DSL additions

```ruby
Pim.configure do |config|
  # Image lifecycle settings
  config.images do |img|
    img.require_label = true          # --run requires --label (default: true)
    img.auto_publish = false          # auto-flatten on deploy (default: false)
  end
end
```

When `require_label` is false, PIM auto-generates labels from the script name (e.g., `setup-k8s.sh` → `setup-k8s`).

When `auto_publish` is true, `pim image deploy` auto-flattens overlays instead of requiring an explicit `pim image publish` step.

### Command API

```
pim image list                        # All tracked images with status, label, lineage
pim image show <id>                   # Full detail including lineage and deployment history
pim image publish <id>                # Flatten overlay → standalone qcow2, status → published
pim image deploy <id> <target>        # Push image to a target
pim image delete <id>                 # Remove from registry + disk
```

### How provisioning integrates

When `pim vm run --run script.sh --label k8s-node` completes successfully:

1. The provisioned overlay is registered as a new image in the registry
2. `parent_id` points to the golden image
3. `status` is set to `provisioned`
4. `label` and `provisioned_with` are recorded
5. The image appears in `pim image list`

When `--label` is omitted and `require_label` is false:
- Label is derived from script filename (strip extension, replace underscores)

When `--label` is omitted and `require_label` is true:
- Error: `"--run requires --label (configure images.require_label = false to auto-generate)"`

## Plan Table

| # | Plan | Description | Depends on |
|---|------|-------------|------------|
| 01 | image-model-and-registry | Evolve Registry to v2 schema, add Image value object, config DSL | — |
| 02 | image-commands | `pim image list/show/delete` commands and view | 01 |
| 03 | provisioning-integration | Wire `vm run --run --label` into image registry, labeling policy | 01, 02 |
| 04 | image-publish | `pim image publish` — flatten overlay to standalone qcow2 | 01, 02 |
| 05 | deploy-proxmox | `pim image deploy <id> <target>` — ProxmoxTarget implementation | 04 |
| 06 | deploy-aws | `pim image deploy <id> <target>` — AwsTarget implementation | 04 |

## Completion Criteria

- [ ] `pim image list` shows all images with status, label, parent lineage
- [ ] `pim image show <id>` displays full image detail including deployments
- [ ] `pim image delete <id>` removes image from registry and disk
- [ ] `pim vm run --run script.sh --label name` registers provisioned image in registry
- [ ] Labeling policy respects `config.images.require_label` setting
- [ ] `pim image publish <id>` flattens CoW overlay to standalone qcow2
- [ ] `pim image deploy <id> proxmox-target` uploads to Proxmox as VM template
- [ ] `pim image deploy <id> aws-target` creates AMI from image
- [ ] Registry migration from v1 → v2 is seamless
- [ ] Deployment history tracked per image

