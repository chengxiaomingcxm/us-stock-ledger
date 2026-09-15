import hashlib, json, plistlib, struct, sys, zipfile
from pathlib import Path

ipa = Path(sys.argv[1])
checksum=hashlib.sha256(ipa.read_bytes()).hexdigest()
expected=ipa.with_suffix(ipa.suffix+'.sha256')
if expected.exists():
    assert expected.read_text().split()[0].lower()==checksum, 'Downloaded IPA checksum mismatch'
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, 'ZIP integrity failed'
    names = archive.namelist()
    base = 'Payload/App.app/'
    info = plistlib.loads(archive.read(base + 'Info.plist'))
    binary = archive.read(base + info['CFBundleExecutable'])
    assert struct.unpack_from('<I', binary, 0)[0] == 0xfeedfacf, 'Not a 64-bit Mach-O executable'
    assert struct.unpack_from('<I', binary, 4)[0] == 0x0100000c, 'Not an ARM64 executable'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Not a real-device build'
    assert info['CFBundleIdentifier'] == 'com.personal.stockledger'
    assert base+'public/index.html' in names
    assert base+'PrivacyInfo.xcprivacy' in names
    config=json.loads(archive.read(base+'capacitor.config.json'))
    assert config['appId']==info['CFBundleIdentifier']
    assert not config.get('server', {}).get('url'), 'App requires an external dev server'
    print(json.dumps({'file':str(ipa),'bytes':ipa.stat().st_size,'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'bundle_id':info['CFBundleIdentifier'],'display_name':info['CFBundleDisplayName'],'version':info['CFBundleShortVersionString'],'minimum_ios':info['MinimumOSVersion'],'platform':info['CFBundleSupportedPlatforms'],'architecture':'arm64','embedded_web_assets':len([n for n in names if n.startswith(base+'public/')]),'requires_development_server':False}, ensure_ascii=False, indent=2))
