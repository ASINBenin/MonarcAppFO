#!/bin/bash
BASE_DIR=$(pwd)

mkdir -p "$BASE_DIR/public/js/anr" "$BASE_DIR/public/css/anr" "$BASE_DIR/public/views/anr" "$BASE_DIR/public/views/dialogs"

echo "Linking ng_anr resources"
cd "$BASE_DIR/public/js/anr" && find ../../../node_modules/ng_anr/src -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/views/anr" && find ../../../node_modules/ng_anr/views -maxdepth 1 -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/css" && find ../../node_modules/ng_anr/css -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/css/anr" && find ../../../node_modules/ng_anr/css -type f -maxdepth 1 -name "*" -exec ln -sf {} . \; 2>/dev/null

echo "Linking ng_client resources"
cd "$BASE_DIR/public/js" && find ../../node_modules/ng_client/src -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/views" && find ../../node_modules/ng_client/views -type f -maxdepth 1 -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/views/dialogs" && find ../../../node_modules/ng_client/views/dialogs -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/css" && find ../../node_modules/ng_client/css -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/js" && find ../../node_modules/ng_client/po -type f -name "translations.js" -exec ln -sf {} . \; 2>/dev/null

echo "Linking ng_sign resources"
rm -rf "$BASE_DIR/public/js/sign" "$BASE_DIR/public/views/sign" "$BASE_DIR/public/css/sign"
mkdir -p "$BASE_DIR/public/js/sign" "$BASE_DIR/public/views/sign/dialogs" "$BASE_DIR/public/css/sign"

cd "$BASE_DIR/public/js/sign" && find ../../../node_modules/ng_sign/src -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/views/sign" && find ../../../node_modules/ng_sign/views -maxdepth 1 -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/views/sign/dialogs" && find ../../../../node_modules/ng_sign/views/dialogs -type f -name "*" -exec ln -sf {} . \; 2>/dev/null
cd "$BASE_DIR/public/css/sign" && find ../../../node_modules/ng_sign/css -type f -name "*" -exec ln -sf {} . \; 2>/dev/null

cd "$BASE_DIR"

if [ -d "$BASE_DIR/node_modules/ng_client" ]; then
    cd "$BASE_DIR/node_modules/ng_client"
    grunt concat
    cd "$BASE_DIR"
fi

echo "All module resources linked successfully!"