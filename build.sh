#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ]
  then
    (repo forall -c "git reset --hard") >/dev/null
    cleanup
    echo $1
    exit 1
  fi
}

function cleanup {
  rm -f .repo/local_manifests/dyn-*.xml
  rm -f .repo/local_manifests/roomservice.xml
  if [ -f $WORKSPACE/build_env/cleanup.sh ]
  then
    bash $WORKSPACE/build_env/cleanup.sh
  fi
}

if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

if [ -z "$WORKSPACE" ]
then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "$CLEAN" ]
then
  echo CLEAN not specified
  exit 1
fi

if [ -z "$REPO_HOST" ]
then
  echo REPO_HOST not specified. Using REPO_HOST=github.com/CyanogenMod/android.git
  export REPO_HOST="github.com/CyanogenMod/android.git"
fi

if [ -z "$REPO_BRANCH" ]
then
  echo REPO_BRANCH not specified
  exit 1
fi

if [ -z "$LUNCH" ]
then
  echo LUNCH not specified
  exit 1
fi

if [ -z "$RELEASE_TYPE" ]
then
  echo RELEASE_TYPE not specified
  exit 1
fi

if [ -z "$SYNC_PROTO" ]
then
  SYNC_PROTO=https
fi

if [ -z "$REPO_SYNC" ]
then
  echo REPO_SYNC not specified
  exit 1
fi


export PYTHONDONTWRITEBYTECODE=1

# colorization fix in Jenkins
export CL_RED="\"\033[31m\""
export CL_GRN="\"\033[32m\""
export CL_YLW="\"\033[33m\""
export CL_BLU="\"\033[34m\""
export CL_MAG="\"\033[35m\""
export CL_CYN="\"\033[36m\""
export CL_RST="\"\033[0m\""

cd $WORKSPACE
rm -rf archive
mkdir -p archive
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

export PATH=~/bin:$PATH

export USE_CCACHE=1
export CCACHE_NLEVELS=4
export BUILD_WITH_COLORS=0

REPO=$(which repo)
if [ -z "$REPO" ]
then
  mkdir -p ~/bin
  curl https://dl-ssl.google.com/dl/googlesource/git-repo/repo > ~/bin/repo
  chmod a+x ~/bin/repo
fi

git config --global user.name "André Pinela"
git config --global user.email "sheffzor@gmail.com"

export JENKINS_BUILD_DIR=source

mkdir -p $JENKINS_BUILD_DIR
cd $JENKINS_BUILD_DIR

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
if [ "$STABILIZATION_BRANCH" = "true" ]
then
  SYNC_BRANCH="stable/$REPO_BRANCH"
  # Temporary: Let the stab builds fallback to the mainline dependency 
  export ROOMSERVICE_BRANCHES="$REPO_BRANCH"
else
  SYNC_BRANCH=$REPO_BRANCH
fi

if [ ! -z "$RELEASE_MANIFEST" ]
then
  MANIFEST="-m $RELEASE_MANIFEST"
else
  RELEASE_MANIFEST=""
  MANIFEST=""
fi

if [ $REPO_SYNC = "true" ]
then
  rm -rf .repo/manifests*
  rm -f .repo/local_manifests/dyn-*.xml
  repo init -u $SYNC_PROTO://$REPO_HOST -b $SYNC_BRANCH $MANIFEST
  check_result "repo init failed."
fi

# make sure ccache is in PATH
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilts/misc/$(uname|awk '{print tolower($0)}')-x86/ccache"
export CCACHE_DIR=~/.ccache

if [ -f ~/.jenkins_profile ]
then
  . ~/.jenkins_profile
fi

mkdir -p .repo/local_manifests
rm -f .repo/local_manifest.xml

if [ $REPO_SYNC = "true" ]
then
  rm -rf $WORKSPACE/build_env
  git clone https://github.com/apinela/cm_build_config.git $WORKSPACE/build_env -b master
  check_result "Bootstrap failed"
fi

if [ -f $WORKSPACE/build_env/bootstrap.sh ]
then
  bash $WORKSPACE/build_env/bootstrap.sh
fi

if [ $REPO_SYNC = "true" ]
then
  cp $WORKSPACE/build_env/$REPO_BRANCH.xml .repo/local_manifests/dyn-$REPO_BRANCH.xml
  cp $WORKSPACE/build_env/shared.xml .repo/local_manifests/dyn-shared.xml
fi

echo Core Manifest:
cat .repo/manifest.xml

if [ $REPO_SYNC = "true" ]
then
  ## TEMPORARY: Some kernels are building _into_ the source tree and messing
  ## up posterior syncs due to changes
  rm -rf kernel/*
fi

if [[ "$RELEASE_TYPE" = "CM_RELEASE" || "$STABILIZATION_BRANCH" = "true" ]]
then
  if [ -f  $WORKSPACE/build_env/$REPO_BRANCH-release.xml ]
  then
    cp -f $WORKSPACE/build_env/$REPO_BRANCH-release.xml .repo/local_manifests/dyn-$REPO_BRANCH.xml
  fi
fi

if [ $REPO_SYNC = "true" ]
then
  echo Syncing...
  repo sync -d -c --force-sync > /dev/null
  check_result "repo sync failed."
  echo Sync complete.
fi

if [ -f $WORKSPACE/hudson/$REPO_BRANCH-setup.sh ]
then
  $WORKSPACE/hudson/$REPO_BRANCH-setup.sh
fi

if [ -f .last_branch ]
then
  LAST_BRANCH=$(cat .last_branch)
else
  echo "Last build branch is unknown, assume clean build"
  LAST_BRANCH=$REPO_BRANCH-$RELEASE_MANIFEST
fi

if [ "$LAST_BRANCH" != "$REPO_BRANCH-$RELEASE_MANIFEST" ]
then
  echo "Branch has changed since the last build happened here. Forcing cleanup."
  CLEAN="true"
fi

. build/envsetup.sh
# Workaround for failing translation checks in common hardware repositories
if [ ! -z "$GERRIT_XLATION_LINT" ]
then
    LUNCH=$(echo $LUNCH@$DEVICEVENDOR | sed -f $WORKSPACE/hudson/shared-repo.map)
fi

lunch $LUNCH
check_result "lunch failed."

# save manifest used for build (saving revisions as current HEAD)

# include only the auto-generated locals
TEMPSTASH=$(mktemp -d)
mv .repo/local_manifests/* $TEMPSTASH
mv $TEMPSTASH/roomservice.xml .repo/local_manifests/ 2>/dev/null

# save it
repo manifest -o $WORKSPACE/archive/manifest.xml -r

# restore all local manifests
mv $TEMPSTASH/* .repo/local_manifests/ 2>/dev/null
rmdir $TEMPSTASH

rm -f $OUT/cm-*.zip*

UNAME=$(uname)

if [ ! -z "$BUILD_USER_ID" ]
then
  export RELEASE_TYPE=CM_EXPERIMENTAL
fi

export SIGN_BUILD=false

if [ "$RELEASE_TYPE" = "CM_NIGHTLY" ]
then
  export CM_NIGHTLY=true
elif [ "$RELEASE_TYPE" = "CM_EXPERIMENTAL" ]
then
  export CM_EXPERIMENTAL=true
elif [ "$RELEASE_TYPE" = "CM_RELEASE" ]
then
  export CM_RELEASE=true
  if [ "$SIGNED" = "true" ]
  then
    SIGN_BUILD=true
  fi
elif [ "$RELEASE_TYPE" = "CM_SNAPSHOT" ]
then
  export CM_SNAPSHOT=true
  if [ "$SIGNED" = "true" ]
  then
    SIGN_BUILD=true
  fi
fi

if [ ! -z "$CM_EXTRAVERSION" ]
then
  export CM_EXPERIMENTAL=true
fi

if [ ! -z "$GERRIT_CHANGES" ]
then
  export CM_EXPERIMENTAL=true
  IS_HTTP=$(echo $GERRIT_CHANGES | grep http)
  if [ -z "$IS_HTTP" ]
  then
    python $WORKSPACE/hudson/repopick.py $GERRIT_CHANGES
    check_result "gerrit picks failed."
  else
    python $WORKSPACE/hudson/repopick.py $(curl $GERRIT_CHANGES)
    check_result "gerrit picks failed."
  fi
  if [ ! -z "$GERRIT_XLATION_LINT" ]
  then
    python $WORKSPACE/hudson/xlationlint.py $GERRIT_CHANGES
    check_result "basic XML lint failed."
  fi
fi

if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "100.0" ]
then
  ccache -M 100G
fi

rm -f $WORKSPACE/changecount
WORKSPACE=$WORKSPACE LUNCH=$LUNCH bash $WORKSPACE/hudson/changes/buildlog.sh 2>&1
if [ -f $WORKSPACE/changecount ]
then
  CHANGE_COUNT=$(cat $WORKSPACE/changecount)
  rm -f $WORKSPACE/changecount
  if [ $CHANGE_COUNT -eq "0" ]
  then
    echo "Zero changes since last build, aborting"
    exit 1
  fi
fi

LAST_CLEAN=0
if [ -f .clean ]
then
  LAST_CLEAN=$(date -r .clean +%s)
fi
TIME_SINCE_LAST_CLEAN=$(expr $(date +%s) - $LAST_CLEAN)
# convert this to hours
TIME_SINCE_LAST_CLEAN=$(expr $TIME_SINCE_LAST_CLEAN / 60 / 60)
if [ $TIME_SINCE_LAST_CLEAN -gt "24" -o $CLEAN = "true" ]
then
  echo "Cleaning!"
  touch .clean
  make clobber
else
  echo "Skipping clean: $TIME_SINCE_LAST_CLEAN hours since last clean."
fi

echo "$REPO_BRANCH-$RELEASE_MANIFEST" > .last_branch

if [ $BOOT_IMAGE_ONLY = "true" ]
then
  time mka bootimage
else
  if [ ! -z "$JOBS" ]
  then
    time make -j$JOBS bacon recoveryimage
    check_result "Build failed."
  else
    time mka bacon recoveryimage
    check_result "Build failed."
  fi
fi

if [ "$SIGN_BUILD" = "true" ]
then
  MODVERSION=$(cat $OUT/system/build.prop | grep ro.cm.version | cut -d = -f 2)
  if [ ! -z "$MODVERSION" -a -f $OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files-$BUILD_NUMBER.zip ]
  then
    if [ -s $OUT/ota_script_path ]
    then
        OTASCRIPT=$(cat $OUT/ota_script_path)
    else
        OTASCRIPT=./build/tools/releasetools/ota_from_target_files
    fi
    ./build/tools/releasetools/sign_target_files_apks -e Term.apk= -d vendor/cm-priv/keys $OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files-$BUILD_NUMBER.zip $OUT/$MODVERSION-signed-intermediate.zip
    $OTASCRIPT -k vendor/cm-priv/keys/releasekey $OUT/$MODVERSION-signed-intermediate.zip $WORKSPACE/archive/cm-$MODVERSION-signed.zip
    if [ "$FASTBOOT_IMAGES" = "true" ]
    then
       ./build/tools/releasetools/img_from_target_files $OUT/$MODVERSION-signed-intermediate.zip $WORKSPACE/archive/cm-$MODVERSION-fastboot.zip
    fi
    rm -f $OUT/ota_script_path
  else
    echo "Unable to find target files to sign"
    exit 1
  fi
else
  for f in $(ls $OUT/cm-*.zip*)
  do
    ln $f $WORKSPACE/archive/$(basename $f)
  done
fi
if [ -f $OUT/utilties/update.zip ]
then
  cp $OUT/utilties/update.zip $WORKSPACE/archive/recovery.zip
fi
if [ -f $OUT/recovery.img ]
then
  cp $OUT/recovery.img $WORKSPACE/archive
fi

if [ -f $OUT/boot.img ]
then
  cp $OUT/boot.img $WORKSPACE/archive
fi

# archive the build.prop as well
ZIP=$(ls $WORKSPACE/archive/cm-*.zip | grep -v -- -fastboot)
unzip -p $ZIP system/build.prop > $WORKSPACE/archive/build.prop

if [ "$TARGET_BUILD_VARIANT" = "user" -a "$EXTRA_DEBUGGABLE_BOOT" = "true" ]
then
  # Minimal rebuild to get a debuggable boot image, just in case
  rm -f $OUT/root/default.prop
  DEBLUNCH=$(echo $LUNCH|sed -e 's|-user$|-userdebug|g')
  breakfast $DEBLUNCH
  mka bootimage
  check_result "Failed to generate a debuggable bootimage"
  cp $OUT/boot.img $WORKSPACE/archive/boot-debuggable.img
fi

# Build is done, cleanup the environment
cleanup

# CORE: save manifest used for build (saving revisions as current HEAD)

# Stash away other possible manifests
TEMPSTASH=$(mktemp -d)
mv .repo/local_manifests $TEMPSTASH

repo manifest -o $WORKSPACE/archive/core.xml -r

mv $TEMPSTASH/local_manifests .repo
rmdir $TEMPSTASH

# chmod the files in case UMASK blocks permissions
chmod -R ugo+r $WORKSPACE/archive
