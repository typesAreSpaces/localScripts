#!/bin/bash
# Choose a prompt by DESC, collect positional arguments, and run it.
# Override PROMPTS_DIR to use a different collection of prompt scripts.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
prompts_dir=${PROMPTS_DIR:-"$script_dir/prompts"}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    printf 'Usage: %s\n\nChoose a prompt by number, then enter its arguments when asked.\nEnter q at the menu to quit. Arguments are entered literally, one per line.\nPROMPTS_DIR overrides the default prompts directory.\n' "${0##*/}"
    exit 0
fi

if [[ ! -d $prompts_dir ]]; then
    printf 'Prompt directory not found: %s\n' "$prompts_dir" >&2
    exit 1
fi

shopt -s nullglob
scripts=("$prompts_dir"/*.sh)
if (( ${#scripts[@]} == 0 )); then
    printf 'No .sh scripts found in %s\n' "$prompts_dir" >&2
    exit 1
fi

# Read literal, single-line DESC assignments without sourcing the scripts.
# Sourcing them here would also run their clipboard commands.
descriptions=()
for script in "${scripts[@]}"; do
    description=$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?DESC[[:space:]]*=[[:space:]]*(.*)$/\2/p' "$script" | head -n 1)
    case "$description" in
        \"*\") description=${description#\"}; description=${description%\"} ;;
        \'*\') description=${description#\'}; description=${description%\'} ;;
    esac
    descriptions+=("${description:-${script##*/}}")
done

printf '\nAvailable prompts\n\n' >&2
for (( i=0; i<${#scripts[@]}; i++ )); do
    printf '  %d) %s\n' "$((i + 1))" "${descriptions[i]}" >&2
done
printf '\n  q) Quit\n\n' >&2

while true; do
    printf 'Choose a prompt [1-%d]: ' "${#scripts[@]}" >&2
    if ! IFS= read -r choice; then
        printf '\n' >&2
        exit 0
    fi
    case "$choice" in
        q|Q|quit|exit) exit 0 ;;
    esac
    # Compare strings against the menu numbers to avoid arithmetic on user input.
    selected=-1
    for (( i=0; i<${#scripts[@]}; i++ )); do
        if [[ $choice == "$((i + 1))" ]]; then
            selected=$i
            break
        fi
    done
    if (( selected >= 0 )); then
        break
    fi
    printf 'Please enter a listed number or q.\n' >&2
done

script=${scripts[selected]}
# Detect $1 ... $9 and ${1}, ${10}, ${1:-default}, etc. This is a
# convenience scanner, not a shell parser: dynamically accessed arguments
# ($@, $*, eval, or shift) cannot be inferred. Offer extra arguments below.
argument_pattern='\$\{([1-9][0-9]*)([^0-9]|$)|\$([1-9])'
argument_count=0
while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    while [[ $line =~ $argument_pattern ]]; do
        reference=${BASH_REMATCH[0]}
        number=${BASH_REMATCH[1]:-${BASH_REMATCH[3]}}
        if (( number > argument_count )); then
            argument_count=$number
        fi
        line=${line#*"$reference"}
    done
done < "$script"

printf '\n%s\n' "${descriptions[selected]}" >&2
arguments=()
for (( i=1; i<=argument_count; i++ )); do
    printf 'Argument %d (literal value; blank for empty/default): ' "$i" >&2
    if ! IFS= read -r argument; then
        printf '\nCancelled: no input for argument %d.\n' "$i" >&2
        exit 1
    fi
    arguments+=("$argument")
done

# Scripts using $@ or other dynamic argument handling can still receive input.
if (( argument_count == 0 )) && grep -Eq '\$[@*]|\$\{[@*]' "$script"; then
    printf 'This script accepts an argument list. Enter one argument per line;\nfinish with a blank line.\n' >&2
    while true; do
        printf 'Argument %d: ' "$((${#arguments[@]} + 1))" >&2
        if ! IFS= read -r argument; then
            printf '\nCancelled.\n' >&2
            exit 1
        fi
        [[ -z $argument ]] && break
        arguments+=("$argument")
    done
fi

# Some existing prompt scripts have no shebang, so run them explicitly in Bash.
if bash "$script" ${arguments[@]+"${arguments[@]}"}; then
    printf 'Done: %s\n' "${descriptions[selected]}" >&2
else
    status=$?
    printf 'Prompt failed (exit %d): %s\n' "$status" "${script##*/}" >&2
    exit "$status"
fi
