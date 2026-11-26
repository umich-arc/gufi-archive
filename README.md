# GUFI Archive Scanning

We use parts of [GUFI](https://github.com/mar-file-system/GUFI/) to perform high
perfromance scanning of storage areas to make reports to better make decisions
about the archiveability of data in massive volumes.

## Quick start: gufish

`gufish` indexes a directory and opens your usual shell with `gufi` commands
for the reports. It runs GUFI from the container for you, so all you need is
one of Apptainer, Singularity or Docker, and no root.

```
curl -fsSLO https://raw.githubusercontent.com/umich-arc/gufi-archive/master/gufish
chmod +x gufish
./gufish /path/to/scan
```

Indexing takes a while on a big tree. Then, at the `GUFI$` prompt:

```
gufi dirtotals 180          # per-directory table and totals, 180 days unread
gufi cdroot                 # cd to the scanned directory
gufi dirsum 90 somedir      # drill down: days and directory in either order
cd somedir; gufi totals 30  # inside the tree, reports cover where you are
gufi summary                # per-owner totals
gufi usage                  # every command
exit                        # deletes the index unless you ran "gufi noclean"
```

The first report reads the whole index. After that, reports on the same tree
and its subdirectories come back at once for 30, 60, 90, 120, 150, 180, 270,
365, 730, 1095 or 1826 days (see [Drill-down cache](#drill-down-cache)).
Commands can also come on standard input, for scripts:
`./gufish -q /path/to/scan <<< 'gufi dirtotals 180; exit'`.

gufish picks the first of these that works: Apptainer, Singularity
(including after `module load`), then Docker. Apptainer and Singularity
keep the image in `~/.cache/gufish` and download it again only when a new
version is published. `./gufish --help` explains everything; the settings
you are most likely to want are:

| Variable | Effect |
|---|---|
| `TMPDIR` | where the index goes (default `/tmp`); it needs room |
| `GUFISH_NTHREADS` | threads for indexing (default 8) |
| `GUFISH_RUNTIME` | `apptainer`, `singularity`, `docker` or `native` instead of the first that works |
| `GUFISH_PULL=never` | never check for a newer image, e.g. offline |
| `GUFISH_CACHE` | where the image is kept (default `~/.cache/gufish`) |
| `GUFI_LIB` | the image: another tag such as `docker://ghcr.io/umich-arc/gufi-archive:pr-8`, or a local `.sif` |

gufish is also in the image, where it runs GUFI directly, so you can get
it without git, `apptainer exec docker://ghcr.io/umich-arc/gufi-archive cat
/usr/local/bin/gufish > gufish`, or run it all in the container, binding the
directory to scan: `apptainer exec -B /scratch gufi.sif gufish /scratch/mydir`.

gufish was written by Steve Kinzler.

## Running the container directly

gufish does all of this for you. These are the underlying commands, for
scripting or for a site's own tooling.

### Getting the image

gufi-archive is published as a Docker / OCI image, which Singularity and
[Apptainer](https://apptainer.org) pull and run directly without root:

```
apptainer pull gufi.sif docker://ghcr.io/umich-arc/gufi-archive:latest

# or with Singularity
singularity pull gufi.sif docker://ghcr.io/umich-arc/gufi-archive:latest
```

See [docker/README.md](docker/README.md) for full instructions, plain Docker
usage, published tags and building the image.

### Indexing and reports

```
# build an index this is time consuming but is reused for many queries
singularity exec gufi.sif gufi_dir2index -n <#threads> <inputdir> /tmp/GUFI

# run a summary report of how much not been accessed in X days
singularity exec --bind /etc/passwd gufi.sif summary.sh /tmp/GUFI [days]

# use GUFI ls to just list files
singularity exec --bind /etc/passwd gufi.sif gufi_ls --help
```

#### Scripts

[SCRIPTS.md](SCRIPTS.md)

 * `summary.sh /tmp/GUFI [days]` provides a summary of total and data not
   accessed in 180 days
 * `dirsum.sh /tmp/GUFI/dir [days]` Show totals in each directory below the
   given directory and files not accessed in 180 days
 * `totals.sh /tmp/GUFI/dir [days]` Summary similar to `du -s`
 * `dirtotals.sh /tmp/GUFI/dir [days]` `dirsum.sh` and `totals.sh` together
   from one read of the index instead of two.
 * `archivescan.sh /tmp/GUFI/dir [sizeMB]` Bucket data into over size and under.

#### Threads

`dirsum.sh`, `totals.sh` and `dirtotals.sh` run 8 threads. Set `GUFI_THREADS`
to change that, for example `GUFI_THREADS=32 dirtotals.sh /tmp/GUFI`. An index
on spinning disk is limited by seeks rather than CPU, and more threads keep
more reads queued for the drive to reorder.

#### Drill-down cache

The first `dirsum.sh`, `totals.sh`, `dirtotals.sh` or `summary.sh` on an index walks all of
it and saves the per-directory sums in a small hidden file at the top of what
it walked (`.gufi-archive-cache-v2-depth5.db`). After that, the same reports on
that path or any directory up to 5 levels below it answer from the file in
seconds instead of walking the index again, as long as `days` is one of 30, 60,
90, 120, 150, 180, 270, 365, 730, 1095 or 1826. The output then starts with a
`Using sums cached` line.

The index is a snapshot, so the cache keeps being used on later days and its
ages count from the day it was made, which the output names. A walk counts
ages from midnight UTC today.

Anything else walks the index as before: another `days` value, a directory
deeper than the cache reaches, or an index rebuilt since the cache was made.
Nothing is off limits, it is only slower. To count ages from today instead,
walk again with `GUFI_CACHE=0`; that run does not replace the cache.

 * `GUFI_CACHE=0` (or `false`, `no`, `off`) always walks and never writes a
   cache.
 * `GUFI_CACHE_DEPTH` changes how many levels the cache keeps, 5 by default.
 * An index you cannot write to just isn't cached. Deleting the index deletes
   its cache.

#### Resolving groups and users

The continer doesn't know about UID's and groups other than the user invoking
it. To correctly resolve the UID and GID's stored in the GUFI index you need to
bind the local system to the container runtime with `--bind /etc/passwd`

## Building GUFI

GUFI as of June 2022 cannot build from
[googletest](https://github.com/mar-file-system/GUFI/issues/90)

The reports use the older CLI options of the GUFI commit pinned by
`GUFI_COMMIT` in [docker/Dockerfile](docker/Dockerfile); check out that commit
for a native build.

```
git clone https://github.com/mar-file-system/GUFI.git
cd GUFI
rm contrib/deps/googletest.tar.gz 
mkdir build
cd build
cmake ..
make
make install
```
