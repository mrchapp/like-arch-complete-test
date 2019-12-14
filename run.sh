#!/bin/bash

ROOT_DIR="$(dirname "$(readlink -e "$0")")"
JENKINS_PARAMETERS_FILE="${1:-${ROOT_DIR}/jenkins-parameters-822.sh}"
if [ -e "${JENKINS_PARAMETERS_FILE}" ]; then
  set -a
  . "${JENKINS_PARAMETERS_FILE}"
  set +a
else
  echo "Jenkins parameters file (${JENKINS_PARAMETERS_FILE}) does not exist"
  exit 1
fi

"${ROOT_DIR}/jenkins-script.sh"
