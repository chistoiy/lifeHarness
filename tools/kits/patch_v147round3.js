/* 三轮补丁：修上一批 rulerApplyBoot 只替换前两行留下的残行（`a` 未定义）
 * 用法：node tools/kits/patch_v147round3.js [--dry] */
const fs = require('fs'), path = require('path');
const DRY = process.argv.includes('--dry');
const F = 'prototype/index-kits.html';
const raw = fs.readFileSync(path.resolve(F), 'utf8');
const nl = raw.includes('\r\n') ? '\r\n' : '\n';
const FROM = `function rulerApplyBoot(){if(!KITS.rulerDir)KITS.rulerDir='long';if(!KITS.rulerUnit)KITS.rulerUnit='cm';
 rsChips();const b=$('#rUcm');if(!b)return;
 a.classList.toggle('on',KITS.rulerDir==='long');b&&$('#rDirShort').classList.toggle('on',KITS.rulerDir==='short');
 $('#rUcm').classList.toggle('on',KITS.rulerUnit==='cm');$('#rUin').classList.toggle('on',KITS.rulerUnit==='in')}`.replace(/\n/g, nl);
const TO = `function rulerApplyBoot(){if(!KITS.rulerDir)KITS.rulerDir='long';if(!KITS.rulerUnit)KITS.rulerUnit='cm';
 rsChips();const b=$('#rUcm');if(!b)return;
 b.classList.toggle('on',KITS.rulerUnit==='cm');$('#rUin').classList.toggle('on',KITS.rulerUnit==='in');
 $('#rDirLong').classList.toggle('on',KITS.rulerDir==='long');$('#rDirShort').classList.toggle('on',KITS.rulerDir==='short')}`.replace(/\n/g, nl);
const n = raw.split(FROM).length - 1;
if (n !== 1) { console.error('!! 命中 ' + n + ' 次，零写入'); process.exit(1); }
const out = raw.replace(FROM, TO);
if (out.length < raw.length - 200 || out.length > raw.length + 200) { console.error('!! 体积异常'); process.exit(2); }
console.log('PASS rulerApplyBoot 整函数重写（残行清除）');
if (!DRY) { fs.writeFileSync(path.resolve(F), out); console.log('已写入 ' + F); } else console.log('dry-run');
