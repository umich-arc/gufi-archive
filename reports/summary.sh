#!/bin/bash
THREADS=4
BFQ="singularity exec gufi_master.sif gufi_query"
QUERYDBS="singularity exec --bind /etc/passwd gufi_master.sif querydbs"
DAYS=${2:-180}

echo ""
echo "Using GUFI Index located in: $1"
echo "Reporting on data older than $DAYS days last accessed"
echo ""

$BFQ -E "insert into sument select uid, name, size, atime from entries where type='f'and size>4 AND datetime(atime, 'unixepoch') < DATE('now', '-"$DAYS" day');" -n $THREADS -O outdb -I "create table sument (username text, name text, size int64, atime int64);" $1

$QUERYDBS -NV outdb sument "select uidtouser(username, 0) AS username, COUNT(*) AS count, sum(size)/1024/1024/1024 AS sizeGB from vsument GROUP BY uidtouser(username, 0) ORDER BY sizeGB DESC;" outdb.* | column -s '|' -t
#$QUERYDBS -NV outdb sument "select name,username, size from vsument WHERE username NOT LIKE 'brockp';" outdb.*

# cleanup 
rm -f outdb.*
