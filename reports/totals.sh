#!/bin/bash

# just show the totals for a path, don't worry about user or folder data

. "$(dirname "$(readlink -f "$0")")/lib.bash"

DAYS=${2:-180}

if [ $# -lt 1 ]; then echo "Usage: $(basename $0) index [days]"; exit 1; fi

echo ""
echo "Using GUFI Index located in: $1"
echo "Reporting on data older than $DAYS days last accessed"
echo ""

dirstats_load "$1" "$DAYS" 0
print_totals "$DAYS" | column -s '|' -t
