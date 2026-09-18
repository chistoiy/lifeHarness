# LifeHarness 主题配置规范（themes/）

主题即**设计令牌配置文件**。运行时（原型 = prototype/index.html；正式版 = Flutter `ThemeTokens.load()`）从本目录或远程仓库（GitHub Release）拉取 json，校验签名后写入设计令牌，实现**热加载换肤，无需刷新**。

## 文件规范（theme.json schema）

```json
{
  "id": "cyber",                  // 唯一标识
  "meta": { "name": "赛博朋克", "ver": "1.0", "author": "...", "license": "..." },
  "forceDark": true,              // 可选：强制深色（如赛博朋克）
  "tokens": {                     // 亮色令牌
    "--accent":   "强调色",
    "--accent-l": "深色模式下的强调色",
    "--g1/--g2/--g3": "渐变三停点（hero卡/按钮/进度条）",
    "--page":  "页面底色",
    "--card":  "卡片底色",
    "--card-bd": "卡片描边",
    "--card-r":  "卡片圆角",
    "--card-sh": "卡片阴影（可含发光）",
    "--nav-bg / --nav-bd": "底栏背景/描边",
    "--page-img":  "可选：页面纹理/装饰背景（CSS 图像）",
    "--app-font":  "可选：全局字体（复古/衬线主题用）"
  },
  "dark": { ... }                 // 深色模式下的同名令牌覆盖
}
```

## 规则
1. 与深色模式**正交**：`tokens` 为亮态、`dark` 为深态，切换深色时自动取对应组。
2. 缺失令牌回落到「简约」默认值，允许只做局部微调的主题（仅改强调色也可成立）。
3. 热加载：`applyTokens()` 写入 `<html>` style 属性即全局生效；主题市场（设置 → 主题风格 → 更多主题）演示了拉取→校验→应用全流程。
4. 内置 7 套：minimal / fresh / retro / neumorph / cyber / autumn / ocean；本目录提供新增 3 套的独立配置文件示例；市场扩展（sakura / mint / graphite）在 prototype/index.html 的 `MKT` 中内嵌（file:// 无法 fetch，浏览器原型用内嵌对象模拟，内容结构与本目录 json 一致）。
5. 正式版安全：远程主题需附发布者签名与哈希校验，敏感令牌（如注入 url）做白名单过滤。
