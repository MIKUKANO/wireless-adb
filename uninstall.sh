#!/system/bin/sh
MODDIR=${0%/*}
touch "$MODDIR/remove"
/system/bin/sh "$MODDIR/scripts/control.sh" restore
# Keep private configuration for reinstallation; never remove unrelated data.
