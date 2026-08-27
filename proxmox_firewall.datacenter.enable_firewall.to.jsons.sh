#!/bin/bash

#
# PR-60
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_dc_enable"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"ip:port\" | $(basename "$0") "
  echo "    echo \"ip:port\" | $(basename "$0") --json"
  echo "    echo \"ip:port\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/proxmox_node.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_api_host":"ip:port"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Enable datacenter firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                                $(basename "$0") [-h|--help] "
  echo "  STDIN :: [proxmox_api_host] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [proxmox_api_host] | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# define output type
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

case "${1:-}" in
--json)
  OUTPUT_JSON=true
  ;;
--text)
  OUTPUT_JSON=false
  ;;
"") ;;
*)
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  show_example
  exit 1
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::proxmox_api_host" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
    # exit 0

    # On a refusal the play stops before the task that builds the json payload, so the shared
    # normaliser - which keeps only the key named after the action - prints nothing. The real
    # message is discarded there, upstream of this wrapper : do not look for it here. All this
    # can do is say so, and point at --text which does carry it.
    _dk_rc=0
    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" || _dk_rc=$?

    if [ "$_dk_rc" -ne 0 ]; then
      devkit_utils.text.echo_error.to.text.to.stderr.sh \
        "refused or failed (rc=${_dk_rc}). stdout is empty : the payload is built only on success."
      devkit_utils.text.echo_error.to.text.to.stderr.sh \
        "re-run the same command with --text to read the reason."
      exit "$_dk_rc"
    fi

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
