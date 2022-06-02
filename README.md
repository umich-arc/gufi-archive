# GUFI Archive Scanning

We use parts of [GUFI](https://github.com/mar-file-system/GUFI/) to perform high
perfromance scanning of storage areas to make reports to better make decisions
about the archiveability of data in massive volumes.

## Building


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
