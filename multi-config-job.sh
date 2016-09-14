set -- "$ROM"
IFS="-";declare -a Array=($*)
export ROM=${Array[0]}
export VERSION=${Array[1]}
export REPO_BRANCH=${ROM}-${VERSION}
export REPO_SYNC=true
export BUILD_TARGETS=otapackage
export LUNCH=${ROM}_${DEVICE}-${TYPE}
unset IFS
export ORIGINAL_WORKSPACE=$(pwd)
export ANDROID_INITIAL_BLUID_PATH=$(cd ../../../../../../;pwd)
export WORKSPACE=$ANDROID_INITIAL_BLUID_PATH
mkdir -p archive
rm -rf archive/**
cd $ANDROID_INITIAL_BLUID_PATH
cd ../android/
echo BUILD_PATH=$(pwd)
rm -rf hudson/ build_env/
rm archive/**
curl -ksO https://raw.githubusercontent.com/apinela/hudson/master/job.sh
chmod a+x job.sh
./job.sh
if [ "0" -eq "$?" ]
  then
  exit 1
fi
cd $ORIGINAL_WORKSPACE
cp -Rvf $ANDROID_INITIAL_BLUID_PATH/../android/archive/** ./archive/.
exit 0