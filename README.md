# GUFI Archive Scanning

We use parts of [GUFI](https://github.com/mar-file-system/GUFI/) to perform high
perfromance scanning of storage areas to make reports to better make decisions
about the archiveability of data in massive volumes.

## Container

**The Singularity definition file and the Sylabs library images
(`library://brockp/gufi/gufi`) are retired and no longer updated.**

gufi-archive is now published as a Docker / OCI image, which Singularity and
[Apptainer](https://apptainer.org) pull and run directly without root.  The
commands you already know still work; only the `pull` source changes:

```
# old (no longer updated)
singularity pull --arch amd64 library://brockp/gufi/gufi:master

# new
singularity pull gufi.sif docker://ghcr.io/umich-arc/gufi-archive:latest

# or with Apptainer
apptainer pull gufi.sif docker://ghcr.io/umich-arc/gufi-archive:latest
```

See [docker/README.md](docker/README.md) for full instructions, plain Docker
usage, published tags and building the image.

## Reporting Scripts

```
# build an index this is time consuming but is reused for many queries
singularity exec gufi.sif gufi_dir2index -n <#threads> <inputdir> /tmp/GUFI

# run a summary report of how much not been accessed in X days
singularity exec --bind /etc/passwd gufi.sif summary.sh /tmp/GUFI [days]

# use GUFI ls to just list files
singularity exec --bind /etc/passwd gufi.sif gufi_ls --help
```

### Scripts

[SCRIPTS.md](SCRIPTS.md)

 * `summary.sh /tmp/GUFI [days]` provides a summary of total and data not
   accessed in 180 days
 * `dirsum.sh /tmp/GUFI/dir [days]` Show totals in each directory below the
   given directory and files not accessed in 180 days
 * `totals.sh /tmp/GUFI/dir [days]` Summary similar to `du -s`
 * `dirtotals.sh /tmp/GUFI/dir [days]` `dirsum.sh` and `totals.sh` together
   from one read of the index instead of two.
 * `archivescan.sh /tmp/GUFI/dir [sizeMB]` Bucket data into over size and under.

### Threads

`dirsum.sh`, `totals.sh` and `dirtotals.sh` run 8 threads. Set `GUFI_THREADS`
to change that, for example `GUFI_THREADS=32 dirtotals.sh /tmp/GUFI`. An index
on spinning disk is limited by seeks rather than CPU, and more threads keep
more reads queued for the drive to reorder.

### Drill-down cache

The first `dirsum.sh`, `totals.sh` or `dirtotals.sh` on an index walks all of
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

### Resolving groups and users

The continer doesn't know about UID's and groups other than the user invoking
it. To correctly resolve the UID and GID's stored in the GUFI index you need to
bind the local system to the container runtime with `--bind /etc/passwd`

### Using GUFI-Shell gufish, a shell front-end to all this

A simple way to use the GUFI Archive Scanning container and reports
is via the gufish script here.  Make sure you have singularity or
apptainer installed.  Run this Bash script without arguments for usage.
Run it with a directory as an argument to index that directory and
enter your regular bash shell with additional commands to run reports
on the index.

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
