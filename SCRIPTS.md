
# totals.sh

`totals.sh [days]`

Returns total for entire path file count, total data and total data last
accessed more than `days` ago.

```
totals.sh /tmp/GUFI/path/ 365

count                     sizeGB  oldsize  percent
2115539                   149798  95928    64
```

# dirsum.sh

`dirsum.sh [days]`

Similar output to `du --max-depth=1` with totals and just data last accessed
more than `days` ago.

```
dirsum.sh /tmp/GUFI/path 180

directory                                         count    sizeGB  oldsize  percent
folder1		                                  80256    115     115      100
folder2                                           8189     1269    1269     100
folder3                                           8119     1307    1307     100
folder4                                           1098     291     207      71
```

# dirtotals.sh

`dirtotals.sh [days]`

The `dirsum.sh` table followed by the `totals.sh` row. Every report reads the
whole index, which is the slow part when the index sits on spinning disk, so
this reads it once for both.

Later runs on the same index, or on a directory up to 5 levels inside it,
answer from the drill-down cache without reading the index again. See the
[README](README.md#drill-down-cache).

```
dirtotals.sh /tmp/GUFI/path 180

directory  count    sizeGB  oldsize  percent
folder1    80256    115     115      100%
folder2    8189     1269    1269     100%
folder4    1098     291     207      71%

----------------- Path Totals -----------------
count  sizeGB  oldsize  percent
89543  1675    1591     94%
```

# summary.sh

`summary.sh [days]`

Similar to `dirsum.sh` but rahter than using paths, report on data by UID, total
data held by each and total not accessed in `days` days.

It shares the walk and [drill-down cache](README.md#drill-down-cache) with
`dirsum.sh` and `totals.sh`, so after either of those it needs no walk.

```
summary.sh /tmp/GUFI/path 180

username                  count    sizeGB  oldsize  percent
ememcard                  1988101  143653  112959   78
brockp                    127428   6145    0        0
123456                    10       0       0        (null)
```

# archivescan.sh

`archivescan.sh [size]`

Bin data into files over and under a given theashold and report count and total
size.
Used for setting activearchive configs eg 100TB Data Den, 10TB Cache space.
`size` is filesizes in MBytes.

```
archivescan.sh /tmp/GUFI/path 100

count                     sizeGB  cacheCnt  cachesizeGB  tapeCnt  tapesizeGB  archiveGBratio  archiveCntRatio
2115539                   149798  2044612   4547         70927    145250      96              3
```

96% (archiveGBratio) of data are in files larger than 100MB, but only 3% of the
files.  The cache space for files < 100MB needs to be 4547GB (4.4TBytes) plus
cahced tape files large at least.
