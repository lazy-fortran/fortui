#!/bin/sh
# Print command for ippeveprinter -c: keeps the job's IPP attributes beside the
# received document ($1), so a test can read what the printer was asked for.
env | grep '^IPP_' | sort > "$1.attributes"
