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
singularity run-help gufi.sif
singularity exec gufi.sif <exe>
```

## Reporting Scripts

```
# build an index this is time consuming but is reused for many queries
gufi_dir2index -n <#threads> <inputdir> <output>

```

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
