#!/bin/bash

# histogram bin file metadata timestamps (atime/mtime/ctime)
#
# Purge keeps anything touched inside the window, looking at both atime and
# ctime.  Someone who runs 'touch' across their whole tree resets those clocks,
# but they cannot hide the shape of it: ctime is stamped by the kernel on every
# inode change and there is no syscall to set it, so a mass touch always leaves
# a spike in the ctime histogram.  Bin narrow (1h) to find the spike, bin wide
# (30d) for capacity planning.

THREADS=12

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

if [ $# -lt 1 ]; then echo "Usage: $(basename $0) index [binwidth] [maxage] [user]"; exit 1; fi

# turn 30m / 6h / 7d / 4w (or bare seconds) into seconds
tosecs () {
	local n=${1%[smhdw]}
	if ! [[ $n =~ ^[0-9]+$ ]] || [ "$n" -eq 0 ]; then echo "$(basename $0): bad interval '$1'" >&2; exit 1; fi
	case ${1#$n} in
		s|'') echo $((n)) ;;
		m)    echo $((n * 60)) ;;
		h)    echo $((n * 3600)) ;;
		d)    echo $((n * 86400)) ;;
		w)    echo $((n * 604800)) ;;
	esac
}

BIN=$(tosecs "${2:-7d}") || exit 1
MAXAGE=$(tosecs "${3:-1095d}") || exit 1

# seconds back into something readable for the banner
human () {
	if   [ "$1" -ge 86400 ]; then plural $(($1 / 86400)) day
	elif [ "$1" -ge 3600 ];  then plural $(($1 / 3600)) hour
	elif [ "$1" -ge 60 ];    then plural $(($1 / 60)) minute
	else                          plural "$1" second; fi
}

plural () {
	if [ "$1" -eq 1 ]; then echo "$1 $2"; else echo "$1 ${2}s"; fi
}

# one timestamp is fixed for both query phases so the bins cannot drift
NOW=$(date +%s)

# sentinel bins that sort either side of the real ones
FUTURE=-1
OLDER=999999999

# resolve an optional username or uid to restrict the report to
UIDFILT=""
WHO="all users"
if [ -n "$4" ]; then
	if [[ $4 =~ ^[0-9]+$ ]]; then
		WHOUID=$4
	else
		WHOUID=$(id -u "$4") || exit 1
	fi
	UIDFILT=" AND uid = $WHOUID"
	WHO="uid $WHOUID"
fi

# bin a timestamp column by age, bucketing the future and the far past aside
agebin () {
	echo "CASE WHEN $1 > $NOW THEN $FUTURE \
		WHEN ($NOW - $1) >= $MAXAGE THEN $OLDER \
		ELSE ($NOW - $1) / $BIN END"
}

# cleanup
trap 'rm -f outdb$$.*' EXIT

echo ""
echo "Using GUFI Index located in: $1"
echo "Binning $WHO in steps of $(human $BIN) out to $(human $MAXAGE)"
echo "Each row holds files aged from ageDays up to ageDays plus one bin"
echo ""

# aggregate per directory so the scratch table stays small on 100M file indexes
$BFQ -E " \
	INSERT INTO mdhist \
	SELECT 'a', uid, bin, COUNT(*), SUM(size) FROM ( \
		SELECT uid, size, $(agebin atime) AS bin FROM entries WHERE type='f'$UIDFILT) \
		GROUP BY uid, bin \
	UNION ALL \
	SELECT 'm', uid, bin, COUNT(*), SUM(size) FROM ( \
		SELECT uid, size, $(agebin mtime) AS bin FROM entries WHERE type='f'$UIDFILT) \
		GROUP BY uid, bin \
	UNION ALL \
	SELECT 'c', uid, bin, COUNT(*), SUM(size) FROM ( \
		SELECT uid, size, $(agebin ctime) AS bin FROM entries WHERE type='f'$UIDFILT) \
		GROUP BY uid, bin;" \
	-n $THREADS -O outdb$$ \
	-I "CREATE TABLE mdhist (ts text, uid int64, bin int64, cnt int64, bytes int64);" "$1"

# pivot the three timestamps back into one row per bin
$QUERYDBS -d \| -NV outdb$$ mdhist " \
	SELECT \
		CASE WHEN bin = $FUTURE THEN 'future' \
			WHEN bin = $OLDER THEN 'older' \
			ELSE PRINTF('%.2f', (bin * $BIN) / 86400.0) END AS ageDays, \
		CASE WHEN bin = $FUTURE OR bin = $OLDER THEN '-' \
			ELSE DATETIME($NOW - bin * $BIN, 'unixepoch', 'localtime') END AS date, \
		SUM(CASE WHEN ts = 'a' THEN cnt ELSE 0 END) AS atimeCnt, \
		SUM(CASE WHEN ts = 'a' THEN bytes ELSE 0 END)/1024/1024/1024 AS atimeGB, \
		SUM(CASE WHEN ts = 'm' THEN cnt ELSE 0 END) AS mtimeCnt, \
		SUM(CASE WHEN ts = 'm' THEN bytes ELSE 0 END)/1024/1024/1024 AS mtimeGB, \
		SUM(CASE WHEN ts = 'c' THEN cnt ELSE 0 END) AS ctimeCnt, \
		SUM(CASE WHEN ts = 'c' THEN bytes ELSE 0 END)/1024/1024/1024 AS ctimeGB \
	FROM vmdhist GROUP BY bin ORDER BY bin;" \
	outdb$$.* | awk -F'|' '
		/^query returned/ { next }
		{ line[++n] = $0
		  if (n == 1) { for (i = 1; i <= NF; i++) if ($i == "ctimeCnt") c = i; next }
		  val[n] = $c + 0
		  if (val[n] > max) max = val[n] }
		END {
			print line[1] "|ctimeBar"
			for (i = 2; i <= n; i++) {
				bar = ""
				if (max > 0) for (j = 0; j < int(50 * val[i] / max); j++) bar = bar "#"
				print line[i] "|" bar
			}
		}' | column -s '|' -t

# a mass touch cannot move ctime without landing in one of these
echo ""
echo "----------------- Densest ctime bins (inode changes cluster here) -----------------"
$QUERYDBS -d \| -NV outdb$$ mdhist " \
	SELECT DATETIME($NOW - bin * $BIN, 'unixepoch', 'localtime') AS date, \
		uidtouser(uid, 0) AS username, \
		SUM(cnt) AS files, \
		SUM(bytes)/1024/1024/1024 AS sizeGB \
	FROM vmdhist WHERE ts = 'c' AND bin >= 0 AND bin != $OLDER \
	GROUP BY uid, bin ORDER BY files DESC LIMIT 20;" \
	outdb$$.* | grep -v '^query returned' | column -s '|' -t

# cleanup
rm -f outdb$$.*
