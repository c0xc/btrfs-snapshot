btrfs-snapshot
==============

A simple snapshot rotation script for BTRFS filesystems.



Usage
-----

    # btrfs-snapshot filesystem name count

A filesystem snapshot with the specified base name will be created.
Typical snapshot base names are "hourly", "nightly", "weekly" or "monthly".
Not more than *count* snapshots are kept.
Additional snapshots with the same base name are deleted.
This means that reducing the number of snapshots in the cron job is sufficient,
they don't have to be deleted manually.

Example cron jobs:

    @hourly         /root/bin/btrfs-snapshot /data/Temp hourly 24
    @midnight       /root/bin/btrfs-snapshot /data/Temp nightly 31
    @monthly        /root/bin/btrfs-snapshot /data/Temp monthly 12
    0 0 * * 1       /root/bin/btrfs-snapshot /data/Temp weekly 4



Notes
-----

The snapshot base name may only contain letters, digits and underscores.

Snapshots are stored in the `.snapshot` directory.
This directory will be created if it doesn't exist.

This script will use `/sbin/btrfs` if it exists.
Otherwise, it will look for `btrfs` in the PATH (Debian: `/bin/btrfs`).
Use the `BTRFS` variable to specify another btrfs-progs binary:

    BTRFS=/root/bin/btrfs /root/bin/btrfs-snapshot



Author
------

Philip Seeger (philip@philip-seeger.de)



License
-------

Please see the file called LICENSE.



