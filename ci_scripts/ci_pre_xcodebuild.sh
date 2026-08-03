echo $GOOGLE_SERVICE_INFO_PLIST | base64 -d > $CI_WORKSPACE/Omok/GoogleService-Info.plist
chmod 644 $CI_WORKSPACE/Omok/GoogleService-Info.plist
