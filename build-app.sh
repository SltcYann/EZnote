#!/bin/zsh
# Compile EZnote et crée EZnote.app.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/EZnote"

APP="build/EZnote.app"
rm -rf "$APP"
# fr.lproj : les menus du système (À propos, Réglages…, Quitter) passent en français.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fr.lproj"
cp "$BIN" "$APP/Contents/MacOS/EZnote"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>EZnote</string>
    <key>CFBundleDisplayName</key><string>EZnote</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>CFBundleLocalizations</key><array><string>fr</string></array>
    <key>CFBundleIdentifier</key><string>local.eznote.app</string>
    <key>CFBundleExecutable</key><string>EZnote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>EZnote écoute le cours pour écrire ce que dit le professeur dans ton document.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>EZnote transcrit le cours sur ton Mac pour que Claude puisse ensuite l'EZifier.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Note EZnote</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key><array><string>local.eznote.note</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Texte enrichi</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.rtf</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Texte brut</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.plain-text</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>local.eznote.note</string>
            <key>UTTypeDescription</key><string>Note EZnote</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.content</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>eznote</string></array></dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Signature avec le certificat local « EZnote » s'il existe (le trousseau garde alors l'accès à la clé API
# après chaque recompilation), sinon signature ad hoc.
if security find-identity -p codesigning | grep -q '"EZnote"'; then
    codesign --force --deep --sign "EZnote" --identifier local.eznote.app "$APP"
else
    codesign --force --deep --sign - "$APP"
fi
rm -rf /Applications/EZnote.app
ditto "$APP" /Applications/EZnote.app
echo "✅ $APP prête, installée dans /Applications/EZnote.app"
