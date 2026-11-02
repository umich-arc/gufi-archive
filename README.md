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
 * `archivescan.sh /tmp/GUFI/dir [sizeMB]` Bucket data into over size and under.

### Resolving groups and users

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
