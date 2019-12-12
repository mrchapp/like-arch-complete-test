#!/usr/bin/env bash

set -e
#set -x
set -u

#env
echo
echo "git describe: [$GIT_DESCRIBE]"

if [[ -v HUDSON_COOKIE ]] || [[ -v GITLAB_CI ]]; then
  sudo pip3 install jinja2-cli ruamel.yaml
  DRY_RUN=""
else
  DRY_RUN="--dry-run"
fi
export DRY_RUN

if [[ -v HUDSON_COOKIE ]] || [[ -v GITLAB_CI ]]; then
  WORKDIR="${WORKSPACE:-${CI_PROJECT_DIR}}"
else
  WORKDIR="$(dirname "$(readlink -e "$0")")/workspace"
fi

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
    --build-number "${BUILD_NUMBER}" \
    --lava-server "${LAVA_SERVER}" \
    --qa-server https://qa-reports.linaro.org \
    --qa-server-team staging-lkft \
    --qa-server-project linux-mainline-oe \
    --git-commit "${GIT_DESCRIBE}" \
    --test-plan lkft-sanity
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
  unset DTB_FILENAME
  unset ROOTFS_FILENAME
  unset ROOTFS_PUB_DEST
  unset ROOTFS_URL
  unset BOOT_IMG_FILENAME
  unset BOOT_URL

  LAVA_SERVER=https://lkft.validation.linaro.org/RPC2/
  S3_BUCKET="storage.staging.lkft.org"
  PUB_DEST="${TREE_NAME}/${BRANCH}/${GIT_DESCRIBE}"
  ROOTFS_RELEASE_PUB_DEST="rootfs/oe-lkft-sumo"
  ROOTFS_BUILDNR_PUB_DEST="62"
  ARCH_ARTIFACTS="http://${S3_BUCKET}/${PUB_DEST}/${ARCH}/defconfig%2Blkft/gcc-8"
  KERNEL_URL=${ARCH_ARTIFACTS}/Image
  MODULES_URL=${ARCH_ARTIFACTS}/modules.tar.xz

  case "${MACHINE}" in
  dragonboard-410c)
    # Qualcomm's Dragonboard 410c
    DEVICE_TYPE=dragonboard-410c
    DTB_FILENAME=dtbs/qcom/apq8016-sbc.dtb
    BOOT_IMG_FILENAME=boot--5.2+git0+0ecfebd2b5-r0-dragonboard-410c-20190910203807.img
    ROOTFS_FILENAME=rpb-console-image-lkft-dragonboard-410c-20190923201628.rootfs.ext4.gz
    ROOTFS_PUB_DEST="${ROOTFS_RELEASE_PUB_DEST}/dragonboard-410c/${ROOTFS_BUILDNR_PUB_DEST}"
    BOOT_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
    ROOTFS_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${ROOTFS_FILENAME}
    ;;
  hikey)
    # HiKey
    DEVICE_TYPE=hi6220-hikey
    DTB_FILENAME=dtbs/hisilicon/hi6220-hikey.dtb
    BOOT_IMG_FILENAME=boot-0.0+AUTOINC+2d8c108bf0-ed8112606c-r0-hikey-20190911025241.uefi.img
    ROOTFS_FILENAME=rpb-console-image-lkft-hikey-20190923201702.rootfs.ext4.gz
    ROOTFS_PUB_DEST="${ROOTFS_RELEASE_PUB_DEST}/hikey/${ROOTFS_BUILDNR_PUB_DEST}"
    BOOT_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
    ROOTFS_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${ROOTFS_FILENAME}
    ;;
  juno)
    # Arm's Juno
    DEVICE_TYPE=juno-r2
    DTB_FILENAME=dtbs/arm/juno-r2.dtb
    ROOTFS_FILENAME=rpb-console-image-lkft-juno-20190923201430.rootfs.tar.xz
    ROOTFS_PUB_DEST="${ROOTFS_RELEASE_PUB_DEST}/juno/${ROOTFS_BUILDNR_PUB_DEST}"
    ROOTFS_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${ROOTFS_FILENAME}
    BOOT_URL=
    ;;
  ls2088a)
    # NXP's LS2088A RDB
    DEVICE_TYPE=nxp-ls2088
    DTB_FILENAME=dtbs/freescale/fsl-ls2088a-rdb.dtb
    ROOTFS_FILENAME=rpb-console-image-lkft-ls2088ardb-20191019001216.rootfs.tar.xz
    ROOTFS_URL=http://people.linaro.org/~daniel.diaz/lkft-nxp/images/${ROOTFS_FILENAME}
    #LAVA_SERVER=http://59.144.98.45/RPC2/
    LAVA_SERVER=nxp
    BOOT_URL=
    ;;
  esac

  cat <<EOF >"${WORKDIR}/variables.ini"
DEVICE_TYPE=${DEVICE_TYPE}
BASE_URL=http://${S3_BUCKET}/
PUB_DEST=${PUB_DEST}
BUILD_NUMBER=${BUILD_NUMBER}
BUILD_URL=http://ci.staging.lkft.org/job/kernel-arch-complete/${BUILD_NUMBER}/
KERNEL_URL=${KERNEL_URL}
MODULES_URL=${MODULES_URL}
DTB_URL=${ARCH_ARTIFACTS}/${DTB_FILENAME}
KERNEL_CONFIG_URL=${ARCH_ARTIFACTS}/kernel.config
#
KERNEL_DESCRIBE=${GIT_DESCRIBE}
KERNEL_COMMIT=${GIT_DESCRIBE}
# we don't have this:
MAKE_KERNELVERSION=5.4-rc8
KERNEL_VERSION=mainline
KERNEL_BRANCH=mainline
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
KERNEL_DEFCONFIG_URL=http://${S3_BUCKET}/${PUB_DEST}/${BUILD_NUMBER}/defconfig
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
EOF
  echo
  echo "---vvv------variables.ini------vvv---"
  cat "${WORKDIR}/variables.ini"
  echo "---^^^------variables.ini------^^^---"

  generate_submit_tests "${WORKDIR}/variables.ini"
}

# arm64 boards: juno, ls2088a, hikey, db410c
# arm32 boards: am57xx-evm
#for MACHINE in juno ls2088a hikey dragonboard-410c am57xx-evm; do
echo ========================== "ARCH=${ARCH}"
case "${ARCH}" in
#  arm)
#    for MACHINE in am57xx-evm; do
#      create_vars_for_machine ${MACHINE}
#    done
#    ;;
  arm64)
    for MACHINE in juno ls2088a hikey dragonboard-410c; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
esac
