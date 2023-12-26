#!/bin/bash
set -ex

#
# --- Export Environment Variables for other Steps:
# You can export Environment Variables for other Steps with
#  envman, which is automatically installed by `bitrise setup`.
# A very simple example:
#envman add --key EXAMPLE_STEP_OUTPUT --value 'the value you want to share'
# Envman can handle piped inputs, which is useful if the text you want to
# share is complex and you don't want to deal with proper bash escaping:
#  cat file_with_complex_input | envman add --KEY EXAMPLE_STEP_OUTPUT
# You can find more usage examples on envman's GitHub page
#  at: https://github.com/bitrise-io/envman

#
# --- Exit codes:
# The exit code of your Step is very important. If you return
#  with a 0 exit code `bitrise` will register your Step as "successful".
# Any non zero exit code will be registered as "failed" by `bitrise`.

RESTORE='\033[0m'
RED='\033[00;31m'
YELLOW='\033[00;33m'
BLUE='\033[00;34m'
GREEN='\033[00;32m'

function color_echo {
    color=$1
    msg=$2
    echo -e "${color}${msg}${RESTORE}"
}

function echo_fail {
    msg=$1
    echo
    color_echo "${RED}" "${msg}"
    exit 1
}

function echo_warn {
    msg=$1
    color_echo "${YELLOW}" "${msg}"
}

function echo_info {
    msg=$1
    echo
    color_echo "${BLUE}" "${msg}"
}

function echo_details {
    msg=$1
    echo "  ${msg}"
}

#=======================================
# Main
#=======================================
#
# Validate parameters

echo "Building Flutter APKs"
# Flutter build generates files in android/ for building the app
pushd android
flutter build apk --flavor $build_flavor --dart-define="FLAVOR=$build_flavor"
./gradlew app:assembleAndroidTest
./gradlew app:assembleDebug -Ptarget=$integration_test_path
popd

echo_info "Configs:"
echo_details "* service_credentials_file_path: $service_account_credentials_file"
echo_details "* app_apk_path: $apk_path"
echo_details "* project: $project_id"
echo_details "* build_flavor: $build_flavor"
echo_details "* scheme: $scheme"
echo_details "* ios_configuration: $ios_configuration"
echo_details "* output_path: $output_path"
echo_details "* product_path: $product_path"
echo_details "* locale: $locale"
echo_details "* simulator_model: $simulator_model"
echo_details "* orientation: $orientation"
echo_details "* workspace: $workspace"
echo_details "* config_file_path: $config_file_path"

# Checking regular APK
if [ -z "${apk_path}" ] ; then
    echo_fail "The path for APK, AAB or IPA is not defined"
fi

case "${apk_path}" in
    \|\|*)
       echo_warn "The app path starts with || . Manually fixing path: ${apk_path}"
       apk_path="${apk_path:2}"
       ;;
    *\|\|)
       echo_warn "The app path ends with || . Manually fixing path: ${apk_path}"
       apk_path="${apk_path%??}"
       ;;
    \|*\|)
       echo_warn "App path starts and ends with | . Manually fixing path: ${apk_path}"
       apk_path="${apk_path:1}"
       apk_path="${apk_path%?}"
       ;;
    *\|*)
       echo_fail "App path contains | . You need to make sure only one build path is set: ${apk_path}"
       ;;
    *)
       echo_info "App path contains a file, great!! 👍"
       ;;
esac

if [ -z "${project_id}" ] ; then
    echo_fail "Firebase App ID is not defined"
fi

if [ -z "${service_account_credentials_file}" ] ; then
    echo_fail "Service Account Credential File is not defined"
fi

if [[ $service_account_credentials_file == http* ]]; then
          echo_info "Service Credentials File is a remote url, downloading it ..."
          curl $service_account_credentials_file --output credentials.json
          service_account_credentials_file=$(pwd)/credentials.json
          echo_info "Downloaded Service Credentials File to path: ${service_account_credentials_file}"
fi

if [ ! -f "${service_account_credentials_file}" ] ; then
    echo_fail "Service Account Credential path is defined but the file does not exist at path: ${service_account_credentials_file}"
fi

if [ -z "${integration_test_path}" ] ; then
    echo_fail "The path to the integration tests you'd like to deploy is not defined"
fi

##### Android Deploy #####
echo_info "Deploying Android Tests to Firebase"


pushd android
if [ -z "${$BITRISE_APK_PATH}"] [&& -z "${build_flavor}" ] ; then
    echo_info "APK not found, building APK"
    flutter build apk 
elif [ -z "${$BITRISE_APK_PATH}" ] [ && ! -z "${build_flavor}" ] ; then 
    echo_info "APK not found, building APK with $build_flavor"
    flutter build apk --flavor $build_flavor
else 
    echo_info "APK is already built, moving on!"
fi

./gradlew app:assembleAndroidTest
./gradlew app:assembleDebug -Ptarget=$integration_test_path
popd

# Deploy Android Tests to Firebase
gcloud auth activate-service-account --key-file=$service_account_credentials_file
gcloud --quiet config set project $project_id
if [  -z "${BITRISE_APK_PATH}" ] ; then 
gcloud firebase test android run --async --type instrumentation \
  --app $BITRISE_APK_PATH \
  --test build/app/outputs/apk/androidTest/free/debug/app-debug-androidTest.apk \
  --timeout 2m \
  --results-dir="./"
elif [ -z "${build_flavor}" ] ; then
    gcloud firebase test android run --async --type instrumentation \
    --app build/app/outputs/flutter-apk/app-release.apk \
    --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
    --timeout 2m \
    --results-dir="./"
else
    gcloud firebase test android run --async --type instrumentation \
    --app build/app/outputs/flutter-apk/app-release.apk \
    --test build/app/outputs/apk/androidTest/$build_flavor/debug/app-$build_flavor-debug-androidTest.apk \
    --timeout 2m \
    --results-dir="./"
  
##### iOS Deploy WIP #####
#echo_info "Deploying iOS Tests to Firebase"

#flutter build ios --flavor $build_flavor --dart-define="FLAVOR=$build_flavor" $integration_test_path --release

#pushd ios
#xcodebuild build-for-testing -allowProvisioningUpdates \
#  -workspace $workspace \
#  -scheme $scheme \
#  -xcconfig $config_file_path \
#  -configuration $configuration \
#  -derivedDataPath \
# $output_path -sdk iphoneos
#popd

#pushd $product_path
#zip -r ios_tests.zip . -i Release-iphoneos Runner_iphoneos17.0-arm64.xctestrun
#popd

# Running this command asynchrounsly avoids wasting runtime on waiting for test results to come back
#gcloud firebase test ios run --async \
#    --test $product_path \
#    --device model=$simulator_model,version=$xcode_version,locale=$locale,orientation=$orientation