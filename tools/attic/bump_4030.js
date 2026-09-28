// 一次性：versionCode 4029→4030（v0.1.31-ai-fix1）。已执行过会因命中数断言报错。
const fs = require('fs');
function bump(path, from, to) {
  const s = fs.readFileSync(path, 'utf8');
  const c = s.split(from).length - 1;
  if (c !== 1) throw new Error(path + ' 命中 ' + c + ' != 1');
  fs.writeFileSync(path, s.split(from).join(to), 'utf8');
  console.log('OK', path, from, '->', to);
}
bump('pubspec.yaml', 'version: 0.1.31+4029', 'version: 0.1.31+4030');
bump('android/local.properties', 'flutter.versionCode=4029', 'flutter.versionCode=4030');
