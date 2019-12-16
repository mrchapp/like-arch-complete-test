#!/usr/bin/env bash

set -e
#set -x
set -u

env
echo
[ ! -v GIT_DESCRIBE ] && [ -v LATEST_SHA ] && GIT_DESCRIBE="${LATEST_SHA:0:12}"
echo "git describe: [$GIT_DESCRIBE]"

if [[ -v HUDSON_COOKIE ]] || [[ -v CI ]]; then
  SUDO=$(which sudo ||:)
  ${SUDO} pip3 install jinja2-cli requests ruamel.yaml
  ${SUDO} apt update
  ${SUDO} apt install -yqq --no-install-recommends jq
  DRY_RUN=""
else
  DRY_RUN="--dry-run"
fi
export DRY_RUN

if [[ -v HUDSON_COOKIE ]] || [[ -v CI ]]; then
  WORKDIR="${WORKSPACE:-${CI_PROJECT_DIR}}"
else
  WORKDIR="$(dirname "$(readlink -e "$0")")/workspace"
fi
mkdir -p "${WORKDIR}"

if [ ! -d "${WORKDIR}/lava-test-plans" ]; then
  git clone -o origin https://github.com/linaro/lava-test-plans "${WORKDIR}/lava-test-plans"
else
  if [ -v GIT_SYNC ]; then
    (cd "${WORKDIR}/lava-test-plans" && git fetch origin && git reset --hard origin/master)
  fi
fi

# Generate and submit tests
# $1: Location of variables.ini file
# This argument is required.
generate_submit_tests() {
  cd "${WORKDIR}/lava-test-plans"
  set -x
  python3 "${WORKDIR}/lava-test-plans/submit_for_testing.py" \
    ${DRY_RUN} \
    --variables "${WORKDIR}/variables.ini" \
    --device-type "${DEVICE_TYPE}" \
    --build-number "${GIT_DESCRIBE}" \
    --lava-server "${LAVA_SERVER}" \
    --qa-server https://qa-reports.linaro.org \
    --qa-server-team staging-lkft \
    --qa-server-project "${QA_PROJECT}" \
    --test-plan "${LKFT_TEST_PLAN}"
  set +x
}

# Create variables.ini for the specified MACHINE
# $1: MACHINE to create the variables.ini for
# This argument is required.
#
# This variables affect the produced variables.ini:
#   ARCH_ARTIFACTS

create_vars_for_machine() {
  echo
  echo "====================================================="
  echo "Now submitting jobs for ${MACHINE^^}"
  unset DEVICE_TYPE
  unset ROOTFS_FILENAME
  unset ROOTFS_PUB_DEST
  unset BOOT_IMG_FILENAME

  LAVA_SERVER=https://lkft.validation.linaro.org/RPC2/
  ROOTFS_BUCKET="storage.staging.lkft.org"
  ROOTFS_RELEASE_PUB_DEST="rootfs/oe-lkft-sumo"
  ROOTFS_BUILDNR_PUB_DEST="62"
  ROOTFS_PUB_DEST="${ROOTFS_RELEASE_PUB_DEST}/${MACHINE}/${ROOTFS_BUILDNR_PUB_DEST}"
  GCC_VER_PUB_DEST="gcc-8"
  KERNEL_NAME=Image
  QA_PROJECT="linux-mainline-oe"
  LKFT_TEST_PLAN="lkft-sanity"
  DTB_FILENAME=
  BOOT_URL=
  TAGS=
  BOOT_LABEL=
  ROOTFS_URL=

  if [[ -v GITLAB_CI ]]; then
    DOWNLOAD_URL="$(jq .download_url build.json | tr -d \")"
    # The URL ends with /, so remove the last one
    ARCH_ARTIFACTS="$(echo ${DOWNLOAD_URL} | cut -d/ -f1-4)"
    BUILD_URL="${CI_PIPELINE_URL}"
    KERNEL_DEFCONFIG_URL="${DOWNLOAD_URL}/kernel.conf"
    BUILD_NUMBER="${CI_BUILD_ID}"
    BASE_URL=$(echo "${DOWNLOAD_URL}" | cut -d/ -f1-3)
    PUB_DEST=$(echo "${DOWNLOAD_URL}" | cut -d/ -f4-)
    case "${REPO_NAME}" in
      mainline)
        QA_PROJECT="linux-mainline-oe"
        ;;
      next)
        QA_PROJECT="linux-next-oe"
        ;;
      stable-rc)
        major_version=$(echo ${GIT_BRANCH#linux-*} | cut -d. -f1-2)
        QA_PROJECT="linux-stable-rc-${major_version}-oe"
        ;;
    esac
  else
    S3_BUCKET="storage.staging.lkft.org"
    PUB_DEST="${TREE_NAME}/${BRANCH}/${GIT_DESCRIBE}"
    KERNEL_DEFCONFIG_URL="http://${S3_BUCKET}/${PUB_DEST}/${BUILD_NUMBER}/defconfig"
    BASE_URL=http://${S3_BUCKET}

    # default ARCH_ARTIFACTS to arm64
    ARCH_ARTIFACTS="${BASE_URL}/${PUB_DEST}/${ARCH}/defconfig%2Blkft/${GCC_VER_PUB_DEST}"
    case "${ARCH}" in
      arm)
        ARCH_ARTIFACTS="http://${S3_BUCKET}/${PUB_DEST}/${ARCH}/multi_v7_defconfig%2Blkft/${GCC_VER_PUB_DEST}"
        ;;
      i386)
        ARCH_ARTIFACTS="http://${S3_BUCKET}/${PUB_DEST}/${ARCH}/i386_defconfig%2Blkft/${GCC_VER_PUB_DEST}"
        ;;
      x86_64)
        ARCH_ARTIFACTS="http://${S3_BUCKET}/${PUB_DEST}/${ARCH}/x86_64_defconfig%2Blkft/${GCC_VER_PUB_DEST}"
        ;;
    esac
  fi

  case "${MACHINE}" in
  dragonboard-410c)
    # Qualcomm's Dragonboard 410c
    DEVICE_TYPE=dragonboard-410c
    DTB_FILENAME=dtbs/qcom/apq8016-sbc.dtb
    BOOT_IMG_FILENAME=boot--5.2+git0+0ecfebd2b5-r0-dragonboard-410c-20190910203807.img
    ROOTFS_FILENAME=rpb-console-image-lkft-dragonboard-410c-20190923201628.rootfs.ext4.gz
    BOOT_URL=http://${ROOTFS_BUCKET}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
    TAGS="[old-firmware]"
    BOOT_OS_PROMPT='dragonboard-410c:'
    ;;
  hikey)
    # HiKey
    DEVICE_TYPE=hi6220-hikey
    DTB_FILENAME=dtbs/hisilicon/hi6220-hikey.dtb
    BOOT_IMG_FILENAME=boot-0.0+AUTOINC+2d8c108bf0-ed8112606c-r0-hikey-20190911025241.uefi.img
    ROOTFS_FILENAME=rpb-console-image-lkft-hikey-20190923201702.rootfs.ext4.gz
    BOOT_URL=http://${ROOTFS_BUCKET}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
    BOOT_OS_PROMPT='hikey:~'
    ;;
  juno)
    # Arm's Juno
    DEVICE_TYPE=juno-r2
    DTB_FILENAME=dtbs/arm/juno-r2.dtb
    ROOTFS_FILENAME=rpb-console-image-lkft-juno-20190923201430.rootfs.tar.xz
    BOOT_OS_PROMPT=''
    ;;
  ls2088a)
    # NXP's LS2088A RDB
    DEVICE_TYPE=nxp-ls2088
    DTB_FILENAME=dtbs/freescale/fsl-ls2088a-rdb.dtb
    ROOTFS_FILENAME=rpb-console-image-lkft-ls2088ardb-20191019001216.rootfs.tar.xz
    ROOTFS_URL=http://people.linaro.org/~daniel.diaz/lkft-nxp/images/${ROOTFS_FILENAME}
    #LAVA_SERVER=http://59.144.98.45/RPC2/
    LAVA_SERVER=nxp
    BOOT_OS_PROMPT=''
    LKFT_TEST_PLAN="lkft-full"
    ;;
  am57xx-evm)
    # am57xx-evm
    DEVICE_TYPE=x15
    KERNEL_NAME=zImage
    DTB_FILENAME=dtbs/am57xx-beagle-x15.dtb
    ROOTFS_FILENAME=rpb-console-image-lkft-am57xx-evm-20190923201632.rootfs.ext4.gz
    KERNEL_URL=${ARCH_ARTIFACTS}/${KERNEL_NAME}
    BOOT_URL=${KERNEL_URL}
    BOOT_OS_PROMPT='root@am57xx-evm:'
    BOOT_LABEL="kernel"
    ;;
  intel-corei7-64)
    # intel-corei7-64
    DEVICE_TYPE=x86
    KERNEL_NAME=bzImage
    ROOTFS_FILENAME=rpb-console-image-lkft-intel-corei7-64-20190923201627.rootfs.tar.xz
    KERNEL_URL=${ARCH_ARTIFACTS}/${KERNEL_NAME}
    BOOT_URL=${KERNEL_URL}
    BOOT_OS_PROMPT='root@intel-corei7-64:'
    ;;
  intel-core2-32)
    # intel-core2-32
    DEVICE_TYPE=i386
    KERNEL_NAME=bzImage
    ROOTFS_FILENAME=rpb-console-image-lkft-intel-core2-32-20190923201631.rootfs.tar.xz
    KERNEL_URL=${ARCH_ARTIFACTS}/${KERNEL_NAME}
    BOOT_URL=${KERNEL_URL}
    BOOT_OS_PROMPT='root@intel-core2-32:'
    ;;
  esac

  KERNEL_URL=${ARCH_ARTIFACTS}/${KERNEL_NAME}
  MODULES_URL=${ARCH_ARTIFACTS}/modules.tar.xz
  [[ -z ${ROOTFS_URL} ]] && ROOTFS_URL=http://${ROOTFS_BUCKET}/${ROOTFS_PUB_DEST}/${ROOTFS_FILENAME}

  cat <<EOF >"${WORKDIR}/variables.ini"
DEVICE_TYPE=${DEVICE_TYPE}
BASE_URL=${BASE_URL}
PUB_DEST=${PUB_DEST}
BUILD_NUMBER=${BUILD_NUMBER}
BUILD_URL=${BUILD_URL}
KERNEL_URL=${KERNEL_URL}
MODULES_URL=${MODULES_URL}
KERNEL_CONFIG_URL=${ARCH_ARTIFACTS}/kernel.config
#
KERNEL_DESCRIBE=${GIT_DESCRIBE}
KERNEL_COMMIT=${GIT_DESCRIBE}
# we don't have this:
MAKE_KERNELVERSION=5.4-rc8
KERNEL_VERSION=mainline
KERNEL_BRANCH=mainline
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
KERNEL_DEFCONFIG_URL=${KERNEL_DEFCONFIG_URL}
# juno/ls2088a:
ROOTFS_URL=${ROOTFS_URL}
# hikey:
BOOT_URL=${BOOT_URL}
# common, need adjustment per project:
PROJECT_NAME=linux-mainline-oe
KSELFTEST_PATH=/opt/kselftests/mainline/
LAVA_JOB_PRIORITY=72
TDEFINITIONS_REVISION=master
LXC_PTABLE_FILE=ptable-linux-8g.img
LXC_BOOT_FILE=boot.img
LXC_ROOTFS_FILE=rpb-console-image-lkft.rootfs.img
PROJECT=lkft-
DEPLOY_OS=oe
EOF
  [[ -n ${TAGS} ]] && echo "TAGS=${TAGS}" >>"${WORKDIR}/variables.ini"
  [[ -n ${BOOT_OS_PROMPT} ]] && echo "BOOT_OS_PROMPT=${BOOT_OS_PROMPT}" >>"${WORKDIR}/variables.ini"
  [[ -n ${BOOT_LABEL} ]] && echo "BOOT_LABEL=${BOOT_LABEL}" >>"${WORKDIR}/variables.ini"
  [[ -n ${DTB_FILENAME} ]] && echo "DTB_URL=${ARCH_ARTIFACTS}/${DTB_FILENAME}" >>"${WORKDIR}/variables.ini"
  echo
  echo "---vvv------variables.ini------vvv---"
  cat "${WORKDIR}/variables.ini"
  echo "---^^^------variables.ini------^^^---"

  generate_submit_tests "${WORKDIR}/variables.ini"
}

if [ -v board ]; then
  MACHINE="${board}"
  case "${board}" in
    db410c) MACHINE="dragonboard-410c" ;;
    i386)   MACHINE="intel-core2-32" ;;
    x15)    MACHINE="am57xx-evm" ;;
    x86_64) MACHINE="intel-corei7-64" ;;
  esac

  create_vars_for_machine "${MACHINE}"

  # We're done here. Thank you, come again.
  exit 0
fi

# arm64 boards: juno, ls2088a, hikey, db410c
# arm32 boards: am57xx-evm
#for MACHINE in juno ls2088a hikey dragonboard-410c am57xx-evm; do
echo ========================== "ARCH=${ARCH}"
case "${ARCH}" in
  arm)
    for MACHINE in am57xx-evm; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
  arm64)
    for MACHINE in juno ls2088a hikey dragonboard-410c; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
  x86_64)
    for MACHINE in intel-corei7-64; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
  i386)
    for MACHINE in intel-core2-32; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
esac
