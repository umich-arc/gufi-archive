#!/bin/bash
THREADS=8

# are we in a normal install or outside of singularity?
if hash gufi_query 2> /dev/null; then
	BFQ=gufi_query
else
	BFQ="singularity exec gufi_master.sif gufi_query"
fi

if hash querydbs 2> /dev/null; then
	QUERYDBS=querydbs
else
	QUERYDBS="singularity exec --bind /etc/passwd gufi_master.sif querydbs"
fi

DAYS=${2:-180}

if [ $# -lt 1 ]; then echo "Usage: $(basename $0) index [days]"; exit 1; fi 

# cleanup 
trap 'rm -f outdb.*' EXIT

echo ""
echo "Using GUFI Index located in: $1"
echo "Reporting on data older than $DAYS days last accessed"
echo ""

$BFQ -E " \
	INSERT INTO sument select uid, name, size, atime, \
	case when datetime(atime, 'unixepoch') < DATE('now', '-"$DAYS" day') then size else 0 end as oldsize \
	FROM entries \
	WHERE type='f';" \
	-n $THREADS -O outdb \
	-I "CREATE TABLE sument (username text, name text, size int64, atime int64, oldsize int64);" "$1"

$QUERYDBS -d \| -NV outdb sument " \
	select username,count, sizeGB, oldsize, \
		PRINTF('%02d%%', (100*oldsize/sizeGB)) AS percent \
		FROM( \
	SELECT uidtouser(username, 0) AS username, COUNT(*) AS count, sum(size)/1024/1024/1024 AS sizeGB, sum(oldsize)/1024/1024/1024 as oldsize from vsument \
	GROUP BY uidtouser(username, 0)) \
	ORDER BY sizeGB DESC;" \
	outdb.* | column -s '|' -t



echo ""
echo "----------------- Path Totals -----------------"
$QUERYDBS -d \| -NV outdb sument " \
	select count, sizeGB, oldsize, \
		PRINTF('%02d%%', (100*oldsize/sizeGB)) AS percent \
		FROM( \
		SELECT uidtouser(username, 0) AS username, COUNT(*) AS count, sum(size)/1024/1024/1024 AS sizeGB, sum(oldsize)/1024/1024/1024 as oldsize from vsument);" \
	outdb.* | column -s '|' -t

# cleanup 
rm -f outdb.*
