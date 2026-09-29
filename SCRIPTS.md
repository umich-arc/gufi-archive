
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

# summary.sh

`summary.sh [days]`

Similar to `dirsum.sh` but rahter than using paths, report on data by UID, total
data held by each and total not accessed in `days` days.

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

# mdhist.sh

`mdhist.sh index [binwidth] [maxage] [user]`

Histogram bin every file by the age of its `atime`, `mtime` and `ctime` into
fixed width buckets. `binwidth` and `maxage` take a suffix (`30m`, `6h`, `7d`,
`4w`, or bare seconds) and default to `7d` and `1095d`. An optional username or
uid restricts the report to one person.

Each row holds the files aged from `ageDays` up to `ageDays` plus one bin, so
rows run newest first. Timestamps past `maxage` collect in an `older` row and
timestamps in the future get their own row. The bar tracks `ctimeCnt`.

Wide bins size a purge. Narrow bins find a sweep.

```
mdhist.sh /tmp/GUFI/path 1d 21d

ageDays  date                 atimeCnt  atimeGB  mtimeCnt  mtimeGB  ctimeCnt  ctimeGB  ctimeBar
future   -                    900       41       900       41       0         0
0.00     2026-09-23 11:56:18  415       19       0         0        0         0
1.00     2026-09-22 11:56:18  439       20       2         0        2         0
2.00     2026-09-21 11:56:18  389       18       8         0        1023      47       #
3.00     2026-09-20 11:56:18  405       18       12822     597      18707     871      ################################
4.00     2026-09-19 11:56:18  10585     490      2187      102      12373     573      #####################
5.00     2026-09-18 11:56:18  10204     473      9         0        9823      456      ################
6.00     2026-09-17 11:56:18  388       18       5         0        5         0
...
9.00     2026-09-14 11:56:18  29280     1366     28916     1350     28916     1350     ##################################################
10.00    2026-09-13 11:56:18  1511      69       1087      49       1087      49       #
...
older    -                    24558     1143     37905     1765     11905     558      ####################

----------------- Densest ctime bins (inode changes cluster here) -----------------
date                 username  files  sizeGB
2026-09-20 11:56:18  jdoe      18707  871
2026-09-19 11:56:18  jdoe      12373  573
```

Read the three counts against each other. Day 9 moved `atime`, `mtime` and
`ctime` together, which is a job writing 29k output files. Days 3 to 5 moved
`ctime` for 41k files while `mtime` barely moved, so those inodes changed
without their contents changing. The `older` row says the same thing from the
other end: 37905 files last had content written over 21 days ago but only 11905
of them have a `ctime` that old.

Rerun the suspect window at `1h` or `10m` to get the wall clock time of the
sweep, then hand it to `purgeevade.sh`.

# purgeevade.sh

`purgeevade.sh index [days] [minfiles] [user]`

Rank users by how much of their surviving data has had its timestamps reset to
sit out the purge. `days` is the purge window and defaults to 60, `minfiles`
suppresses users with fewer files than that and defaults to 1000.

Our purge takes anything not accessed in `days` days and reads both `atime` and
`ctime`, so a file survives when `MAX(atime, ctime)` falls inside the window.
`atime` and `mtime` are settable to any value through `utimensat`, which is what
`touch` uses, but no syscall writes `ctime`: the kernel stamps it on every inode
change. Every column below rests on that.

| column | meaning |
| --- | --- |
| `touchGB` | `mtime` is stale, yet `atime` and `ctime` moved together. Reading a file moves `atime` alone and leaves `ctime` back near `mtime`, so both moving as one means the inode was written, not read. `touch` and `touch -a` land here. |
| `coGB` | `atime` and `mtime` are both outside the window and only `ctime` is inside it, so the file survives purely on the `ctime` half of the policy. `touch -a -t <old date>` does this on purpose and a recursive `chmod` or `chown` does it by accident. |
| `mtGB` | `mtime` and `ctime` moved together while `atime` stayed outside the window, which is `touch` or `touch -m` on a file nobody has read in months. |
| `suspPct` | share of the user's surviving **bytes** that the three tests above claim. |
| `futCnt` | files with `atime` or `mtime` parked in the future, which never ages out. |
| `hotHr` | most files any one of the user's `ctime` hours holds, whatever the class. Scattering `atime` with `touch -a -d` hides a sweep from the tests above, but every inode still took its `ctime` the hour the sweep ran. |
| `peakHrPct` | share of the user's suspect files sitting in that one hour. |

```
purgeevade.sh /tmp/GUFI/path 60

username  files  sizeGB  survGB  touchGB  coGB  mtGB  suspPct  futCnt  hotHr  peakHrPct
jdoe      20000  927     927     927      0     0     100%     0       11558  57%
asmith    15000  698     698     0        0     698   100%     0       13516  90%
bjones    6000   279     279     0        279   0     100%     0       5093   84%
cflint    900    41      41      0        0     0     0%       900     900    0%

----------------- Busiest ctime hours (when the sweep ran) -----------------
hourEnding           username  files  suspect  suspectGB  suspPct
2026-09-19 12:55:38  asmith    13516  13516    629        100%
2026-09-18 12:55:38  jdoe      11558  11558    534        100%
2026-09-18 11:55:38  jdoe      8442   8442     392        100%
2026-09-20 11:55:38  bjones    5093   5093     237        100%
2026-09-13 12:55:38  dgarza    29245  0        0          0%

----------------- Path Totals -----------------
files  sizeGB  survGB  survPct  touchGB  coGB  mtGB  atimeEqMtime
83900  3910    3770    96%      927      279   698   36%
```

`jdoe` ran `touch -a` over a 2 year old tree, `asmith` used `touch -m`, and
`bjones` backdated `atime` so the files read as ancient while `ctime` keeps them
alive. `cflint` parked 900 files a year into the future.

`dgarza` is the control. That hour holds more files than any sweep in the list
but `suspPct` is 0%, because it was a job writing 29k outputs: `atime`, `mtime`
and `ctime` all moved together, which is what real work looks like. Always read
`suspPct` beside the file count.

## Reading the totals

`survPct` is what the purge will not reclaim. `touchGB`, `coGB` and `mtGB` say
how much of that is only surviving because its timestamps were rewritten. `coGB`
on its own is the price of having `ctime` in the policy at all.

`atimeEqMtime` is a sanity check on the filesystem rather than the users. If it
runs near 100% then `atime` is not advancing and the `atime` half of the purge
policy is inert, so check for `noatime` on the mount.

## What this cannot see

One snapshot cannot separate `touch -m` from a genuine rewrite, since both leave
`mtime` and `ctime` equal and current. Two things also produce a stale `mtime`
beside a fresh `atime` and `ctime` without anyone cheating:

 * a restore or copy that preserved timestamps (`cp -p`, `rsync -a`, `tar -xp`)
 * an append only log that has not been read in months

Neither crams thousands of files into a single hour, so check a hit against the
`ctime` hours above and against `dirsum.sh` before acting on it. Keeping last
month's index and diffing it against today's settles the rest: an inode whose
`ctime` moved while its size stayed put was swept, not written.
