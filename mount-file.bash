#!/usr/bin/env bash

set -o nounset            # Fail on use of unset variable.
set -o errexit            # Exit on command failure.
set -o pipefail           # Exit on failure of any command in a pipeline.
set -o errtrace           # Trap errors in functions and subshells.
shopt -s inherit_errexit  # Inherit the errexit option status in subshells.
shopt -s extglob          # Extend pattern matching.

verbosity="0"
die() { printf '%s\n' "$@" >&2; exit 1; }
die_option() { die "ERROR: ${1@Q} requires an option argument."; }
verbose() {
    if (( verbosity >= $1 )); then
        shift
        printf '%s\n' "$@"
    fi
}

# Print a useful trace when an error occurs
trap 'printf "%s\n" "ERROR: Error when executing ${BASH_COMMAND@Q} at line ${LINENO}!" >&2' ERR

# Get inputs from command line arguments
while :; do
    case "${1+x}" in '') break;; esac
    case "${1-}" in
        '--verbose')
            ((verbosity++)) || :
            ;;
        '--quiet')
            ((verbosity--)) || :
            ;;
        '--') shift; break;;
        '-'?|'--'*) die "ERROR: Unknown top-level option: $1";;
        '-'??*) die "ERROR: Switches must not be ran together: $1";;
        *) break
    esac
    shift
done
case "${1+x}" in '') die "ERROR: Specify a mount point.";; esac
mountPoint="$1"; shift
case "${1+x}" in '') die "ERROR: Specify a target file.";; esac
targetFile="$1"; shift
case "${1+x}" in 'x') die "ERROR: Unknown top-level positional argument: $3";; esac

if (( verbosity >= 3 )); then
    set -o xtrace
fi

mountPointTarget=$(readlink -f -- "$mountPoint")
if [[ -L "$mountPoint" && "$mountPointTarget" == "$targetFile" ]]; then
    verbose 1 "V: ${mountPoint@Q} already links to ${targetFile@Q}, ignoring" >&2
elif { mountStdout="$(mount)"; grep -F "$mountPoint"' ' <<< "$mountStdout" >/dev/null && ! grep -F "$mountPoint"/ <<< "$mountStdout" >/dev/null; }; then
    verbose 1 "V: A mount already exists at ${mountPoint@Q}, ignoring" >&2
elif [[ -e "$mountPoint" ]]; then
    die "ERROR: A file already exists at ${mountPoint@Q}!"
elif [[ -e "$targetFile" ]]; then
    verbose 2 "VV: A file exists at ${targetFile@Q}"
    verbose 2 "VV: Creating blank file at ${mountPoint@Q}" >&2
    touch -- "$mountPoint"
    verbose 2 "VV: Bind mounting ${targetFile@Q} to ${mountPoint@Q}" >&2
    mount -o bind -- "$targetFile" "$mountPoint"
else
    verbose 2 "VV: Symbolically linking ${targetFile@Q} to ${mountPoint@Q}" >&2
    ln -s -- "$targetFile" "$mountPoint"
fi
