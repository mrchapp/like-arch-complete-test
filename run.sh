#!/bin/bash

set -a
. "$(dirname "$(readlink -e "$0")")/jenkins-parameters-741.sh"
set +a

if [ $# -gt 1 ]; then
  ARCH=$1
fi

mkdir -p "${WORKSPACE}"
./jenkins-script.sh
