#!/bin/bash
THREADS=4
BFQ="singularity exec gufi_master.sif gufi_query"
QUERYDBS="singularity exec gufi_master.sif querydbs"

$BFQ -E "insert into sument select uidtouser(uid, 0), name, size, mtime from entries where type='f'and size>4;" -n $THREADS -O outdb -I "create table sument (username text, name text, size int64, mtime int64);" $1

$QUERYDBS -NV outdb sument "select username, name,size/1024/1024,datetime(mtime, 'unixepoch') from vsument order by size;" outdb.*

# cleanup 
rm -f outdb.*
