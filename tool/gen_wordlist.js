// 从 @scure/bip39 包内词表生成 lib/core/session/bip39_zh.dart。
// 用法：node tool/gen_wordlist.js <simplified-chinese.js 路径>
// 拉取来源：https://registry.npmmirror.com/@scure/bip39/-/bip39-1.5.4.tgz（wordlists/simplified-chinese.js）
const fs = require('fs');

const file = process.argv[2];
if (!file) {
  console.error('用法: node tool/gen_wordlist.js <simplified-chinese.js>');
  process.exit(1);
}
const src = fs.readFileSync(file, 'utf8');
const m = src.match(/exports\.wordlist = `([\s\S]*?)`\.split/);
if (!m) {
  console.error('词表格式不符（exports.wordlist 模板字符串）');
  process.exit(1);
}
const words = m[1].split('\n').filter((s) => s.length > 0);
if (words.length !== 2048) {
  console.error('词数不是 2048:', words.length);
  process.exit(1);
}
const lines = [];
for (let i = 0; i < 2048; i += 16) {
  lines.push(
    '  ' + words.slice(i, i + 16).map((w) => `'${w}'`).join(', ') + ',',
  );
}
const out =
  '// BIP39 中文简体词表（2048 词，顺序 = BIP39 官方索引 0..2047）。\n' +
  '// 来源：@scure/bip39@1.5.4 wordlists/simplified-chinese.js（审计实现，npm 镜像拉取后生成）。\n' +
  '// 由 tool/gen_wordlist.js 提取生成，勿手改；改动需同步更新恢复词测试向量。\n' +
  'const List<String> bip39Zh = [\n' +
  lines.join('\n') +
  '\n];\n';
fs.writeFileSync('lib/core/session/bip39_zh.dart', out);
console.log(
  'written OK; words[0..5]:',
  words.slice(0, 6).join(' '),
  '; words[2045..]:',
  words.slice(2045).join(' '),
);

// 顺带输出测试黄金向量（entropy 全 0 的 12 词 + 派生 seed + 动态口令向量）
const c = require('crypto');
const ent = Buffer.alloc(16, 0);
const cs = c.createHash('sha256').update(ent).digest()[0] >> 4;
const bits = '0'.repeat(128) + cs.toString(2).padStart(4, '0');
const idx = [];
for (let i = 0; i < 12; i++) idx.push(parseInt(bits.slice(i * 11, (i + 1) * 11), 2));
const phrase = idx.map((i) => words[i]).join(' ');
console.log('ZERO_INDICES=' + idx.join(','));
console.log('ZERO_PHRASE=' + phrase);
console.log('ZERO_SEED=' + c.createHash('sha256').update(phrase, 'utf8').digest('hex'));
console.log(
  'PASS_GOLDEN=' +
    c
      .createHash('sha256')
      .update('2bdb0e19c144b01c7214407b7ce8f9c15f40705bcb04184b1917730e4f0bea4d:5982143')
      .digest('hex')
      .slice(0, 8),
);
