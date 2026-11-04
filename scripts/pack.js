// Creează dist/OrarSmart-win32-x64/OrarSmart.exe (program Windows de sine stătător)
const m = require('@electron/packager');
const packager = m.packager || m.default || m;
packager({
  dir: '.',
  name: 'OrarSmart',
  platform: 'win32',
  arch: 'x64',
  out: 'dist',
  overwrite: true,
  icon: 'build/icon.ico',
  prune: true,
  ignore: [/^\/dist/, /^\/\.tools/, /^\/scripts/, /\.bat$/i, /^\/README/],
  appCopyright: 'Echipa SmartTeam',
  win32metadata: { CompanyName: 'SmartTeam', ProductName: 'OrarSmart', FileDescription: 'OrarSmart' }
}).then(p => { console.log('Gata: ' + p.join(', ')); })
  .catch(e => { console.error(e); process.exit(1); });
