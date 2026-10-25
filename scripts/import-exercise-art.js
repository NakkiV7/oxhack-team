const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const names = ['wallPushup', 'inclinePushup', 'kneePushup', 'closeGripPushup', 'gluteBridge', 'reverseLunge', 'splitSquat', 'assistedSquat', 'deadBug', 'plank', 'sidePlank', 'stepJack', 'highKnees', 'mountainClimber', 'catCow', 'hipFlexorStretch', 'singleLegBalance'];
(async () => {
  for (const name of names) {
    const source = path.join('design/assets', `${name}.png`);
    if (!fs.existsSync(source)) continue;
    const output = path.join('Native/Resources/Assets.xcassets', `${name}.imageset`);
    fs.mkdirSync(output, { recursive: true });
    await sharp(source).trim().resize(420, 420, { fit: 'contain', background: '#00000000' }).png().toFile(path.join(output, `${name}.png`));
    fs.writeFileSync(path.join(output, 'Contents.json'), JSON.stringify({ images: [{ filename: `${name}.png`, idiom: 'universal' }], info: { author: 'xcode', version: 1 } }));
  }
})();
