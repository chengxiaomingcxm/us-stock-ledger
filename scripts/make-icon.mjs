import fs from 'node:fs';
import { createRequire } from 'node:module';
// Run with an available Sharp installation; the generated icon is committed.
const sharp = createRequire(import.meta.url)(process.argv[2] || 'sharp');
await sharp(fs.readFileSync(new URL('./icon.svg',import.meta.url))).resize(1024,1024).removeAlpha().png().toFile('ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png');
const mark = await sharp(fs.readFileSync(new URL('./icon.svg',import.meta.url))).resize(320,320).png().toBuffer();
const splash=await sharp({create:{width:2732,height:2732,channels:3,background:'#f4f6f8'}}).composite([{input:mark,gravity:'centre'}]).png().toBuffer();
for(const filename of ['splash-2732x2732.png','splash-2732x2732-1.png','splash-2732x2732-2.png']) fs.writeFileSync('ios/App/App/Assets.xcassets/Splash.imageset/'+filename,splash);
