#!/bin/bash

JENKINS_PARAMETERS_FILE="${1:-$(dirname "$(readlink -e "$0")")/jenkins-parameters-822.sh}"
if [ -e "${JENKINS_PARAMETERS_FILE}" ]; then
  set -a
  . "${JENKINS_PARAMETERS_FILE}"
  set +a
else
  echo "Jenkins parameters file (${JENKINS_PARAMETERS_FILE}) does not exist"
  exit 1
fi

if [ ! -v WORKSPACE ]; then
  echo "WORKSPACE is undefined. Please set an empty WORKSPACE directory."
  exit 1
fi
mkdir -p "${WORKSPACE}"
./jenkins-script.sh
