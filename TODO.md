# TODO

## Update GUFI to a current release

The container and native builds pin GUFI to commit
`226b604f4687ac055bde16f0d59742ad472fdb44` (2022) because the reports use
that version's older CLI options. That old tree also needs an old cmake
(`module load cmake/3.22.2`) and the googletest workaround to build.

- [ ] Pick a current GUFI release tag to target
- [ ] Audit every `gufi_query` / `querydbs` invocation in `reports/*.sh`
      against the new `--help` output (flags, `-E`/`-I`/`-K`/`-J`/`-G`
      semantics, table/column names in the index schema)
- [ ] Check whether `querydbs` still exists or has been replaced
- [ ] Re-run every report against the same index on old and new GUFI and
      compare output
- [ ] Update the pinned commit in `singularity.def` and the build steps in
      `README.md`; drop the cmake module and googletest workaround if no
      longer needed
- [ ] Rebuild and push the container
