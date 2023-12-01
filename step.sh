#!/bin/bash
set -ex

echo "This is the value specified for the input 'example_step_input': ${example_step_input}"

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



#=======================================
# Main
#=======================================
#
# Validate parameters
echo_info "Configs:"
echo_details "* service_credentials_file_path: $service_account_credentials_file"
echo_details "* test_apk_path: $test_apk_path"
echo_details "* app_apk_path: $apk_path"
echo_details "* project: $project_id"

echo

# Checking regular APK
if [ -z "${apk_path}" ] ; then
    echo_fail "App path for APK, AAB or IPA is not defined"
fi

case "${apk_path}" in
    \|\|*)
       echo_warn "App path starts with || . Manually fixing path: ${apk_path}"
       apk_path="${apk_path:2}"
       ;;
    *\|\|)
       echo_warn "App path ends with || . Manually fixing path: ${apk_path}"
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

if [ ! -f "${apk_path}" ] ; then
    echo_fail "App path defined but the file does not exist at path: ${apk_path}"
fi

# Checking the androidTest APK
if [ -z "${test_apk_path}" ] ; then
    echo_fail "App path for APK, AAB or IPA is not defined"
fi

case "${test_apk_path}" in
    \|\|*)
       echo_warn "App path starts with || . Manually fixing path: ${test_apk_path}"
       test_apk_path="${test_apk_path:2}"
       ;;
    *\|\|)
       echo_warn "App path ends with || . Manually fixing path: ${test_apk_path}"
       test_apk_path="${test_apk_path%??}"
       ;;
    \|*\|)
       echo_warn "App path starts and ends with | . Manually fixing path: ${test_apk_path}"
       test_apk_path="${test_apk_path:1}"
       test_apk_path="${test_apk_path%?}"
       ;;
    *\|*)
       echo_fail "App path contains | . You need to make sure only one build path is set: ${test_apk_path}"
       ;;
    *)
       echo_info "App path contains a file, great!! 👍"
       ;;
esac

if [ ! -f "${test_apk_path}" ] ; then
    echo_fail "App path defined but the file does not exist at path: ${test_apk_path}"
fi

if [ -z "${project_id}" ] ; then
    echo_fail "Firebase App ID is not defined"
fi

if [ -z "${service_account_credentials_file}" ] ; then
    echo_fail "Service Account Credential File is not found"
fi

##### Android Deploy #####

pushd android
# Flutter build generates files in android/ for building the app
flutter build apk --flavor dev --dart-define="FLAVOR=dev"
./gradlew app:assembleAndroidTest
./gradlew app:assembleDebug -Ptarget=$integration_test_path
popd

# Deploy Android Tests
gcloud auth activate-service-account --key-file=$service_account_credentials_file
gcloud --quiet config set project $project_id
gcloud firebase test android run --type instrumentation \
  --app $apk_path\
  --test $test_apk_path\
  --timeout 2m \
  --results-dir="./"
  
##### iOS Deploy WIP #####

flutter build ios --flavor dev --dart-define="FLAVOR=dev" $integration_test_path --release

pushd ios
xcodebuild build-for-testing \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -xcconfig Flutter/Release.xcconfig \
  -configuration Release \
  -derivedDataPath \
  $output -sdk iphoneos
popd

pushd $product
zip -r ios_tests.zip . -i Release-iphoneos Runner_iphoneos17.0-arm64.xctestrun
popd