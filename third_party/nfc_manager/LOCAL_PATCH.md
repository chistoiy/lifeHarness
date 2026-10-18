# nfc_manager 本地内置（4.1.1 + 上游 4.2.1 同款修复）

来源：pub.dev `nfc_manager: 4.1.1`（未改动 Dart 侧任何代码，仅 `android/` 一处 Kotlin 修补）。

## 为什么内置而不是升级

- 4.2.1 已修该崩溃，但其 `environment.sdk: ^3.11.4`，本机 Dart 3.10.8（Flutter 侧钉版），**装不上**。
- 4.1.1 只要求 `sdk: ^3.9.2`，可装，但带崩溃缺陷。
- 结论：内置 4.1.1，只打上游 4.2.1 的那一处修复；Dart 侧零改动（pigeon 生成物差异 5000+ 行，不碰）。

## 唯一改动

`android/src/main/kotlin/dev/flutter/plugins/nfcmanager/NfcManagerPlugin.kt` 的 `onAttachedToActivity`：

```kotlin
// 4.1.1（崩溃版）
activity.applicationContext.registerReceiver(this, null, RECEIVER_NOT_EXPORTED)

// 本地（= 上游 4.2.1）
val intentFilter = IntentFilter(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED)
activity.applicationContext.registerReceiver(this, intentFilter, RECEIVER_NOT_EXPORTED)
```

## 崩溃机理（2026-10-18 真机实锤）

- 现象：点桌面 App 图标，图标放大到一半就缩回；再点一次才正常打开。**点过「记一笔」小组件后必现**。
- 点小组件 → 起独立的弹窗引擎 Activity，主界面/主引擎被系统回收 → 再点图标＝冷启动 → 走 `onAttachedToActivity`。
- `registerReceiver(this, null, ...)`：Android 14+ 的 `system_server` 在
  `BroadcastController.registerReceiverWithFeatureTraced` 里对 null filter 取 `actionsIterator()` ⇒ NPE ⇒ 主进程当场崩。
- 热启动不会重走 `onAttachedToActivity`（复用引擎），所以「第二次点击正常」。
- logcat 关键行：
  `FATAL EXCEPTION: main / NullPointerException: Attempt to invoke virtual method 'java.util.Iterator android.content.IntentFilter.actionsIterator()' on a null object reference`
  → `wm_finish_activity ... force-crash` → `am_proc_died`。

## 升级退场条件

Flutter 侧 Dart 升到 3.11.4+ 后，改回 `nfc_manager: ^4.2.1` 并删除本目录。
