import { cp, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const output = new URL('_site/', root);
await mkdir(new URL('assets/', output), { recursive: true });

for (const name of ['index.html', 'style.css', 'main.js']) {
  await cp(new URL(`site/${name}`, root), new URL(name, output));
}

// Publish the source brand assets rather than keeping a second editable copy.
for (const name of ['mark-dark.svg', 'mark-light.svg']) {
  await cp(new URL(`brand/${name}`, root), new URL(`assets/${name}`, output));
}
for (const name of ['Geist-Variable.ttf', 'OFL.txt']) {
  await cp(new URL(`apple/Cauldron/Fonts/${name}`, root), new URL(`assets/${name}`, output));
}
await writeFile(new URL('.nojekyll', output), '');

console.log(`Built ${fileURLToPath(output)}`);
