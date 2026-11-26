#!/bin/bash
# Smoke test a gufi-archive container image; used locally and by CI.
#
#   docker/smoke-test.sh [image]     (default gufi-archive:test)
#
# Set DOCKER="sudo docker" if your user is not in the docker group.

set -euo pipefail

image=${1:-gufi-archive:test}
docker=${DOCKER:-docker}

echo "== tools start"
for tool in gufi_dir2index gufi_query querydbs gufi_ls; do
    # the pinned GUFI tools print usage and exit -1 (255) on --help, so judge
    # them by the usage text; 125-127 mean docker could not run the tool at all
    status=0
    out=$($docker run --rm "$image" "$tool" --help 2>&1) || status=$?
    if [ "$status" -ge 125 ] && [ "$status" -le 127 ] || ! grep -qi usage <<< "$out"; then
        echo "$out"
        echo "FAIL $tool (exit $status)"
        exit 1
    fi
    echo "ok $tool (exit $status)"
done

echo "== GUFI shared libraries resolve in the runtime stage"
# the Python wrappers in bin/ make ldd complain on stderr, which is harmless
$docker run --rm "$image" bash -c '! ldd /usr/local/bin/* 2>/dev/null | grep "not found"'

echo "== index and report round trip as a non-root user, like Apptainer"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/src/old" "$workdir/src/new"
for n in 1 2 3; do
    head -c 2048 /dev/urandom > "$workdir/src/new/file$n"
    head -c 4096 /dev/urandom > "$workdir/src/old/file$n"
done
# make half the data look unread for a year so the age columns have something
touch -a -d '400 days ago' "$workdir"/src/old/*
nfiles=6
chmod -R a+rwX "$workdir"

run() {
    $docker run --rm --user "$(id -u):$(id -g)" -v "$workdir:/data" -w /data "$image" "$@"
}

run gufi_dir2index -n 2 /data/src /data/idx
# gufi_dir2index nests the index under the source directory's name
index=/data/idx/src
test -f "$workdir/idx/src/db.db"

# the reports always exit 0, so judge them by what they print
reports=$(run bash -c 'cd /gufi-archive/reports && ls *.sh')
for report in $reports; do
    echo "-- $report"
    out=$(run "$report" "$index" 2>&1)
    echo "$out"
    if [ -z "$out" ] || grep -qiE 'cannot attach|unable to open|error' <<< "$out"; then
        echo "FAIL $report"
        exit 1
    fi
done

echo "-- summary.sh counts every indexed file"
run summary.sh "$index" 180 | tee "$workdir/summary.out"
# the row after the Path Totals heading is querydbs' column header
total=$(awk '/Path Totals/ {getline; getline; print $1; exit}' "$workdir/summary.out")
if [ "$total" != "$nfiles" ]; then
    echo "FAIL summary.sh Path Totals count is '$total', expected $nfiles"
    exit 1
fi

echo "-- totals.sh and dirtotals.sh count every indexed file"
# both print a count header then the totals row last
for report in totals.sh dirtotals.sh; do
    total=$(run "$report" "$index" 180 | awk 'NF {last = $1} END {print last}')
    if [ "$total" != "$nfiles" ]; then
        echo "FAIL $report total count is '$total', expected $nfiles"
        exit 1
    fi
    echo "ok $report ($total files)"
done

echo "-- the drill-down cache answers the same as a fresh walk"
# docker run does not pass the host environment through, so set it inside
walked=$(run env GUFI_CACHE=0 dirtotals.sh "$index" 90 | grep -v '^$')
run dirtotals.sh "$index" 180 > /dev/null
cached=$(run dirtotals.sh "$index" 90)
if ! grep -q '^Using sums cached' <<< "$cached"; then
    echo "$cached"
    echo "FAIL dirtotals.sh did not use the cache"
    exit 1
fi
if [ "$(grep -v -e '^Using sums cached' -e '^Ages count back' -e '^(set GUFI_CACHE' -e '^$' <<< "$cached")" != "$walked" ]; then
    echo "$cached"
    echo "FAIL cached dirtotals.sh differs from a walk"
    exit 1
fi
echo "ok cache matches walk"

echo "-- a cache from an earlier day is still used, with its own date"
touch -d '3 days ago' "$workdir/idx/src/db.db"
touch -d '2 days ago' "$workdir"/idx/src/.gufi-archive-cache-*
cached=$(run totals.sh "$index" 90)
if ! grep -q '^Using sums cached' <<< "$cached" ||
    ! grep -q "^Ages count back from $(date -u +%F)" <<< "$cached"; then
    echo "$cached"
    echo "FAIL totals.sh did not use the older cache"
    exit 1
fi
echo "ok two-day-old cache used, ages still from the day it was made"

echo "-- gufish inside the image runs GUFI directly"
out=$($docker run --rm -i --user "$(id -u):$(id -g)" -v "$workdir:/data" -w /data \
    "$image" gufish -q /data/src <<< 'gufi info | grep "^Running"; gufi totals 180; exit' 2>&1)
total=$(awk '/^count/ {getline; last = $1} END {print last}' <<< "$out")
if [ "$total" != "$nfiles" ] || ! grep -q '^Running GUFI with native' <<< "$out"; then
    echo "$out"
    echo "FAIL gufish in the image: count '$total', expected $nfiles, native runtime"
    exit 1
fi
echo "ok gufish native in the image ($total files)"

echo "-- gufish runs the image with the docker runtime"
# gufish calls plain docker, so only when that is what this test uses
if [ "$docker" = docker ]; then
    repo=$(cd "$(dirname "$0")/.." && pwd)
    out=$(cd "$workdir" && GUFISH_RUNTIME=docker GUFISH_PULL=never \
        GUFI_LIB="docker://$image" TMPDIR="$workdir" GUFISH_CACHE="$workdir/cache" \
        "$repo/gufish" -q "$workdir/src" <<< 'gufi totals 180; exit' 2>&1)
    total=$(awk '/^count/ {getline; last = $1} END {print last}' <<< "$out")
    if [ "$total" != "$nfiles" ]; then
        echo "$out"
        echo "FAIL gufish totals count is '$total', expected $nfiles"
        exit 1
    fi
    echo "ok gufish with docker ($total files)"
fi

echo "== all smoke tests passed"
