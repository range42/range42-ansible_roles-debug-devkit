# range42-ansible_roles-debug-devkit

Helper scripts for testing, debugging, and development workflows on
[range42](https://github.com/range42/range42) cyber ranges.
Interacts with Proxmox API, Ansible vault, and VM management from the command line.

---

## Getting Started

Activate your workspace, then use tab completion to discover and run scripts:

```bash
range42-context use <codename> <scenario>

proxmox_vm.<Tab><Tab>          # list all VM commands
proxmox_firewall.<Tab><Tab>    # list all firewall commands
devkit_ansible.<Tab><Tab>      # list all ansible helpers
devkit_transform.<Tab><Tab>    # list all JSON transformers
```

All environment variables (`RANGE42_VAULT_PASSWORD_FILE`, inventory paths, etc.)
are set automatically — scripts just work.

### Prerequisites

These are already installed on the deployer-cli by the range42 bootstrap:
- Ansible
- `jq`, `curl`
- Proxmox API access (configured via `range42-context use`)

---

## Output Format

Scripts output **JSON lines** (`jsons`) by default — one JSON object per line,
pipeable to `jq` or other scripts.

Add `--text` to see raw Ansible output instead:

```bash
# JSON output (default) — one JSON object per line
proxmox_vm.list.to.jsons.sh
{"vmid": 100, "name": "r42.mon-wazuh-01", "status": "running", ...}
{"vmid": 101, "name": "r42.builder-api-01", "status": "stopped", ...}

# Raw Ansible output
proxmox_vm.list.to.jsons.sh --text
```

### Piping examples

```bash
# List all VMs, show names only
proxmox_vm.list.to.jsons.sh | jq '.name'

# Get CPU config for VM 100
proxmox_vm.vm_id.get_config_cpu.to.jsons.sh 100

# Stop a specific VM
proxmox_vm.vm_id.stop.to.jsons.sh 100

# Delete a specific VM
proxmox_vm.vm_id.delete.to.jsons.sh 100

# Chain: list all VMs → force stop → delete (full cleanup)
proxmox_vm.list.to.jsons.sh | jq -c | proxmox_vm.vm_id.stop_force.to.jsons.sh
proxmox_vm.list.to.jsons.sh | jq -c | proxmox_vm.vm_id.delete.to.jsons.sh

# Filter: stop only admin VMs (skip templates and groups)
proxmox_vm.list.to.jsons.sh \
  | grep -vi template | grep -vi group \
  | grep -iE "(admin-)|(testing-)" \
  | jq -c | proxmox_vm.vm_id.stop_force.to.jsons.sh
```

### STDIN piping

Scripts accept JSON lines on STDIN via `| jq -c |`. The JSON must contain
a `vmid` field — each line triggers the action on that VM.
This is what makes chaining possible: list → filter → act.

Use `jq -c` to ensure one compact JSON object per line before piping.
Use `grep` between pipes to filter by VM name, type, or status.

---

## Naming Convention

Each filename follows the structure:

```
<CONNECTOR>.<DATA_INPUT>.<VERB>.to.<DATA_OUTPUT>.sh
```

| Segment | Description | Example |
|---------|-------------|---------|
| **CONNECTOR** | Top-level namespace | `proxmox_vm`, `devkit_ansible` |
| **DATA_INPUT** | Required parameter (optional) | `vm_id`, `node_name`, `storage_name` |
| **VERB** | Operation to perform | `get_config`, `list_interfaces` |
| **DATA_OUTPUT** | Output format | `to.jsons`, `to.text`, `to.stderr` |

### Conventions

- Use **dots** to separate segments
- Use **snake_case** within segments
- Chain multiple `.to.<format>` segments when needed (e.g. `.to.text.to.stderr`)
- `jsons` = JSON lines (one JSON object per line, not a JSON array)

### Examples

| Script | What it does |
|--------|-------------|
| `proxmox_vm.vm_id.get_config.to.jsons.sh` | Get VM config as JSON |
| `proxmox_vm.list.to.jsons.sh` | List all VMs |
| `proxmox_vm.vm_id.start.to.jsons.sh` | Start a VM |
| `proxmox_network.node_name.list_interfaces_node.to.jsons.sh` | List node network interfaces |
| `proxmox_firewall.vm_id.enable_firewall.to.jsons.sh` | Enable firewall on a VM |
| `devkit_ansible.get_proxmox_node.to.jsons.sh` | Get Proxmox node info via Ansible |
| `devkit_utils.text.echo_error.to.text.to.stderr.sh` | Print error message to stderr |

---

## Repository Structure

```text
├── proxmox_vm.*                  # VM lifecycle (create, clone, start, stop, delete, pause, resume)
├── proxmox_lxc.*                 # LXC container lifecycle
├── proxmox_network.*             # Network interfaces and SDN
├── proxmox_firewall.*            # Firewall rules, aliases, enable/disable
├── proxmox_storage.*             # Storage, ISOs, cloud-init images
├── proxmox_template.*            # Template conversion, cloud-init variables
├── proxmox_snapshot_vm.*         # VM snapshots (create, delete, list, revert)
├── proxmox_snapshot_lxc.*        # LXC snapshots
├── proxmox_cluster.*             # Cluster-level operations (tags)
├── devkit_ansible.*              # Ansible helpers (inventory, proxmox node)
├── devkit_transform.*            # JSON transformers (filter, append, remove keys)
├── devkit_utils.*                # Text utilities (echo_error, echo_warning, etc.)
├── proxmox__inc.*                # Internal shared includes (sourced by other scripts, not called directly)
│
├── profiles/                     # JSON profiles for VM/LXC creation (passed to create/clone scripts)
├── callback_plugins/             # Ansible callback plugins (no_skipped output)
├── _tests/                       # Test scripts
├── ansible.cfg                   # Devkit-specific ansible config
└── secrets/                      # Symlink → workspace secrets (gitignored)
```

## Script Categories

### VM management (`proxmox_vm.*`)
Full lifecycle: list, create, clone, start, stop, pause, resume, delete.
Plus: get config (CPU, RAM, CDROM), usage stats, bulk operations (start/stop/pause all).

### Firewall (`proxmox_firewall.*`)
Per-VM, per-node, and datacenter-level firewall management.
Rules, aliases, enable/disable at each level.

### Storage & Templates (`proxmox_storage.*`, `proxmox_template.*`)
List storage, ISOs, templates. Download ISOs, import cloud-init images, convert to template.

### Ansible helpers (`devkit_ansible.*`)
- `get_proxmox_node.to.jsons.sh` — Query Proxmox node info via Ansible
- `show_ansible_inventory.to.text.sh` — Display current inventory

### Snapshots (`proxmox_snapshot_vm.*`, `proxmox_snapshot_lxc.*`)
Create, delete, list, and revert snapshots for both VMs and LXC containers.
Useful for lab reset workflows (snapshot before exercise, revert after).

### JSON transformers (`devkit_transform.*`)
Pipeline-friendly tools to filter, append, remove, or select fields in JSON streams.
Designed to chain with `|` between devkit commands.

---

## Contributing

GPL-3.0 license
