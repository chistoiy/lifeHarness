// 治理G7c4 附：只清「脚本自己造的缝」——搬运内容保持逐字节，不做全文件空行重排。
// ①reader_page 类尾拼接缝 6 空行 → 1；②sel_ops/stage 扩展花括号后的多余空行 → 删（对齐 chrome 房规）。
const fs = require('fs');
const D = 'lib/features/read/presentation/reader/';
const jobs = [
  {
    file: D + 'reader_page.dart',
    from: "  String _cfi(int ci, int pg) => '${EpubDoc.cfiPrefix}/${ci + 2}/$pg';\n\n\n\n\n\n\n}",
    to: "  String _cfi(int ci, int pg) => '${EpubDoc.cfiPrefix}/${ci + 2}/$pg';\n\n}",
  },
  {
    file: D + 'reader_sel_ops.dart',
    from: 'extension _ReaderSelOps on _ReaderPageState {\n\n',
    to: 'extension _ReaderSelOps on _ReaderPageState {\n',
  },
  {
    file: D + 'reader_stage.dart',
    from: 'extension _ReaderStage on _ReaderPageState {\n\n',
    to: 'extension _ReaderStage on _ReaderPageState {\n',
  },
];
for (const j of jobs) {
  const src = fs.readFileSync(j.file, 'utf8');
  const n = src.split(j.from).length - 1;
  if (n !== 1) {
    console.error('ANCHOR-FAIL', j.file, 'hits=' + n);
    process.exit(1);
  }
  fs.writeFileSync(j.file, src.replace(j.from, j.to));
  console.log('POLISHED', j.file);
}
