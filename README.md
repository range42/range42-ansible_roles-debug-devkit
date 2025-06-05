

## Overview

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

```json

alias llg="ls -lah | grep -i $1 " 

```

and also : 

```json 

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
