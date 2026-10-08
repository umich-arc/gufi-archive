#!/bin/bash

# find users who reset timestamps to keep files past the purge window
#
# purgetools removes a file only when atime, mtime and ctime are all older than
# 60 days, so a file survives when MAX(atime, mtime, ctime) is inside the window.
# It re-checks each file at purge time, so anything a user refreshes during the
# notice period is spared.  atime
# and mtime can be set to any value with utimensat, so 'touch' rewrites them
# freely, but there is no syscall that writes ctime: the kernel stamps it on
# every inode change.  That leaves four things a mass touch cannot hide.
#
#   touchGB   mtime is stale, yet atime and ctime moved together.  Reading a file
#             moves atime alone and leaves ctime back near mtime, so the two
#             moving as one means the inode was written, not read.  'touch -a'
#             lands here.
#   coGB      atime and mtime are both outside the window and only ctime is
#             inside it, so these files survive purely on the ctime half of the
#             policy.  'touch -a -t <old date>' does this deliberately, and a
#             recursive chmod or chown does it by accident.
#   mtGB      mtime and ctime moved together while atime stayed outside the
#             window, which is what 'touch -m' leaves behind on a file nobody has
#             read in months.
#   hotHr     most files any one of the user's ctime hours holds.  Plain 'touch'
#             sets all three timestamps to now, which one snapshot cannot tell
#             from a fresh write, and 'touch -a -d' can scatter atime to dodge the
#             tests above, but every inode still took its ctime the hour the
#             sweep ran.
#
# Two things also produce stale mtime beside a fresh atime and ctime: a restore
# or copy that preserved timestamps (cp -p, rsync -a, tar -xp), and an append
# only log that has not been read in months.  Check a hit against dirsum.sh and
# the ctime hours below, since neither of those crams thousands of files into one
# hour the way a sweep does.  Keeping last month's index and diffing it against
# today's settles the rest: an inode whose ctime moved while its size stayed put
# was swept, not written.

THREADS=12

# a touch sets its timestamps from one clock read, so allow a second of skew
SLOP=2

# ctime bucket used for the burst tests
BIN=3600

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

if [ $# -lt 1 ]; then echo "Usage: $(basename $0) index [days] [minfiles] [user]"; exit 1; fi

DAYS=${2:-60}
MINFILES=${3:-1000}

# one timestamp for both query phases so the cutoff cannot drift between them
NOW=$(date +%s)
CUT=$((NOW - DAYS * 86400))

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

# the four tests, kept here so the table and the evidence list cannot disagree
SURVIVES="atime >= $CUT OR mtime >= $CUT OR ctime >= $CUT"
TOUCHED="mtime < $CUT AND ctime >= $CUT AND ABS(atime - ctime) <= $SLOP"
CTIMEONLY="mtime < $CUT AND atime < $CUT AND ctime >= $CUT"
MTSWEEP="mtime >= $CUT AND atime < $CUT AND ABS(mtime - ctime) <= $SLOP"

# cleanup
trap 'rm -f outdb$$.*' EXIT

echo ""
echo "Using GUFI Index located in: $1"
echo "Purge window is $DAYS days on MAX(atime, mtime, ctime), reporting $WHO"
echo ""

# bucket by ctime during the scan so the burst tests have their bins already
$BFQ -E " \
	INSERT INTO evade \
	SELECT uid, \
		CASE WHEN ctime > $NOW THEN -1 ELSE ($NOW - ctime) / $BIN END AS bin, \
		COUNT(*), \
		SUM(size), \
		SUM(CASE WHEN $SURVIVES THEN 1 ELSE 0 END), \
		SUM(CASE WHEN $SURVIVES THEN size ELSE 0 END), \
		SUM(CASE WHEN $TOUCHED THEN 1 ELSE 0 END), \
		SUM(CASE WHEN $TOUCHED THEN size ELSE 0 END), \
		SUM(CASE WHEN $CTIMEONLY THEN 1 ELSE 0 END), \
		SUM(CASE WHEN $CTIMEONLY THEN size ELSE 0 END), \
		SUM(CASE WHEN $MTSWEEP THEN 1 ELSE 0 END), \
		SUM(CASE WHEN $MTSWEEP THEN size ELSE 0 END), \
		SUM(CASE WHEN atime > $NOW + $SLOP OR mtime > $NOW + $SLOP THEN 1 ELSE 0 END), \
		SUM(CASE WHEN atime = mtime THEN 1 ELSE 0 END) \
	FROM entries WHERE type='f'$UIDFILT \
	GROUP BY uid, bin;" \
	-n $THREADS -O outdb$$ \
	-I "CREATE TABLE evade (uid int64, bin int64, cnt int64, bytes int64, \
		survCnt int64, survBytes int64, touchCnt int64, touchBytes int64, \
		coCnt int64, coBytes int64, mtCnt int64, mtBytes int64, \
		futCnt int64, amEq int64);" "$1"

# the inner group collapses the per directory rows so MAX() sees whole hours
$QUERYDBS -d \| -NV outdb$$ evade " \
	SELECT username, files, sizeGB, survGB, touchGB, coGB, mtGB, \
		PRINTF('%d%%', 100 * suspBytes / CASE WHEN survBytes > 0 THEN survBytes ELSE 1 END) AS suspPct, \
		futCnt, hotHr, \
		PRINTF('%d%%', 100 * peakCnt / CASE WHEN suspCnt > 0 THEN suspCnt ELSE 1 END) AS peakHrPct \
	FROM ( \
		SELECT uidtouser(uid, 0) AS username, \
			SUM(f) AS files, SUM(b)/1024/1024/1024 AS sizeGB, \
			SUM(sb)/1024/1024/1024 AS survGB, SUM(sb) AS survBytes, \
			SUM(tb)/1024/1024/1024 AS touchGB, \
			SUM(cb)/1024/1024/1024 AS coGB, \
			SUM(mb)/1024/1024/1024 AS mtGB, \
			SUM(tb + cb + mb) AS suspBytes, \
			SUM(tc + cc + mc) AS suspCnt, \
			SUM(fc) AS futCnt, \
			MAX(tc + cc + mc) AS peakCnt, \
			MAX(CASE WHEN bin >= 0 THEN f ELSE 0 END) AS hotHr \
		FROM ( \
			SELECT uid, bin, SUM(cnt) AS f, SUM(bytes) AS b, \
				SUM(survCnt) AS sc, SUM(survBytes) AS sb, \
				SUM(touchCnt) AS tc, SUM(touchBytes) AS tb, \
				SUM(coCnt) AS cc, SUM(coBytes) AS cb, \
				SUM(mtCnt) AS mc, SUM(mtBytes) AS mb, \
				SUM(futCnt) AS fc \
			FROM vevade GROUP BY uid, bin) \
		GROUP BY uid) \
	WHERE files >= $MINFILES AND (suspCnt > 0 OR futCnt > 0) \
	ORDER BY suspBytes DESC;" \
	outdb$$.* | grep -v '^query returned' | column -s '|' -t

echo ""
echo "----------------- Busiest ctime hours (when the sweep ran) -----------------"
$QUERYDBS -d \| -NV outdb$$ evade " \
	SELECT hourEnding, username, files, suspect, suspectGB, \
		PRINTF('%d%%', 100 * suspect / CASE WHEN files > 0 THEN files ELSE 1 END) AS suspPct \
	FROM ( \
		SELECT DATETIME($NOW - bin * $BIN, 'unixepoch', 'localtime') AS hourEnding, \
			uidtouser(uid, 0) AS username, \
			SUM(cnt) AS files, \
			SUM(touchCnt + coCnt + mtCnt) AS suspect, \
			SUM(touchBytes + coBytes + mtBytes)/1024/1024/1024 AS suspectGB \
		FROM vevade WHERE bin >= 0 \
		GROUP BY uid, bin HAVING SUM(cnt) >= $MINFILES) \
	ORDER BY suspect DESC, files DESC LIMIT 20;" \
	outdb$$.* | grep -v '^query returned' | column -s '|' -t

echo ""
echo "----------------- Path Totals -----------------"
$QUERYDBS -d \| -NV outdb$$ evade " \
	SELECT files, sizeGB, survGB, \
		PRINTF('%d%%', 100 * survBytes / CASE WHEN bytes > 0 THEN bytes ELSE 1 END) AS survPct, \
		touchGB, coGB, mtGB, \
		PRINTF('%d%%', 100 * amEq / CASE WHEN files > 0 THEN files ELSE 1 END) AS atimeEqMtime \
	FROM ( \
		SELECT SUM(cnt) AS files, SUM(bytes)/1024/1024/1024 AS sizeGB, SUM(bytes) AS bytes, \
			SUM(survBytes)/1024/1024/1024 AS survGB, SUM(survBytes) AS survBytes, \
			SUM(touchBytes)/1024/1024/1024 AS touchGB, \
			SUM(coBytes)/1024/1024/1024 AS coGB, \
			SUM(mtBytes)/1024/1024/1024 AS mtGB, \
			SUM(amEq) AS amEq \
		FROM vevade);" \
	outdb$$.* | grep -v '^query returned' | column -s '|' -t

echo ""
echo "suspPct is the share of surviving data the tests above call reset."
echo "coGB is data the purge spares only because ctime is in the policy."
echo "A high atimeEqMtime means atime is barely moving, check for noatime."

# cleanup
rm -f outdb$$.*
