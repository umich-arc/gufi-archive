#!/bin/bash

# totals per file owner for a path, from the same walk and cache as dirsum

. "$(dirname "$(readlink -f "$0")")/lib.bash"

DAYS=${2:-180}

if [ $# -lt 1 ]; then echo "Usage: $(basename $0) index [days]"; exit 1; fi

echo ""
echo "Using GUFI Index located in: $1"
echo "Reporting on data older than $DAYS days last accessed"
echo ""

dirstats_load "$1" "$DAYS" 0

$QUERYDBS -d \| -NV dirstats dirstats " \
	SELECT uidtouser(uid, 0) AS username, count, sizeGB, oldsize, \
		PRINTF('%02d%%', (100*oldsize/sizeGB)) AS percent \
	FROM ( \
		SELECT uid, SUM(cnt) AS count, \
			SUM(bytes)/1024/1024/1024 AS sizeGB, \
			SUM(old$DAYS)/1024/1024/1024 AS oldsize \
		FROM $(below_requested) GROUP BY uid) \
	ORDER BY sizeGB DESC;" \
	"$DIRSTATS" | grep -v '^query returned' | column -s '|' -t

echo ""
echo "----------------- Path Totals -----------------"
print_totals "$DAYS" | column -s '|' -t
