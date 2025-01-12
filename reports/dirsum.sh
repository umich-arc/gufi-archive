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
trap 'rm -f outdb$$.*' EXIT

echo ""
echo "Using GUFI Index located in: $1"
echo "Reporting on data older than $DAYS days last accessed"
echo ""

gettitle="-N"

find "$1" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do
{
folder=$(basename "$dir")
$BFQ -E " \
	INSERT INTO sument select uid, name, size, atime, \
	case when datetime(atime, 'unixepoch') < DATE('now', '-"$DAYS" day') then size else 0 end as oldsize \
	FROM entries \
	WHERE type='f';" \
	-n $THREADS -O outdb$$ \
	-I "CREATE TABLE sument (username text, name text, size int64, atime int64, oldsize int64);" "$dir"

a=`$QUERYDBS -d \| -V $gettitle outdb$$ sument " \
	select count, sizeGB, oldsize, \
		PRINTF('%02d%%', (100*oldsize/sizeGB)) as percent \
		FROM( \
	SELECT COUNT(*) AS count, sum(size)/1024/1024/1024 AS sizeGB, sum(oldsize)/1024/1024/1024 as oldsize from vsument) \
	ORDER BY sizeGB DESC;" \
	outdb$$.*`
gettitle=""
b=`echo "$a" | awk '/^query returned/ {print $3}'`
if [ "$b" = 0 ]; then
  echo "$folder|0|0|0|(null)|"
else
  echo "$a" | awk -v folder="$folder" '/^query returned/ {next} /^count/ {print "directory|"$0;next} {print folder"|"$0}'
fi

# cleanup 
rm -f outdb$$.*
}
done | column -s '|' -t
