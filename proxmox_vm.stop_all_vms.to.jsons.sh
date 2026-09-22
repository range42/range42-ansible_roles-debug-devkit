#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-31
#
# proxmox_vm.stop_all_vms.to.jsons.sh
#
# Stop (acpi shutdown) every RUNNING vm of the node, one after the other, EXCEPT the ids named
# by --keep. The option is MANDATORY : the deployer-cli that runs this command is itself a vm of
# this Proxmox, and a plain "stop everything" would stop it too, cut ansible and lose every way
# back. Its vm_id is declared nowhere and differs from one Proxmox to the next, so nobody can
# guess it : the operator names it, and to name it right the refusal prints the running vms with
# their ids and names.
#
#   without --keep                     refuse, rc 1, print the running vms (id, name), stop nothing
#   --keep A,B                         A and B are removed from the list BEFORE the loop, reported as kept
#   none of the kept ids is running    refuse, rc 1 : the deployer-cli runs this command, so its id
#                                      is in the running list, a typo would let it be stopped
#   a kept id that is not running      said on stderr, the run goes on (the others still protect)
#   [VM_NAME_FILTER]                   as before, a case insensitive filter on vm_name, applied to the
#                                      running list ; the kept ids are checked against the whole node
#
# Each stop goes through proxmox_vm.vm_id.stop.to.jsons.sh, the unitary devkit : the api fast path
# when the api answers, the ansible play otherwise or with RANGE42_PROXMOX_API_FORCE=off. Its
# lines pass through to stdout ; the kept vms and the summary go to stderr.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_stop"
DEFAULT_OUTPUT_JSON=true
ARG_VM_NAME_FILTER=""
KEEP_ARG=""
ACPI_SETTLE_SECONDS=7 # a pause between two acpi shutdowns, as before

_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$@" ; }
_error() { devkit_utils.text.echo_error.to.text.to.stderr.sh "$@" ; }
_warn()  { devkit_utils.text.echo_warning.to.text.to.stderr.sh "$@" ; }
_pass()  { devkit_utils.text.echo_pass.to.text.to.stderr.sh "$@" ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {

  echo "  $(basename "$0") --keep DEPLOYER_VM_ID"
  echo "  $(basename "$0") --keep DEPLOYER_VM_ID,OTHER_VM_ID --json"
  echo "  $(basename "$0") vm_name_team --keep DEPLOYER_VM_ID"
  echo "  $(basename "$0") --keep DEPLOYER_VM_ID --text"
  echo
  echo "  :: FIND THE vm_id OF THE deployer-cli, THE VM THAT RUNS THIS COMMAND"
  echo
  echo "    $(basename "$0")                     - refuses, and prints the running vms with their names"
  echo "    proxmox_vm.list_running.to.jsons.sh | jq -r '[.vm_id, .vm_name] | @tsv'"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Stop all RUNNING vms but the kept ones - Execute the specified $ACTION action for each (api when reachable, ansible otherwise) "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") --keep <vm_id>[,<vm_id>...]           - MANDATORY : the vms to keep running, the deployer-cli first "
  echo "  $(basename "$0") [VM_NAME_FILTER] --keep <ids>         - case insensitive filter on vm_name, the kept ids still apply "
  echo "  $(basename "$0") --keep <ids> [--json]                 - force output as json *default "
  echo "  $(basename "$0") --keep <ids> [--text]                 - force output as text "
  echo
  echo "  Without --keep the command refuses to run and prints the running vms (id, name) : the"
  echo "  deployer-cli is one of them, stopping it cuts ansible and every way back."
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# arguments : output type, the mandatory --keep, an optional vm_name filter
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    OUTPUT_JSON=true
    shift
    ;;
  --text)
    OUTPUT_JSON=false
    shift
    ;;
  --keep)
    if [[ $# -lt 2 || -z "$2" ]]; then
      _error "--keep needs a value : --keep <vm_id>[,<vm_id>...]"
      show_example
      exit 1
    fi
    KEEP_ARG="${KEEP_ARG:+${KEEP_ARG},}$2"
    shift 2
    ;;
  -*)
    _error "unknown option : $1"
    show_example
    exit 1
    ;;
  *)
    if [[ -z "$ARG_VM_NAME_FILTER" ]]; then
      ARG_VM_NAME_FILTER="$1"
      shift
    else
      _error "wrong number of arguments."
      show_example
      exit 1
    fi
    ;;
  esac
done

KEEP_IDS=()
if [[ -n "$KEEP_ARG" ]]; then
  if [[ ! "$KEEP_ARG" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    _error "--keep expects vm_ids separated by commas, got : ${KEEP_ARG}"
    show_example
    exit 1
  fi
  IFS=',' read -r -a KEEP_IDS <<< "$KEEP_ARG"
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# the running vms of the node, read ONCE : the refusal shows them, the guard checks them,
# the loop walks them. vm_id is a number on the api path and a string on the ansible path.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

RUNNING_JSONL="$(proxmox_vm.list_running.to.jsons.sh --json | jq -c '{vm_id: (.vm_id | tostring), vm_name: (.vm_name // "?"), vm_status: (.vm_status // "?")}')" || {
  _error "could not read the running vms - the run stops here, nothing was stopped"
  exit 1
}

_print_running() {
  if [[ -z "$RUNNING_JSONL" ]]; then
    echo "  (no running vm on this node)" >&2
  else
    printf '%s\n' "$RUNNING_JSONL" | devkit_utils.jsons.render.to.table.sh vm_id:VM_ID vm_name:VM_NAME vm_status:STATUS >&2
  fi
}

if [[ ${#KEEP_IDS[@]} -eq 0 ]]; then
  _error "refuses to run without --keep : the deployer-cli that runs this command is a vm of this Proxmox, stopping it cuts ansible and every way back. Name its vm_id, and any other vm to keep : --keep <vm_id>[,<vm_id>...]"
  _trace "the running vms, to pick the ids to keep :"
  _print_running
  exit 1
fi

if [[ -z "$RUNNING_JSONL" ]]; then
  _trace "no running vm on this node - nothing to stop"
  exit 0
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# the guard : at least one kept id must be running. The deployer-cli runs this command, so its
# id is in the running list ; a list where none of the kept ids runs is a typo, and the typo
# would let the deployer-cli be stopped.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

RUNNING_IDS="$(printf '%s\n' "$RUNNING_JSONL" | jq -r '.vm_id')"
KEPT_RUNNING=()
KEPT_ABSENT=()
for id in "${KEEP_IDS[@]}"; do
  if grep -qx -- "$id" <<< "$RUNNING_IDS"; then
    KEPT_RUNNING+=("$id")
  else
    KEPT_ABSENT+=("$id")
  fi
done

if [[ ${#KEPT_RUNNING[@]} -eq 0 ]]; then
  _error "none of the ids to keep (${KEEP_ARG}) is running : the deployer-cli runs this command, so its vm_id is in the running list - check the ids, nothing was stopped"
  _trace "the running vms :"
  _print_running
  exit 1
fi

for id in ${KEPT_ABSENT[@]+"${KEPT_ABSENT[@]}"}; do # the array may be empty
  _warn "kept id ${id} is not running on this node - nothing to protect there, the run goes on"
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# the targets : the running vms, through the vm_name filter when given, minus the kept ids
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -n "$ARG_VM_NAME_FILTER" ]]; then
  SELECTED_JSONL="$(printf '%s\n' "$RUNNING_JSONL" | devkit_transform.jsons.key_field_greper.to.jsons.sh vm_name "$ARG_VM_NAME_FILTER")" || {
    _error "the vm_name filter could not be applied : ${ARG_VM_NAME_FILTER}"
    exit 1
  }
else
  SELECTED_JSONL="$RUNNING_JSONL"
fi

KEEP_JSON="$(printf '%s\n' "${KEEP_IDS[@]}" | jq -R . | jq -sc .)"
TARGETS_JSONL="$(printf '%s\n' "$SELECTED_JSONL" | jq -c --argjson keep "$KEEP_JSON" 'select(.vm_id as $i | any($keep[]; . == $i) | not)')"
KEPT_JSONL="$(printf '%s\n' "$RUNNING_JSONL" | jq -c --argjson keep "$KEEP_JSON" 'select(.vm_id as $i | any($keep[]; . == $i))')"

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  _pass "kept :: $(jq -r '.vm_id' <<< "$line") ($(jq -r '.vm_name' <<< "$line"))"
done <<< "$KEPT_JSONL"

N_RUNNING=$(printf '%s\n' "$RUNNING_JSONL" | grep -c . || true)
N_SELECTED=$(printf '%s\n' "$SELECTED_JSONL" | grep -c . || true)
N_TARGETS=$(printf '%s\n' "$TARGETS_JSONL" | grep -c . || true)

if [[ -n "$ARG_VM_NAME_FILTER" ]]; then
  _trace "filter '${ARG_VM_NAME_FILTER}' : ${N_SELECTED} of ${N_RUNNING} running vm(s) selected, the others are left as they are"
fi

if [[ "$N_TARGETS" -eq 0 ]]; then
  _trace "nothing to stop : every running vm is kept or outside the filter"
  exit 0
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# the loop : one unitary stop per target, its lines pass through ; the first failure ends the run
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

N_STOPPED=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  VM_ID="$(jq -r '.vm_id' <<< "$line")"
  VM_NAME="$(jq -r '.vm_name' <<< "$line")"

  [[ "$N_STOPPED" -eq 0 ]] || sleep "$ACPI_SETTLE_SECONDS"

  _trace "stopping :: ${VM_ID} (${VM_NAME})"

  if [[ "$OUTPUT_JSON" == true ]]; then
    printf '%s\n' "$VM_ID" | proxmox_vm.vm_id.stop.to.jsons.sh --json || {
      _error "vm_stop of ${VM_ID} (${VM_NAME}) failed - the run stops here, ${N_STOPPED} vm(s) stopped before it"
      exit 1
    }
  else
    printf '%s\n' "$VM_ID" | proxmox_vm.vm_id.stop.to.jsons.sh --text || {
      _error "vm_stop of ${VM_ID} (${VM_NAME}) failed - the run stops here, ${N_STOPPED} vm(s) stopped before it"
      exit 1
    }
  fi

  N_STOPPED=$((N_STOPPED + 1))
done <<< "$TARGETS_JSONL"

_pass "stopped ${N_STOPPED} vm(s), kept ${#KEPT_RUNNING[@]} (${KEEP_ARG})"
