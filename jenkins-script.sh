#!/usr/bin/env bash

set -e
#set -x
set -u

#env
echo
echo "git describe: [$GIT_DESCRIBE]"

[ "${ARCH}" = "arm64" ] || exit 0

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

S3_BUCKET="storage.staging.lkft.org"
PUB_DEST="${TREE_NAME}/${BRANCH}/${GIT_DESCRIBE}"
ARCH_ARTIFACTS="http://${S3_BUCKET}/${PUB_DEST}/arm64/defconfig%2Blkft/gcc-8"

# arm64 boards: juno, ls2088a, hikey, db410c
for MACHINE in juno ls2088a hikey dragonboard-410c; do
  echo
  echo "====================================================="
  echo "Now submitting jobs for ${MACHINE^^}"
  unset DEVICE_TYPE
  unset KERNEL_URL
  unset DTB_FILENAME
  unset EXT4GZ_FILENAME
  unset TARXZ_FILENAME
  unset ROOTFS_PUB_DEST
  unset ROOTFS_URL
  unset BOOT_IMG_FILENAME
  unset BOOT_URL

  LAVA_SERVER=https://lkft.validation.linaro.org/RPC2/
  S3_BUCKET="storage.staging.lkft.org"
  case "${MACHINE}" in
    dragonboard-410c)
      # Qualcomm's Dragonboard 410c
      DEVICE_TYPE=dragonboard-410c
      BOOT_IMG_FILENAME=boot--5.2+git0+0ecfebd2b5-r0-dragonboard-410c-20190910203807.img
      EXT4GZ_FILENAME=rpb-console-image-lkft-dragonboard-410c-20190923201628.rootfs.ext4.gz
      DTB_FILENAME=dtbs/qcom/apq8016-sbc.dtb
      ROOTFS_PUB_DEST="rootfs/oe-lkft-sumo/dragonboard-410c/62"
      KERNEL_URL=${ARCH_ARTIFACTS}/Image
      BOOT_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
      ROOTFS_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${EXT4GZ_FILENAME}
      ;;
    hikey)
      # HiKey
      DEVICE_TYPE=hi6220-hikey
      BOOT_IMG_FILENAME=boot-0.0+AUTOINC+2d8c108bf0-ed8112606c-r0-hikey-20190911025241.uefi.img
      #ROOTFS_PUB_DEST="rootfs/oe-lkft-sumo/juno/60"
      BOOT_IMG_FILENAME=boot-0.0+AUTOINC+2d8c108bf0-ed8112606c-r0-hikey-20191127221144-2279.uefi.img
      #KERNEL_IMG_FILENAME=Image--5.4+git0+95f1fa9e34-r0-hikey-20191127221144-2279.bin
      DTB_FILENAME=dtbs/hisilicon/hi6220-hikey.dtb
      ROOTFS_IMG_FILENAME=rpb-console-image-lkft-hikey-20191127221144-2279.rootfs.img.gz
      S3_BUCKET="snapshots.linaro.org"
      ROOTFS_PUB_DEST="openembedded/lkft/lkft/sumo/hikey/lkft/linux-mainline/2279"
      BOOT_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${BOOT_IMG_FILENAME}
      #KERNEL_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${KERNEL_IMG_FILENAME}
      ROOTFS_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${ROOTFS_IMG_FILENAME}
      KERNEL_URL=${ARCH_ARTIFACTS}/Image
      ;;
    juno)
      # Arm's Juno
      DEVICE_TYPE=juno-r2
      KERNEL_URL=${ARCH_ARTIFACTS}/Image
      DTB_FILENAME=dtbs/arm/juno-r2.dtb
      TARXZ_FILENAME=rpb-console-image-lkft-juno-20190911025238.rootfs.tar.xz
      ROOTFS_PUB_DEST="rootfs/oe-lkft-sumo/juno/60"
      ROOTFS_URL=http://${S3_BUCKET}/${ROOTFS_PUB_DEST}/${TARXZ_FILENAME}
      BOOT_URL=
      ;;
    ls2088a)
      # NXP's LS2088A RDB
      DEVICE_TYPE=nxp-ls2088
      KERNEL_URL=${ARCH_ARTIFACTS}/Image
      DTB_FILENAME=dtbs/freescale/fsl-ls2088a-rdb.dtb
      TARXZ_FILENAME=rpb-console-image-lkft-ls2088ardb-20191019001216.rootfs.tar.xz
      ROOTFS_URL=http://people.linaro.org/~daniel.diaz/lkft-nxp/images/${TARXZ_FILENAME}
      #LAVA_SERVER=http://59.144.98.45/RPC2/
      LAVA_SERVER=nxp
      BOOT_URL=
      ;;
  esac

  cat << EOF > "${WORKDIR}/variables.ini"
DEVICE_TYPE=${DEVICE_TYPE}
BASE_URL=http://${S3_BUCKET}/
PUB_DEST=${PUB_DEST}
BUILD_NUMBER=${BUILD_NUMBER}
BUILD_URL=http://ci.staging.lkft.org/job/kernel-arch-complete/${BUILD_NUMBER}/
KERNEL_URL=${KERNEL_URL}
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
EOF
  echo
  echo "---vvv------variables.ini------vvv---"
  #echo "${WORKDIR}/variables.ini:"
  cat "${WORKDIR}/variables.ini"
  echo "---^^^------variables.ini------^^^---"

  # Generate and submit tests
  cd "${WORKDIR}/lava-test-plans"
  set -x
  #LTP_TESTCASES=$(find testcases/ -name ltp* | sed -e 's#^testcases/##g')
  python3 "${WORKDIR}/lava-test-plans/submit_for_testing.py" \
    ${DRY_RUN} \
    --variables "${WORKDIR}/variables.ini" \
    --device-type ${DEVICE_TYPE} \
    --build-number "${BUILD_NUMBER}" \
    --lava-server ${LAVA_SERVER} \
    --qa-server https://qa-reports.linaro.org \
    --qa-server-team staging-lkft \
    --qa-server-project linux-mainline-oe \
    --git-commit "${GIT_DESCRIBE}" \
    --test-plan lkft-sanity
  set +x
done
