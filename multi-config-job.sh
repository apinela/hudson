set -- "$ROM"
IFS="-";declare -a Array=($*)
export ROM=${Array[0]}
export VERSION=${Array[1]}
export REPO_BRANCH=${ROM}-${VERSION}
export REPO_SYNC=true
export BUILD_TARGETS=otapackage
export CLEAN=true
export LUNCH=${ROM}_${DEVICE}-${TYPE}
rm -rf hudson/ build_env/
chmod a+x job.sh
./job.sh