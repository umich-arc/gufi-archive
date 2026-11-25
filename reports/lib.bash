# shared setup for the reports, sourced by each script
#
# The index is usually bigger than RAM and lives on spinning disk, so a walk
# costs seeks, not CPU.  Every report built on dirstats_load reads the index
# once and keeps only per-directory sums, so several reports can share a walk.
# Those sums are also cached at the top of the walked index, so drilling into
# its subdirectories afterwards does not walk the index again.

THREADS=${GUFI_THREADS:-8}

# directories deeper than this are summed into their ancestor at this depth
CACHE_DEPTH=${GUFI_CACHE_DEPTH:-5}

# GUFI_CACHE=0 (or false, no, off) always walks and never writes a cache
CACHE=yes
case "${GUFI_CACHE,,}" in 0|false|no|off) CACHE="" ;; esac
CACHE_NAME=".gufi-archive-cache-v2-depth$CACHE_DEPTH.db"

# days cutoffs every walk computes, so the cache answers these without a walk
AGE_BUCKETS="30 60 90 120 150 180 270 365 730 1095 1826"

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

# the sums the print functions read, and the requested path's place in them
DIRSTATS="$WORKDIR/dirstats"
DIRSTATS_REL=""

# get per-directory sums for an index path, from a cache or a fresh walk
#
# levels_below is how many directory levels under the path the report shows,
# 1 for dirsum and 0 for totals, so a cache is only used if it reaches them.
dirstats_load () {
	local index_path=$1
	local days=$2
	local levels_below=$3

	if [ -n "$CACHE" ] && dirstats_find_cache "$index_path" "$days" "$levels_below"; then
		return
	fi
	dirstats_walk "$index_path" "$days"
	DIRSTATS_REL=""
	if [ -n "$CACHE" ]; then
		# write beside the final name then rename, so readers never see half a file
		cp "$DIRSTATS" "$index_path/$CACHE_NAME.$$" 2> /dev/null &&
			mv -f "$index_path/$CACHE_NAME.$$" "$index_path/$CACHE_NAME"
	fi
}

# look in the path and each parent inside the index for a usable cache
#
# A cache is usable if it was made after the index was built, holds the
# requested days, and reaches deep enough.  The index is a snapshot, so a cache
# keeps its ages counted from the day it was made, however long ago that was.
dirstats_find_cache () {
	local index_path=$1
	local days=$2
	local levels_below=$3
	local real_path dir cache rel depth asof

	[[ " $AGE_BUCKETS " == *" $days "* ]] || return 1
	real_path=$(realpath "$index_path") || return 1
	dir=$real_path
	while [ -f "$dir/db.db" ]; do
		cache="$dir/$CACHE_NAME"
		if [ -f "$cache" ] && [ "$cache" -nt "$dir/db.db" ]; then
			rel=${real_path#"$dir"}
			rel=${rel#/}
			depth=0
			[ -n "$rel" ] && depth=$(($(tr -cd / <<< "$rel" | wc -c) + 1))
			if [ $((depth + levels_below)) -le "$CACHE_DEPTH" ]; then
				DIRSTATS=$cache
				DIRSTATS_REL=$rel
				asof=$($QUERYDBS -V asof asof "SELECT MAX(midnight) FROM vasof;" \
					"$cache" | grep -o '^[0-9]*')
				echo "Using sums cached $(date -r "$cache" '+%Y-%m-%d %H:%M') in $dir"
				echo "Ages count back from $(date -u -d "@$asof" "+%F %H:%M") UTC, when the sums were made"
				echo "(set GUFI_CACHE=0 to walk the index again)"
				echo ""
				return 0
			fi
		fi
		[ "$dir" = / ] && break
		dir=$(dirname "$dir")
	done
	return 1
}

# the days columns a walk computes: every bucket plus the requested days
age_columns () {
	local days=$1

	echo $AGE_BUCKETS
	[[ " $AGE_BUCKETS " == *" $days "* ]] || echo "$days"
}

# walk the index once, summing files by directory and owner
#
# Each directory's row is keyed by its path relative to the index argument,
# cut to CACHE_DEPTH components, so the result stays small however deep the
# tree goes.  Files directly in the index argument get the key ''.  Column
# oldN holds the bytes last accessed more than N days before midnight UTC
# today, and table asof records that midnight for later readers of a cache.
dirstats_walk () {
	local index_path=$1
	local days=$2
	local real_path midnight_epoch column_defs column_sums column_totals age

	# gufi_query reports fpath() as a realpath
	real_path=$(realpath "$index_path") || exit 1
	real_path=${real_path//\'/\'\'}

	# midnight UTC, the same cutoff the old datetime() < DATE('now') test used
	midnight_epoch=$(date -u -d "$(date -u +%F)" +%s)
	for age in $(age_columns "$days"); do
		column_defs="$column_defs, old$age int64"
		column_sums="$column_sums, SUM(CASE WHEN atime < $((midnight_epoch - age * 86400)) THEN size ELSE 0 END)"
		column_totals="$column_totals, SUM(old$age)"
	done

	$BFQ -n "$THREADS" \
		-I "CREATE TABLE stats (dir text, uid int64, cnt int64, bytes int64$column_defs);" \
		-E "INSERT INTO stats \
			WITH RECURSIVE cut(depth, rest, keep) AS ( \
				SELECT 0, substr(fpath(), length('$real_path') + 2) || '/', '' \
				UNION ALL \
				SELECT depth + 1, substr(rest, instr(rest, '/') + 1), \
					keep || substr(rest, 1, instr(rest, '/')) \
				FROM cut WHERE depth < $CACHE_DEPTH AND rest != '') \
			SELECT (SELECT rtrim(keep, '/') FROM cut ORDER BY depth DESC LIMIT 1), \
				uid, COUNT(*), SUM(size)$column_sums \
			FROM entries WHERE type='f' GROUP BY uid;" \
		-K "CREATE TABLE dirstats (dir text, uid int64, cnt int64, bytes int64$column_defs); \
			CREATE TABLE asof (midnight int64);" \
		-J "INSERT INTO dirstats SELECT dir, uid, SUM(cnt), SUM(bytes)$column_totals \
			FROM stats GROUP BY dir, uid; \
			INSERT INTO asof VALUES ($midnight_epoch);" \
		-O "$DIRSTATS" "$index_path"
}

# SQL for the rows at or below the requested path, with their path below it
below_requested () {
	local rel=${DIRSTATS_REL//\'/\'\'}

	echo "(SELECT *, CASE WHEN '$rel' = '' THEN dir WHEN dir = '$rel' THEN '' \
			ELSE substr(dir, length('$rel') + 2) END AS sub \
		FROM vdirstats \
		WHERE '$rel' = '' OR dir = '$rel' \
			OR substr(dir, 1, length('$rel') + 1) = '$rel' || '/')"
}

# one row per directory directly below the index argument, in find order
#
# Directories holding no files never reach the walk's results, so they are
# listed from the index itself and filled in with the row an empty sum gives.
print_dirsum () {
	local index_path=$1
	local days=$2

	echo "directory|count|sizeGB|oldsize|percent"
	awk -F '\036' -v OFS='|' '
		NR == FNR { row[$1] = $2 OFS $3 OFS $4 OFS $5; next }
		{ print $0, ($0 in row ? row[$0] : "0|(null)|(null)|00%") }' \
		<($QUERYDBS -d x -V dirstats dirstats " \
			SELECT topdir, count, sizeGB, oldsize, \
				PRINTF('%02d%%', (100*oldsize/sizeGB)) AS percent \
			FROM ( \
				SELECT substr(sub, 1, instr(sub || '/', '/') - 1) AS topdir, \
					SUM(cnt) AS count, \
					SUM(bytes)/1024/1024/1024 AS sizeGB, \
					SUM(old$days)/1024/1024/1024 AS oldsize \
				FROM $(below_requested) GROUP BY topdir) \
			WHERE topdir != '';" \
			"$DIRSTATS" | grep -v '^query returned') \
		<(find "$index_path" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
}

# one row totalling everything below the index argument
print_totals () {
	local days=$1

	$QUERYDBS -d \| -NV dirstats dirstats " \
		SELECT count, sizeGB, oldsize, \
			PRINTF('%02d%%', (100*oldsize/sizeGB)) AS percent \
		FROM ( \
			SELECT SUM(cnt) AS count, \
				SUM(bytes)/1024/1024/1024 AS sizeGB, \
				SUM(old$days)/1024/1024/1024 AS oldsize \
			FROM $(below_requested));" \
		"$DIRSTATS" | grep -v '^query returned'
}
