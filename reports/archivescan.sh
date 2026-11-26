#!/bin/bash

# report how much data would move to archive backend

. "$(dirname "$(readlink -f "$0")")/lib.bash"

MIGRATESIZE=${2:-100}

if [ $# -lt 1 ]; then echo "Usage: $(basename $0) index [MB]"; exit 1; fi
if [[ ! "$MIGRATESIZE" =~ ^[0-9]+$ ]]; then echo "MB must be a whole number, not '$MIGRATESIZE'" 1>&2; exit 1; fi

echo ""
echo "Using GUFI Index located in: $1"
echo "Reporting on data larger than $MIGRATESIZE MB"
echo ""

# one row per directory, not per file; bytes stay exact until the last query
SCAN_COLUMNS="cnt int64, cachecnt int64, tapecnt int64, bytes int64, cachebytes int64, tapebytes int64"
$BFQ -n "$THREADS" \
	-I "CREATE TABLE scan ($SCAN_COLUMNS);" \
	-E "INSERT INTO scan SELECT COUNT(*), \
		COUNT(CASE WHEN (size / 1024 / 1024) < $MIGRATESIZE THEN 1 END), \
		COUNT(CASE WHEN (size / 1024 / 1024) >= $MIGRATESIZE THEN 1 END), \
		SUM(size), \
		SUM(CASE WHEN size > $MIGRATESIZE * 1024 * 1024 THEN 0 ELSE size END), \
		SUM(CASE WHEN size > $MIGRATESIZE * 1024 * 1024 THEN size ELSE 0 END) \
		FROM entries WHERE type='f';" \
	-K "CREATE TABLE archivescan ($SCAN_COLUMNS);" \
	-J "INSERT INTO archivescan SELECT SUM(cnt), SUM(cachecnt), SUM(tapecnt), \
		SUM(bytes), SUM(cachebytes), SUM(tapebytes) FROM scan;" \
	-O "$WORKDIR/archivescan" "$1"

echo ""
echo "Total Data, Data in files larger than $MIGRATESIZE MB, Archive Offline Ratio"
echo ""

$QUERYDBS -d \| -NV archivescan archivescan " \
	SELECT count, sizeGB, cacheCnt, cachesizeGB, tapeCnt, tapesizeGB, \
		PRINTF('%02d%%', (100*tapesizeGB/sizeGB)) AS archiveGBratio, \
		PRINTF('%02d%%', (100*tapeCnt/count)) AS archiveCntRatio \
	FROM ( \
		SELECT SUM(cachecnt) AS cacheCnt, SUM(tapecnt) AS tapeCnt, \
			SUM(cachebytes)/1024/1024/1024 AS cachesizeGB, \
			SUM(cnt) AS count, SUM(bytes)/1024/1024/1024 AS sizeGB, \
			SUM(tapebytes)/1024/1024/1024 AS tapesizeGB \
		FROM varchivescan);" \
	"$WORKDIR/archivescan" | grep -v '^query returned' | column -s '|' -t
