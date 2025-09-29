
# 📑 Table of Contents
- [Project Overview](#-project-overview)
- [Repository Content](#-repository-content)
- [Contributing](#-contributing) <!-- optionnel -->
- [License](#-license)<!-- optionnel -->

---

# Project Overview

**RANGE42** is a modular cyber range platform designed for real-world readiness.
We build, deploy, and document offensive, defensive, and hybrid cyber training environments using reproducible, infrastructure-as-code methodologies.

## What we buildu

- Proxmox-based cyber ranges with dynamic catalog 
- Ansible roles for automated deployments (Wazuh, Kong, Docker, etc.)
- Private APIs for range orchestration and telemetry
- Developer and testing toolkits and JSON transformers for automation pipelines
- ...

## Repository Overview

- **RANGE42 deployer UI** : A web interface to visually design infrastructure schemas and trigger deployments.
- **RANGE42 deployer backend API** : Orchestrates deployments by executing playbooks and bundles from the catalog.
- **RANGE42 catalog** : A collection of Ansible roles and Docker/Docker Compose stacks, forming deployable bundles.
- **RANGE42 playbooks** : Centralized playbooks that can be invoked by the backend or CLI.
- **RANGE42 proxmox role** : An Ansible role for controlling Proxmox nodes via the Proxmox API.
- **RANGE42 devkit** : Helper scripts for testing, debugging, and development workflows.
- **RANGE42 kong API gateway** : A network service in front of the backend API, handling authentication, ACLs, and access control policies.
- **RANGE42 swagger API spec** : OpenAPI/Swagger JSON definition of the backend API.


### Putting it all together

These repositories provide a modular and extensible platform to design, manage and deploy infrastructures automatically  either from the UI (coming soon) or from the CLI through the playbooks repository.

---

# Repository Content

This repository uses a strict naming convention for all scripts. Each filename follow the structure :


<**CONNECTOR/MODULE**>(.<**DATA_INPUT**>).<**VERB/ACTION**>(.to.<***DATA_OUTPUT**>).EXTENSION



1. **CONNECTOR/MODULE**: top-level namespace (e.g. `devkit_ansible`, `proxmox_vm`, `proxmox_netowork`).
2. **DATA INPUT** (optional): parameter **required** via STDIN or argument (e.g. `vm_id`, `node_name`, `storage_name`).
3. **VERB**: snake_case command describing the operation (e.g. `get_config`, `list_interfaces`).
4. **DATA OUTPUT FORMAT** : `.to.<format>` possible output (`jsons`, `text`, `file`, `stderr`, etc.).
5. **Extensions**: can be .sh|.js|.py - what you want (until we output to stderr error and stdout the "to" format.)



## Additionnal details on structure : 

- **CONNECTOR**: lowercase, alphanumeric and underscores, e.g. `proxmox_vm`, `devkit_transform.jsons`.
- **DATA INPUT**: lowercase, alphanumeric and underscores, e.g. `proxmox_vm`,  (e.g. `vm_id`).
- **VERB**: lowercase letters, digits, underscores, e.g. `get_config_cpu`.
- **DATA OUTPUT**: chained `to.<format>` segments lowercase letters, digits, underscores, e.g. `to.jsons` or `to.text`


### Guidelines

- Use **dots** to separate segments: CONNECTOR, DATA_INTPUT, VERB, DATA_OUTPUT
- Use **snake_case** 
- Chain multiple `.to.<format>` segments only when needed.


Following this convention makes scripts self-documented, easy to locate, and explicit about required input and output format.

I suggest you to add this alias in your shell to ls grep in dir tree : 

```

alias llg="ls -lah | grep -i $1 " 

```

And also : 

```
alias ls='LC_COLLATE=C ls --color -h --group-directories-first'
alias ll='LC_COLLATE=C ls -lah '

```

### Examples 

`proxmox_vm.vm_id.get_config.to.jsons.sh`
- CONNECTOR: `proxmox_vm`  
- DATA_INPUT: `vm_id`  
- VERB: `get_config`  
- DATA_OUTPUT: `to.jsons`

`proxmox_network.node_name.list_node_sdn_zones.to.jsons.sh`
- CONNECTOR: `proxmox_network`  
- DATA_INPUT: `node_name`  
- VERB: `list_node_sdn_zones`  
- DATA_OUTPUT: `to.jsons`

`devkit_utils.text.echo_error.to.text.to.stderr.sh`
- CONNECTOR: `devkit_utils.text`  
- VERB: `echo_error`  
- DATA_OUTPUT: `to.text`, then `to.stderr`



## Contributing

To be defined.


## License

To be defined.



