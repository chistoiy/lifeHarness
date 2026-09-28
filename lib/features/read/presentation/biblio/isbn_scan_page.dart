import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫书脊 ISBN 全屏页（保真批F2 · 原型「扫 ISBN」真机版）。
/// 命中条码即返回字符串；由调用方（书籍表单）落 ISBN 并按「ISBN 补全」设置决定是否抓取。
class IsbnScanPage extends StatefulWidget {
  const IsbnScanPage({super.key});

  @override
  State<IsbnScanPage> createState() => _IsbnScanPageState();
}

class _IsbnScanPageState extends State<IsbnScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描书脊 ISBN'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black54,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            scanWindow: const Rect.fromLTRB(0.08, 0.32, 0.92, 0.52),
            onDetect: (capture) {
              if (_done) return;
              for (final bar in capture.barcodes) {
                final code = (bar.rawValue ?? '').trim();
                if (code.length >= 8) {
                  _done = true;
                  Navigator.of(context).pop(code);
                  return;
                }
              }
            },
          ),
          // 取景框。
          const Align(
            alignment: Alignment.center,
            child: FractionallySizedBox(
              widthFactor: 0.84,
              heightFactor: 0.2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: Colors.white70, width: 2),
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.66),
            child: const Text(
              '对准书脊条形码 · 命中后自动回填',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
