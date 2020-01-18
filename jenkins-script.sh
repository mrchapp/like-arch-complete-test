#!/usr/bin/env bash

set -e
#set -x
set -u

env
echo
[ ! -v GIT_DESCRIBE ] && [ -v LATEST_SHA ] && GIT_DESCRIBE="${LATEST_SHA:0:12}"

lava_tests=${lava_tests:-"--test-plan lkft-sanity"}

if [[ -v HUDSON_COOKIE ]] || [[ -v CI ]]; then
  SUDO=$(command -v sudo || :)
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
    --qa-server-team "${QA_TEAM}" \
    --qa-server-project "${QA_PROJECT}" \
    ${lava_tests}
  set +x
}

# Create variables.ini for the specified MACHINE
# $1: MACHINE to create the variables.ini for
# This argument is required.
#
# This variables affect the produced variables.ini:
#   KERNEL_PUB_DEST

create_vars_for_machine() {
  echo
  echo "====================================================="
  echo "Now submitting jobs for ${MACHINE^^}"
  unset DEVICE_TYPE
  unset ROOTFS_FILENAME
  unset ROOTFS_PUB_DEST
  unset BOOT_IMG_FILENAME

  LAVA_SERVER=https://lkft.validation.linaro.org/RPC2/
  # Kernel URL may not be the same as the rootfs URL
  BASE_KERNEL_URL="http://storage.staging.lkft.org"
  BASE_ROOTFS_URL="http://storage.staging.lkft.org"
  ROOTFS_RELEASE_PUB_DEST="rootfs/oe-lkft-sumo"
  ROOTFS_BUILDNR_PUB_DEST="74"

  case "${MACHINE}" in
    qemu_arm) MACHINE_PUB_DEST=am57xx-evm ;;
    qemu_arm64) MACHINE_PUB_DEST=juno ;;
    qemu_x86_64) MACHINE_PUB_DEST=intel-corei7-64 ;;
    qemu_i386) MACHINE_PUB_DEST=intel-core2-32 ;;
    *) MACHINE_PUB_DEST=${MACHINE} ;;
  esac

  ROOTFS_PUB_DEST="${ROOTFS_RELEASE_PUB_DEST}/${MACHINE_PUB_DEST}/${ROOTFS_BUILDNR_PUB_DEST}"
  GCC_VER_PUB_DEST="gcc-8"
  KERNEL_NAME=Image
  QA_TEAM=staging-lkft
  QA_PROJECT="linux-mainline-oe"
  LKFT_TEST_PLAN="lkft-sanity"
  DTB_FILENAME=
  BOOT_URL=
  TAGS=
  BOOT_LABEL=
  ROOTFS_URL=
  MODULES_URL_COMP=
  ROOTFS_URL_COMP=
  DEPLOY_TARGET=

  if [[ -v GITLAB_CI ]]; then
    DOWNLOAD_URL="$(jq .download_url build.json | tr -d \")"
    # The URL ends with /, so remove the last one
    KERNEL_PUB_DEST="$(echo "${DOWNLOAD_URL}" | cut -d/ -f1-4)"
    BUILD_URL="${CI_PIPELINE_URL}"
    BUILD_NUMBER="${CI_BUILD_ID}"
    BASE_KERNEL_URL=$(echo "${DOWNLOAD_URL}" | cut -d/ -f1-3)
    PUB_DEST=$(echo "${DOWNLOAD_URL}" | cut -d/ -f4-)
    GIT_DESCRIBE="$(jq .git_describe build.json | tr -d \")"

    case "${REPO_NAME}" in
      mainline)
        QA_PROJECT="linux-mainline-oe"
        ;;
      next)
        QA_PROJECT="linux-next-oe"
        ;;
      stable-rc)
        major_version=$(echo "${GIT_BRANCH#linux-*}" | cut -d. -f1-2)
        QA_PROJECT="linux-stable-rc-${major_version}-oe"
        ;;
    esac
  else
    PUB_DEST="${TREE_NAME}/${BRANCH}/${GIT_DESCRIBE}"

    # default KERNEL_PUB_DEST to arm64
    KERNEL_PUB_DEST="${BASE_KERNEL_URL}/${PUB_DEST}/${ARCH}/defconfig%2Blkft/${GCC_VER_PUB_DEST}"
    case "${ARCH}" in
      arm)
        KERNEL_PUB_DEST="${BASE_KERNEL_URL}/${PUB_DEST}/${ARCH}/multi_v7_defconfig%2Blkft/${GCC_VER_PUB_DEST}"
        ;;
      i386)
        KERNEL_PUB_DEST="${BASE_KERNEL_URL}/${PUB_DEST}/${ARCH}/i386_defconfig%2Blkft/${GCC_VER_PUB_DEST}"
        ;;
      x86_64)
        KERNEL_PUB_DEST="${BASE_KERNEL_URL}/${PUB_DEST}/${ARCH}/x86_64_defconfig%2Blkft/${GCC_VER_PUB_DEST}"
        ;;
    esac
  fi

  case "${MACHINE}" in
    dragonboard-410c)
      # Qualcomm's Dragonboard 410c
      DEVICE_TYPE=dragonboard-410c
      DTB_FILENAME=dtbs/qcom/apq8016-sbc.dtb
      BOOT_IMG_FILENAME=boot--5.4+git0+219d54332a-r0-dragonboard-410c-20191216215555.img
      ROOTFS_FILENAME=rpb-console-image-lkft-dragonboard-410c-20191216215555.rootfs.ext4.gz
      BOOT_URL=${BASE_ROOTFS_URL}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
      TAGS="[old-firmware]"
      BOOT_OS_PROMPT='dragonboard-410c:'
      DEPLOY_TARGET="download"
      ;;
    hikey)
      # HiKey
      DEVICE_TYPE=hi6220-hikey
      DTB_FILENAME=dtbs/hisilicon/hi6220-hikey.dtb
      BOOT_IMG_FILENAME=boot-0.0+AUTOINC+2d8c108bf0-ed8112606c-r0-hikey-20190911025241.uefi.img
      ROOTFS_FILENAME=rpb-console-image-lkft-hikey-20191216215523.rootfs.ext4.gz
      BOOT_URL=${BASE_ROOTFS_URL}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
      BOOT_OS_PROMPT='hikey:~'
      DEPLOY_TARGET="download"
      ;;
    juno | qemu_arm64)
      # Arm's Juno
      DEVICE_TYPE=juno-r2
      DTB_FILENAME=dtbs/arm/juno-r2.dtb
      ROOTFS_FILENAME=rpb-console-image-lkft-juno-20191216215525.rootfs.tar.xz
      BOOT_OS_PROMPT=
      MODULES_URL_COMP="xz"
      ROOTFS_URL_COMP="xz"
      if [[ "${MACHINE}" == "qemu_arm64" ]]; then
        DEVICE_TYPE=qemu_arm64
        DTB_FILENAME=
        DEPLOY_TARGET="tmpfs"
        ROOTFS_FILENAME=rpb-console-image-lkft-juno-20191216215525.rootfs.ext4.gz
        ROOTFS_URL_COMP="gz"
        KERNEL_URL=${KERNEL_PUB_DEST}/${KERNEL_NAME}
        BOOT_URL=${KERNEL_URL}
      else
        LKFT_TEST_PLAN="lkft-full"
      fi
      ;;
    ls2088a)
      # NXP's LS2088A RDB
      DEVICE_TYPE=nxp-ls2088
      DTB_FILENAME=dtbs/freescale/fsl-ls2088a-rdb.dtb
      ROOTFS_FILENAME=rpb-console-image-lkft-ls2088ardb-20191019001216.rootfs.tar.xz
      ROOTFS_URL=http://people.linaro.org/~daniel.diaz/lkft-nxp/images/${ROOTFS_FILENAME}
      #LAVA_SERVER=http://59.144.98.45/RPC2/
      LAVA_SERVER=lavalab.nxp.com
      BOOT_OS_PROMPT=
      LKFT_TEST_PLAN="lkft-full"
      ;;
    am57xx-evm | qemu_arm)
      # am57xx-evm
      DEVICE_TYPE=x15
      KERNEL_NAME=zImage
      DTB_FILENAME=dtbs/am57xx-beagle-x15.dtb
      ROOTFS_FILENAME=rpb-console-image-lkft-am57xx-evm-20191216215806.rootfs.ext4.gz
      KERNEL_URL=${KERNEL_PUB_DEST}/${KERNEL_NAME}
      BOOT_URL=${KERNEL_URL}
      BOOT_OS_PROMPT='root@am57xx-evm:'
      BOOT_LABEL="kernel"
      DEPLOY_TARGET="download"
      if [[ "${MACHINE}" == "qemu_arm" ]]; then
        DEVICE_TYPE=qemu_arm
        DTB_FILENAME=
        DEPLOY_TARGET="tmpfs"
        MODULES_URL_COMP="xz"
        ROOTFS_URL_COMP="gz"
      fi
      ;;
    intel-corei7-64 | qemu_x86_64)
      # intel-corei7-64
      DEVICE_TYPE=x86
      KERNEL_NAME=bzImage
      ROOTFS_FILENAME=rpb-console-image-lkft-intel-corei7-64-20191216215547.rootfs.tar.xz
      KERNEL_URL=${KERNEL_PUB_DEST}/${KERNEL_NAME}
      BOOT_URL=${KERNEL_URL}
      BOOT_OS_PROMPT='root@intel-corei7-64:'
      MODULES_URL_COMP="xz"
      ROOTFS_URL_COMP="xz"
      if [[ "${MACHINE}" == "qemu_x86_64" ]]; then
        DEVICE_TYPE=qemu_x86_64
        DEPLOY_TARGET="tmpfs"
        ROOTFS_FILENAME=rpb-console-image-lkft-intel-corei7-64-20191216215547.rootfs.ext4.gz
        ROOTFS_URL_COMP="gz"
      fi
      ;;
    intel-core2-32 | qemu_i386)
      # intel-core2-32
      DEVICE_TYPE=i386
      KERNEL_NAME=bzImage
      ROOTFS_FILENAME=rpb-console-image-lkft-intel-core2-32-20191216215604.rootfs.tar.xz
      KERNEL_URL=${KERNEL_PUB_DEST}/${KERNEL_NAME}
      BOOT_URL=${KERNEL_URL}
      BOOT_OS_PROMPT='root@intel-core2-32:'
      MODULES_URL_COMP="xz"
      ROOTFS_URL_COMP="xz"
      if [[ "${MACHINE}" == "qemu_i386" ]]; then
        DEVICE_TYPE=qemu_i386
        DEPLOY_TARGET="tmpfs"
        ROOTFS_FILENAME=rpb-console-image-lkft-intel-core2-32-20191216215604.rootfs.ext4.gz
        ROOTFS_URL_COMP="gz"
      fi
      ;;
  esac

  KERNEL_URL=${KERNEL_PUB_DEST}/${KERNEL_NAME}

  if [[ $DEVICE_TYPE == *"qemu_"* ]]; then
    MODULES_URL=
    MODULES_URL_COMP=
  else
    MODULES_URL=${KERNEL_PUB_DEST}/modules.tar.xz
  fi

  [[ -z ${ROOTFS_URL} ]] && ROOTFS_URL=${BASE_ROOTFS_URL}/${ROOTFS_PUB_DEST}/${ROOTFS_FILENAME}

  cat <<EOF >"${WORKDIR}/variables.ini"
DEVICE_TYPE=${DEVICE_TYPE}
KERNEL_PUB_DEST=${KERNEL_PUB_DEST}
BUILD_NUMBER=${BUILD_NUMBER}
BUILD_URL=${BUILD_URL}
KERNEL_URL=${KERNEL_URL}
KERNEL_CONFIG_URL=${KERNEL_PUB_DEST}/kernel.config
#
KERNEL_DESCRIBE=${GIT_DESCRIBE}
KERNEL_COMMIT=${GIT_DESCRIBE}
# we don't have this:
MAKE_KERNELVERSION=5.4-rc8
KERNEL_VERSION=mainline
KERNEL_BRANCH=mainline
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
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
# lower priority for now:
LAVA_JOB_PRIORITY=35
EOF
  [[ -n ${TAGS} ]] && echo "TAGS=${TAGS}" >>"${WORKDIR}/variables.ini"
  [[ -n ${BOOT_OS_PROMPT} ]] && echo "BOOT_OS_PROMPT=${BOOT_OS_PROMPT}" >>"${WORKDIR}/variables.ini"
  [[ -n ${BOOT_LABEL} ]] && echo "BOOT_LABEL=${BOOT_LABEL}" >>"${WORKDIR}/variables.ini"
  [[ -n ${DTB_FILENAME} ]] && echo "DTB_URL=${KERNEL_PUB_DEST}/${DTB_FILENAME}" >>"${WORKDIR}/variables.ini"
  [[ -n ${MODULES_URL} ]] && echo "MODULES_URL=${MODULES_URL}" >>"${WORKDIR}/variables.ini"
  [[ -n ${MODULES_URL_COMP} ]] && echo "MODULES_URL_COMP=${MODULES_URL_COMP}" >>"${WORKDIR}/variables.ini"
  [[ -n ${ROOTFS_URL_COMP} ]] && echo "ROOTFS_URL_COMP=${ROOTFS_URL_COMP}" >>"${WORKDIR}/variables.ini"
  [[ -n ${DEPLOY_TARGET} ]] && echo "DEPLOY_TARGET=${DEPLOY_TARGET}" >>"${WORKDIR}/variables.ini"
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
    i386) MACHINE="intel-core2-32" ;;
    x15) MACHINE="am57xx-evm" ;;
    x86_64) MACHINE="intel-corei7-64" ;;
    qemu)
      case "${ARCH}" in
        arm) MACHINE="qemu_arm" ;;
        arm64) MACHINE="qemu_arm64" ;;
        i386) MACHINE="qemu_i386" ;;
        x86) MACHINE="qemu_x86_64" ;;
      esac
      ;;
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
    for MACHINE in am57xx-evm qemu_arm; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
  arm64)
    for MACHINE in juno ls2088a hikey dragonboard-410c qemu_arm64; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
  x86_64)
    for MACHINE in intel-corei7-64 qemu_x86_64; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
  i386)
    for MACHINE in intel-core2-32 qemu_i386; do
      create_vars_for_machine ${MACHINE}
    done
    ;;
esac
