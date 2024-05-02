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
method="auto"
bindfsMountPointMethod="auto"
bindfsMountPointIgnoreExistingEmpty="1"
while :; do
    case "${1+x}" in '') break;; esac
    case "${1-}" in
        '--verbose')
            ((verbosity++)) || :
            ;;
        '--quiet')
            ((verbosity--)) || :
            ;;
        '--method')
            case "${2+x}" in '') die_option "$1";; esac
            case "$2" in
                'auto'|'bindfs'|'symlink')
                    method="$2"
                    ;;
                *)
                    die "ERROR: Method must be 'auto', 'bindfs', or 'symlink': ${2@Q}"
            esac
            shift
            ;;
        '--bindfs-mount-point-ignore-existing-empty')
            bindfsMountPointIgnoreExistingEmpty="0"
            ;;
        '--bindfs-mount-point-method')
            case "${2+x}" in '') die_option "$1";; esac
            case "$2" in
                'auto'|'empty'|'symlink')
                    bindfsMountPointMethod="$2"
                    ;;
                *)
                    die "ERROR: bindfs mount point method must be 'auto', 'empty', or 'symlink': ${2@Q}"
            esac
            shift
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

computedMethod="$method"
computedBindfsMountPointMethod="$bindfsMountPointMethod"

existingMountPointSymlink="1"
mountPointTarget=""
matchingMountPointSymlink="1"
detectMountPointSymlink() {
    set +e
    [[ -L "$mountPoint" ]]
    existingMountPointSymlink="$?"
    matchingMountPointSymlink="1"
    if [[ existingMountPointSymlink -eq 0 ]]; then
        set -e
        mountPointTarget=$(readlink -f -- "$mountPoint")
        set +e
        [[ "$mountPointTarget" == "$targetFile" ]]
        matchingMountPointSymlink="$?"
    fi
    set -e
}

findmntStdout=""
existingMountPointMount="1"
detectMountPointMount() {
    set +e
    findmntStdout="$(findmnt --mountpoint "$mountPoint")"
    existingMountPointMount="$?"
    set -e
}

existingMountPointFile="1"
detectMountPointFile() {
    set +e
    [[ -e "$mountPoint" ]]
    existingMountPointFile="$?"
    set -e
}

existingTargetFile="1"
detectTargetFile() {
    set +e
    [[ -e "$targetFile" ]]
    existingTargetFile="$?"
    set -e
}

detectMountPointSymlink

if [[ "$computedMethod" == 'auto' && existingMountPointSymlink -eq 0 ]]; then
    computedMethod="symlink"
    verbose 2 "VV: Method ${computedMethod@Q} computed from ${method@Q} due to existing symlink at mount point"
fi

if [[ "$computedMethod" != 'symlink' ]]; then
    detectMountPointMount

    if [[ "$computedMethod" == 'auto' && existingMountPointMount -eq 0 ]]; then
        computedMethod="bindfs"
        verbose 2 "VV: Method ${computedMethod@Q} computed from ${method@Q} due to existing mount at mount point"
    fi
fi


detectMountPointFile
detectTargetFile

case "$computedMethod" in 'auto')
    if [[ existingTargetFile -eq 0 ]]; then
        computedMethod=bindfs
        verbose 2 "VV: Method ${computedMethod@Q} computed from ${method@Q} due to existing file at target"
    else
        computedMethod=symlink
        verbose 2 "VV: Method ${computedMethod@Q} computed from ${method@Q} due to no existing file at target"
    fi
esac

case "$computedBindfsMountPointMethod" in 'auto')
    if [[ "$computedMethod" == 'symlink' ]]; then
        computedBindfsMountPointMethod='symlink'
        verbose 2 "VV: bindfs mount point method ${computedBindfsMountPointMethod@Q} computed from ${bindfsMountPointMethod@Q} due to computed method ${computedMethod@Q}"
    elif [[ matchingMountPointSymlink -eq 0 ]]; then
        computedBindfsMountPointMethod='symlink'
        verbose 2 "VV: bindfs mount point method ${computedBindfsMountPointMethod@Q} computed from ${bindfsMountPointMethod@Q} due to existing, matching symbolic link"
    else
        computedBindfsMountPointMethod='empty'
        verbose 2 "VV: bindfs mount point method ${computedBindfsMountPointMethod@Q} computed from ${bindfsMountPointMethod@Q} as fallback"
    fi
esac

if [[ "$computedMethod" == 'symlink' || ( "$computedMethod" == 'bindfs' && "$computedBindfsMountPointMethod" == 'symlink' ) ]]; then
    if [[ matchingMountPointSymlink -eq 0 ]]; then
        verbose 1 "V: ${mountPoint@Q} already links to ${targetFile@Q}, ignoring" >&2
    elif [[ existingMountPointFile -eq 0 ]]; then
        die "ERROR: A file already exists at ${mountPoint@Q}!"
    else
        verbose 2 "VV: Symbolically linking ${targetFile@Q} to ${mountPoint@Q}" >&2
        ln -s -- "$targetFile" "$mountPoint"
        if [[ "$computedMethod" != 'symlink' ]]; then
            detectMountPointSymlink
            detectMountPointFile
        fi
    fi
fi

if [[ "$computedMethod" == 'bindfs' ]]; then
    if [[ existingMountPointMount -eq 0 ]]; then
        verbose 1 "V: A mount already exists at ${mountPoint@Q}, ignoring" >&2
    elif [[ existingMountPointFile -eq 0 && matchingMountPointSymlink -ne 0 && ( bindfsMountPointIgnoreExistingEmpty -ne 0 || -s "$mountPoint" ) ]]; then
        die "ERROR: A file already exists at ${mountPoint@Q}!"
    else
        if [[ "$computedBindfsMountPointMethod" == 'empty' && existingMountPointFile -ne 0 ]]; then
            verbose 2 "VV: Creating empty file at ${mountPoint@Q}" >&2
            touch -- "$mountPoint"
        fi
        verbose 2 "VV: Bind mounting ${targetFile@Q} to ${mountPoint@Q}" >&2
        mount -o bind -- "$targetFile" "$mountPoint"
        if [[ "$computedMethod" != 'bindfs' ]]; then
            detectMountPointMount
            detectMountPointFile
        fi
    fi
fi
