set -- "$ROM"
IFS="-";declare -a Array=($*)
export ROM=${Array[0]}
export VERSION=${Array[1]}
export REPO_BRANCH=${ROM}-${VERSION}
export REPO_SYNC=true
export BUILD_TARGETS=otapackage
export LUNCH=${ROM}_${DEVICE}-${TYPE}
echo "LUCNH=$LUNCH - $VERSION"
cd ../../../../../../
ORI_WORKSPACE=$WORKSPACE
export WORKSPACE=$(pwd)
rm -rf hudson/ build_env/
curl -ksO https://raw.githubusercontent.com/apinela/hudson/master/job.sh
chmod a+x job.sh
./job.sh
cp -Rf ../android/archive/ $ORI_WORKSPACE