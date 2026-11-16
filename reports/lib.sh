# shared setup for the reports, sourced by each script
#
# The index is usually bigger than RAM and lives on spinning disk, so a walk
# costs seeks, not CPU.  Every report built on dirstats_walk reads the index
# once and keeps only per-directory sums, so several reports can share a walk.

THREADS=${GUFI_THREADS:-8}

# directories deeper than this are summed into their ancestor at this depth
CACHE_DEPTH=${GUFI_CACHE_DEPTH:-5}

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

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/gufi-archive.XXXXXX") || exit 1
trap 'rm -rf "$WORKDIR"' EXIT
DIRSTATS="$WORKDIR/dirstats"

# walk the index once, summing files by directory and owner
#
# Each directory's row is keyed by its path relative to the index argument,
# cut to CACHE_DEPTH components, so the result stays small however deep the
# tree goes.  Files directly in the index argument get the key ''.
dirstats_walk () {
	local index_path=$1
	local days=$2
	local real_path cutoff_epoch

	# gufi_query reports fpath() as a realpath
	real_path=$(realpath "$index_path") || exit 1
	real_path=${real_path//\'/\'\'}

	# midnight UTC, the same cutoff the old datetime() < DATE('now') test used
	cutoff_epoch=$(date -u -d "$(date -u +%F) $days days ago" +%s)

	$BFQ -n "$THREADS" \
		-I "CREATE TABLE stats (dir text, uid int64, cnt int64, bytes int64, oldbytes int64);" \
		-E "INSERT INTO stats \
			WITH RECURSIVE cut(depth, rest, keep) AS ( \
				SELECT 0, substr(fpath(), length('$real_path') + 2) || '/', '' \
				UNION ALL \
				SELECT depth + 1, substr(rest, instr(rest, '/') + 1), \
					keep || substr(rest, 1, instr(rest, '/')) \
				FROM cut WHERE depth < $CACHE_DEPTH AND rest != '') \
			SELECT (SELECT rtrim(keep, '/') FROM cut ORDER BY depth DESC LIMIT 1), \
				uid, COUNT(*), SUM(size), \
				SUM(CASE WHEN atime < $cutoff_epoch THEN size ELSE 0 END) \
			FROM entries WHERE type='f' GROUP BY uid;" \
		-K "CREATE TABLE dirstats (dir text, uid int64, cnt int64, bytes int64, oldbytes int64);" \
		-J "INSERT INTO dirstats SELECT dir, uid, SUM(cnt), SUM(bytes), SUM(oldbytes) \
			FROM stats GROUP BY dir, uid;" \
		-O "$DIRSTATS" "$index_path"
}

# one row per directory directly below the index argument, in find order
#
# Directories holding no files never reach the walk's results, so they are
# listed from the index itself and filled in with the row an empty sum gives.
print_dirsum () {
	local index_path=$1

	echo "directory|count|sizeGB|oldsize|percent"
	awk -F '\036' -v OFS='|' '
		NR == FNR { row[$1] = $2 OFS $3 OFS $4 OFS $5; next }
		{ print $0, ($0 in row ? row[$0] : "0|(null)|(null)|00%") }' \
		<($QUERYDBS -d x -V dirstats dirstats " \
			SELECT topdir, count, sizeGB, oldsize, \
				PRINTF('%02d%%', (100*oldsize/sizeGB)) AS percent \
			FROM ( \
				SELECT substr(dir, 1, instr(dir || '/', '/') - 1) AS topdir, \
					SUM(cnt) AS count, \
					SUM(bytes)/1024/1024/1024 AS sizeGB, \
					SUM(oldbytes)/1024/1024/1024 AS oldsize \
				FROM vdirstats GROUP BY topdir) \
			WHERE topdir != '';" \
			"$DIRSTATS" | grep -v '^query returned') \
		<(find "$index_path" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
}

# one row totalling everything below the index argument
print_totals () {
	$QUERYDBS -d \| -NV dirstats dirstats " \
		SELECT count, sizeGB, oldsize, \
			PRINTF('%02d%%', (100*oldsize/sizeGB)) AS percent \
		FROM ( \
			SELECT SUM(cnt) AS count, \
				SUM(bytes)/1024/1024/1024 AS sizeGB, \
				SUM(oldbytes)/1024/1024/1024 AS oldsize \
			FROM vdirstats);" \
		"$DIRSTATS" | grep -v '^query returned'
}
