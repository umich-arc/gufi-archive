# GUFI Archive Scanning

We use parts of [GUFI](https://github.com/mar-file-system/GUFI/) to perform high
perfromance scanning of storage areas to make reports to better make decisions
about the archiveability of data in massive volumes.

## Singularity

Building the container on [sylabs](https://cloud.sylabs.io/tokens)

```
singularity remote login
singularity build --remote gufi.sif singularity.def 
singularity push -U  gufi.sif library://brockp/gufi/gufi:master
singularity push -U  gufi.sif library://brockp/gufi/gufi:[tag]
```

```
# running
module load singularity
singularity pull --arch amd64 library://brockp/gufi/gufi:master
singularity run-help gufi_master.sif
singularity exec gufi_master.sif cmd
```

## Reporting Scripts

```
# build an index this is time consuming but is reused for many queries
singularity exec gufi_master.sif gufi_dir2index -n <#threads> <inputdir> /tmp/GUFI

# run a summary report of how much not been accessed in X days
singularity exec --bind /etc/passwd gufi_master.sif summary.sh /tmp/GUFI [days]

# use GUFI ls to just list files
singularity exec --bind /etc/passwd gufi_master.sif gufi_ls --help
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
