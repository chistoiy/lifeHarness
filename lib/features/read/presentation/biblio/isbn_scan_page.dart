import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// 扫书脊 ISBN 全屏页（保真批F2 · 原型「扫 ISBN」真机版）。
/// 命中条码即返回字符串；由调用方（书籍表单）落 ISBN 并按「ISBN 补全」设置决定是否抓取。
///
/// 2026-10-29：底层从 `mobile_scanner`（bundled ML Kit，arm64 侧 4.9MB 原生库）
/// 换成 `flutter_zxing`（zxing-cpp 算法库，约 1/4 体积）。ISBN 是 EAN-13 一维码，
/// 条空宽度比规则明确，不需要神经网络模型——省下的 3.7MB 是纯冗余。
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
          ReaderWidget(
            // 只认一维码：书脊 ISBN 是 EAN-13，不放开二维码＝每帧少算一圈候选，
            // 也少误命中（读者拍到的封面二维码不该被当成 ISBN）。
            codeFormat: Format.linearCodes,
            // 中央裁剪比例：书脊条码窄而高，裁太狠会把两侧校验位切掉。
            cropPercent: 0.7,
            // 取景框自己画（下面那层），组件自带的方形框关掉，免得两层叠着。
            showScannerOverlay: false,
            showGallery: false,
            showToggleCamera: false,
            // 书脊常是曲面 + 反光：多试一轮旋转/反相，识别率比默认高。
            tryHarder: true,
            tryRotate: true,
            onScan: (Code result) async {
              if (_done || !result.isValid) return;
              final code = (result.text ?? '').trim();
              if (code.length < 8) return;
              _done = true;
              if (mounted) Navigator.of(context).pop(code);
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
          const Align(
            alignment: Alignment(0, 0.66),
            child: Text(
              '对准书脊条形码 · 命中后自动回填',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
