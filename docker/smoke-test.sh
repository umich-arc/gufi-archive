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

echo "== all smoke tests passed"
