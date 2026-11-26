#!/bin/sh
# release-tag.sh <tag>: this repo's release of a Proton-CachyOS tag, by the recipe's revision (the file
# `revision`): <tag>-armv8 at revision 1, <tag>-armv8-r<revision> after (not -armv8.<n>, which reads as
# ARMv8.n). Its tarball keeps the name proton-<tag>-armv8.tar.zst either way.
set -eu
tag=${1:?usage: release-tag.sh <tag>}
rev=$(grep -v '^#' "$(dirname "$0")/../revision" | tr -d '[:space:]')
case $rev in
    '' | *[!0-9]*) echo "release-tag.sh: revision must be a number" >&2; exit 1 ;;
esac
if [ "$rev" -le 1 ]; then
    echo "$tag-armv8"
else
    echo "$tag-armv8-r$rev"
fi
