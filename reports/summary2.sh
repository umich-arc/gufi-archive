#!/bin/bash
THREADS=4
BFQ="singularity exec gufi_master.sif gufi_query"
QUERYDBS="singularity exec --bind /etc/passwd gufi_master.sif querydbs"
DAYS=${2:-180}
# check if not using singularity
a=`whereis singularity`
if [ -n "$a" ]; then
  BFQ=gufi_query
  QUERYDBS=querydbs
fi

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
	-I "CREATE TABLE sument (username text, name text, size int64, atime int64, oldsize int64);" $1

$QUERYDBS -NV outdb sument " \
	SELECT uidtouser(username, 0) AS username, COUNT(*) AS count, sum(size)/1024/1024/1024 AS sizeGB, sum(oldsize)/1024/1024/1024 as oldsize from vsument \
	GROUP BY uidtouser(username, 0) \
	ORDER BY sizeGB DESC;" \
	outdb.* | column -s '|' -t

# cleanup 
rm -f outdb.*
