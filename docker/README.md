# Container (Docker / Apptainer / Singularity)

gufi-archive is distributed as a [Docker](https://docker.com) / OCI container
image.  It contains [GUFI](https://github.com/mar-file-system/GUFI/) (at the
commit the reports were written against) and the [reporting
scripts](../SCRIPTS.md), so no local GUFI build is needed.

The same image runs under [Apptainer](https://apptainer.org) and Singularity
without root, which is the recommended way to use it on HPC clusters.

> The previous Singularity images on the Sylabs library
> (`library://brockp/gufi/gufi`) are no longer updated.  Pull the Docker image
> instead as shown below.

## Apptainer / Singularity

Pull the image and convert it to a `.sif` file:

```
apptainer pull gufi.sif docker://ghcr.io/umich-arc/gufi-archive:latest
```

Build an index (time consuming, but reused for many reports), then run the
reports against it:

```
apptainer exec gufi.sif gufi_dir2index -n <#threads> <inputdir> /tmp/GUFI

# summary of how much data has not been accessed in [days]
apptainer exec --bind /etc/passwd gufi.sif summary.sh /tmp/GUFI [days]

# use GUFI ls to just list files
apptainer exec --bind /etc/passwd gufi.sif gufi_ls --help
```

Sites still running Singularity can use the same commands with `singularity`
in place of `apptainer`:

```
singularity pull gufi.sif docker://ghcr.io/umich-arc/gufi-archive:latest
singularity exec gufi.sif gufi_dir2index -n <#threads> <inputdir> /tmp/GUFI
singularity exec --bind /etc/passwd gufi.sif summary.sh /tmp/GUFI [days]
```

See [SCRIPTS.md](../SCRIPTS.md) and the [main README](../README.md#scripts) for
every report.  The reports write their temporary `outdb*` files to the current
directory, so run them from a directory you can write to.

Your home directory and current directory are normally bound into the container
automatically.  Bind other filesystems with `-B`, eg
`apptainer exec -B /scratch gufi.sif gufi_dir2index ...`.

### Resolving users and groups

The container only knows the user invoking it.  To resolve the UIDs and GIDs
stored in the GUFI index to names, bind the host's account database with
`--bind /etc/passwd` (add `--bind /etc/group` for group names).  Without it the
reports show numeric IDs.

## Docker

```
docker pull ghcr.io/umich-arc/gufi-archive:latest
docker run --rm ghcr.io/umich-arc/gufi-archive:latest
```

Mount the data and index at `/data` and run as your own user so the index is
not owned by root:

```
docker run --rm --user "$(id -u):$(id -g)" -v /etc/passwd:/etc/passwd:ro \
    -v "${PWD}:/data" ghcr.io/umich-arc/gufi-archive:latest \
    gufi_dir2index -n 8 /data/mydir /data/index

docker run --rm --user "$(id -u):$(id -g)" -v /etc/passwd:/etc/passwd:ro \
    -v "${PWD}:/data" ghcr.io/umich-arc/gufi-archive:latest \
    summary.sh /data/index/mydir 180
```

`gufi_dir2index` puts the index under a directory named after the source
(`/data/index/mydir`).  Point the reports there; the parent has no database
and only produces a harmless `Cannot attach database` warning.

## Published Images

Images are built, smoke tested and pushed to
[GHCR](https://github.com/umich-arc/gufi-archive/pkgs/container/gufi-archive)
automatically by GitHub Actions
([container.yml](../.github/workflows/container.yml)):

* `ghcr.io/umich-arc/gufi-archive:master` every push to `master`
* `ghcr.io/umich-arc/gufi-archive:latest` newest `master` push or non
  pre-release, whichever came last
* `ghcr.io/umich-arc/gufi-archive:v1.2.3` exact release
* `ghcr.io/umich-arc/gufi-archive:1.2` latest patch of a minor release

Pin a release tag for reproducible reports; `master` and `latest` move.

### Testing a Pull Request

Pull requests from branches in this repository also push a test image tagged
`pr-<number>` once the build and smoke tests pass.  These are for testing only,
never move `latest`, and are deleted when the pull request closes:

```
apptainer pull gufi-pr5.sif docker://ghcr.io/umich-arc/gufi-archive:pr-5
```

Pull requests from forks are built and tested but not pushed.

## Building the Image

Build from the root of the repository so the checked-out `reports/` are used:

```
docker build -f docker/Dockerfile -t gufi-archive .
docker/smoke-test.sh gufi-archive
```

GUFI is pinned to the commit in the `GUFI_COMMIT` build argument because the
reports use its older `gufi_query` / `querydbs` options.  Override it to try
another commit:

```
docker build -f docker/Dockerfile --build-arg GUFI_COMMIT=<sha> -t gufi-archive .
```

A locally built image can be converted for Apptainer without pushing it to a
registry:

```
apptainer build gufi.sif docker-daemon://gufi-archive:latest
```
