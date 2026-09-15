import fs from 'node:fs';
const project='ios/App/App.xcodeproj/project.pbxproj';
fs.writeFileSync(project,fs.readFileSync(project,'utf8').replaceAll('IPHONEOS_DEPLOYMENT_TARGET = 15.0','IPHONEOS_DEPLOYMENT_TARGET = 16.0'));
const plist='ios/App/App/Info.plist';
fs.writeFileSync(plist,fs.readFileSync(plist,'utf8').replace('<string>armv7</string>','<string>arm64</string>').replace('<string>en</string>','<string>zh_CN</string>').replace('<key>LSRequiresIPhoneOS</key>','<key>UIUserInterfaceStyle</key>\n\t<string>Light</string>\n\t<key>LSRequiresIPhoneOS</key>'));
