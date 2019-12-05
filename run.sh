#!/bin/bash

ARCH=arm64
if [ $# -gt 1 ]; then
  ARCH=$1
fi
export ARCH

set -a
. "$(dirname "$(readlink -e "$0")")/jenkins-parameters-741.sh"
set +a
mkdir -p "${WORKSPACE}"
./jenkins-script.sh
