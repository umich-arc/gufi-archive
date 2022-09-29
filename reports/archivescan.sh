#!/bin/bash

# report how much data would move to archivebackent

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

MIGRATESIZE=${2:-100}

if [ $# -lt 1 ]; then echo "Usage: $(basename $0) index [days]"; exit 1; fi 

# cleanup 
trap 'rm -f outdb.*' EXIT

echo ""
echo "Using GUFI Index located in: $1"
echo "Reporting on data larger than $MIGRATESIZE MB"
echo ""

$BFQ -E " \
	INSERT INTO sument select uid, name, size, atime, \
	case when size > $MIGRATESIZE * 1024 * 1024 then size else 0 end as oversize \
	FROM entries \
	WHERE type='f';" \
	-n $THREADS -O outdb \
	-I "CREATE TABLE sument (username text, name text, size int64, atime int64, oversize int64);" $1

echo ""
echo "Total Data, Data in files larger than $MIGRATESIZE MB, Archive Offline Ratio"
echo ""

$QUERYDBS -d \| -NV outdb sument " \
	SELECT count, sizeGB, cacheCnt, cachesizeGB, tapeCnt, tapesizeGB, (100*tapesizeGB/sizeGB) as archiveGBratio, (100*tapeCnt/count) as archiveCntRatio from( \
		SELECT 
		COUNT(CASE WHEN (size * 1024 * 1024) < $MIGRATESIZE THEN 1 ELSE NULL END) as cacheCnt, \
		COUNT(CASE WHEN (size * 1024 * 1024) >= $MIGRATESIZE THEN 1 ELSE NULL END) as tapeCnt, \
		SUM(CASE WHEN oversize != 0 THEN size ELSE 0 END)/1024/1024/1024 as cachesizeGB, \
		COUNT(*) AS count, sum(size)/1024/1024/1024 AS sizeGB, sum(oversize)/1024/1024/1024 as tapesizeGB from vsument);" \
	outdb.* | column -s '|' -t

# cleanup 
rm -f outdb.*
