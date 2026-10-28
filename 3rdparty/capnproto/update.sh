#!/bin/bash
# Replaces upstream/ with another release of Cap'n Proto (C++). See README.md, "Updating".
#
#   ./update.sh <version> <sha256 of capnproto-c++-<version>.tar.gz>
#
# The checksum must come from a trusted place (release announcement, GitHub release); an archive
# that does not match it is refused and upstream/ stays as it is.
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <version> <sha256>" >&2
    exit 2
fi
version="$1"
sha256="$2"
here="$(cd "$(dirname "$0")" && pwd)"
url="https://capnproto.org/capnproto-c++-${version}.tar.gz"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

echo "Downloading ${url}"
curl --fail --location --silent --show-error --output "${work}/archive.tar.gz" "${url}"

echo "${sha256}  ${work}/archive.tar.gz" | sha256sum --check --quiet - || {
    echo "The checksum does not match: upstream/ is left unchanged" >&2
    exit 1
}

tar --extract --gzip --no-same-owner --file "${work}/archive.tar.gz" --directory "${work}"
source_dir="${work}/capnproto-c++-${version}"
if [ ! -f "${source_dir}/CMakeLists.txt" ] || [ ! -f "${source_dir}/src/capnp/c++.capnp" ]; then
    echo "The archive does not look like the C++ release of Cap'n Proto" >&2
    exit 1
fi

rm -rf "${here}/upstream"
mv "${source_dir}" "${here}/upstream"
echo "upstream/ is now Cap'n Proto ${version}."
echo "Next: update README.md (version, source, checksum) and 3rdparty/README.md, build, run ctest."
