# 词记（Ciji）

macOS 原生中文输入法：默认 **小鹤双拼**，也可切到全拼。候选栏跟随光标，在汉字旁边显示英文释义，方便边打边背单词。

灵感来自 Windows 上的[水杉输入法](https://github.com/metasequoiaime/MSIME-Windows)「实时背单词」功能。本项目是全新的 InputMethodKit 实现，**不依赖腾讯云**。释义优先走本机可配置的 [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)（OpenAI 兼容接口），离线则回退到 CC-CEDICT 英译。

- 产品名：词记
- Bundle ID：`com.shengtao.ciji.inputmethod`
- 安装位置：`~/Library/Input Methods/Ciji.app`
- 系统要求：macOS 13+

## 下载安装（推荐）

1. 到 [Releases](https://github.com/s546126/ciji-ime/releases) 或 [Actions](https://github.com/s546126/ciji-ime/actions/workflows/build.yml) 的构建产物里下载 `Ciji-<版本>.dmg`（Universal：Apple 芯片 + Intel）
2. 打开 DMG，双击 **安装词记.command**
   - 未签名构建：若提示“无法验证开发者”，右键 →「打开」，或 系统设置 → 隐私与安全性 → 仍要打开
3. 系统设置 → 键盘 → 输入法 → 编辑… →「+」→ 简体中文 → **词记**（列表里没有就注销重登一次）

卸载：双击 DMG 里的 **卸载词记.command**。

## 功能

- 小鹤双拼（默认）/ 全拼，`Ctrl+Shift+P` 或输入法菜单切换
- 竖排候选窗：「序号 + 中文 + 英文释义」，边打字边背单词
- 整句组词：`woshizhongguoren` → 我是中国人；`jintiantianqizhenhao` → 今天天气真好
- 真实词频排序（rime-essay 语料 + 多音字读音权重）；末音节可不打完（`zhonggu` → 中国）
- **英文反查**：直接打 `hello` / `why` / `translate` → 你好 / 为什么 / 翻译
- **Jev 智能重排**（可选）：参考光标前的上文，自动把最通顺的候选排到第一并标 ✦（汽车 + `youxiang` → 油箱；我现在 + `youxiang` → 又想）
- **生词本 + 复习**：`Ctrl+S` 收藏；按 1/2/4/7/15/30… 天间隔复习，到期的词在候选里标「复习」，底栏提醒；打出来即算复习一次
- **Relingo 打通**：同步你的 Relingo 生词本（候选英文命中标「R」），`Ctrl+S` 同时推送到 Relingo；也可导入/导出单词表
- **朗读**：`Ctrl+R` 用系统语音读英文；**整句翻译**：`Ctrl+T` 看英文，再按一次直接上屏英文
- 越用越顺手：记住你选过的词、组过的句子，以及「上一个词 → 下一个词」的搭配（本地保存）
- 本地词库约 20 万词（CC-CEDICT + 语料高频词）；带「≈」的是由词素拼出的近似释义

候选标记：✦ Jev 推荐 · ★ 生词本 · 复习 今天该复习 · R 你的 Relingo 生词

## 按键

| 操作 | 效果 |
| --- | --- |
| Shift 单击 / Caps Lock | 中 ⇄ 英 |
| `Ctrl+Shift+P` | 小鹤双拼 ⇄ 全拼 |
| 空格 | 上屏高亮候选 |
| `1`–`9` | 上屏对应候选 |
| `↑` / `↓` | 移动高亮 |
| `-` `=`、`[` `]`、`Tab`、`←` `→`、PageUp/Down | 翻页 |
| 回车 | 上屏原始字母（打英文单词用） |
| Esc | 取消 |
| 退格 | 删一个按键 |
| `'`（全拼） | 音节分隔：`xi'an` → 西安 |
| `Ctrl+S` | 当前高亮词加入 / 移出生词本（并推送 Relingo） |
| `Ctrl+R` | 朗读英文 |
| `Ctrl+T` | 整句翻译；再按一次上屏英文 |
| `` Ctrl+` `` | 立即请求 Jev 重排 |
| 标点 | 自动上屏首选后输出中文标点 |

小鹤零声母：单字母韵母双击（`a`→`aa`），双字母保持全拼（`en`→`en`），三字母为首字母 + 韵母键（`ang`→`ah`）。

## 从源码编译

只需要 Command Line Tools（`xcode-select --install`），不需要 Xcode.app：

```bash
git clone https://github.com/s546126/ciji-ime.git
cd ciji-ime
./scripts/install.sh          # 编译并安装到 ~/Library/Input Methods
```

其他脚本：

```bash
ARCHS="arm64 x86_64" scripts/build_app.sh   # 只编译 build/Ciji.app（Universal）
VERSION=1.0.0 scripts/make_dmg.sh           # 打包 build/Ciji-1.0.0.dmg
build/Ciji.app/Contents/MacOS/Ciji --selftest   # 无界面自检 Swift 引擎
```

GitHub Actions（`.github/workflows/build.yml`）每次 push 都会：跑 Python 引擎测试 → 在 macOS 上编译 Universal app → 跑 `--selftest` → 打 DMG 并上传为构建产物。推送 `v*` 标签（如 `git tag v1.0.0 && git push --tags`）会自动发布 Release 并附上 DMG。

## Jev 智能重排

参考 [jev-rime-rerank](https://github.com/icf1re/jev-rime-rerank) 的思路：把光标前的上文 + 前 6 个候选发给 TypeSafe 的 System One 决策模型 [Jev](https://openrouter.ai/typesafe/jev-1.13)，按概率重排。不同的是词记是**自动**的：停顿 150ms 后在后台请求，打字不卡，结果回来就刷新候选；失败/超时就保持本地顺序。上文优先读取当前 App 光标前的文字（读不到就用本次输入的内容）。

在 `~/Library/Application Support/Ciji/config.json` 里：

```json
"jev": {
  "enabled": true,
  "provider": "openrouter",      // 或 "gateway"
  "apiKey": "sk-or-…",           // OpenRouter Key；gateway 模式填网关的 Key
  "url": "",                     // gateway 模式填 …/jev/decide 或 …/laya/decide
  "model": "typesafe/jev-1.13",
  "candidates": 6, "debounceMs": 150, "timeoutMs": 1500
}
```

OpenRouter 模式请求 `POST https://openrouter.ai/api/alpha/decisions`。如果 AI 释义本身就配的 OpenRouter（`proxyBaseURL` 含 openrouter.ai），`jev.apiKey` 可留空复用。菜单里能开关 Jev、看最近一次调用状态。注意：开启后，光标前约 40 个字的上文和候选词会发给所配置的服务。

## 生词本与 Relingo

- 生词本保存在 `~/Library/Application Support/Ciji/vocab.json`；菜单「生词本…」导出 `生词本.csv`（中文、拼音、English、下次复习；可直接导入 Anki）。
- **Relingo 同步**：在 config.json 填 `"relingo": {"token": "…"}`。token 获取：浏览器打开任意网页让 Relingo 插件工作 → 开发者工具 Network → 任一 `api.relingo.net` 请求头里的 `x-relingo-token`。之后：
  - 词记会拉取你 Relingo 生词本里的英文单词，候选英文命中时标「R」；
  - `Ctrl+S` 收藏时把英文词（如 翻译 → translate）合并进 Relingo 生词本（先读再合并，不会覆盖）；默认推到第一个非「已掌握」的生词本，可用 `relingo.vocabularyId` 指定（菜单「Relingo：立即同步」会显示各生词本的 id）。
  - Relingo 没有公开 API，这里用的是插件同款接口（参考开源的 [relingo-desktop](https://github.com/bonaysoft/relingo-desktop)），接口变动时可能失效。
- **不填 token 也能打通**：菜单「Relingo：导出英文单词表」生成 `relingo-import.txt`（一行一个词）供 Relingo / 其他背词软件导入；「Relingo：导入单词表」读取 Relingo 导出的 txt/csv（取第一列英文）。

## 英文释义与 CLIProxyAPI

（`Ctrl+T` 整句翻译也走这个接口；任何 OpenAI 兼容地址都行，比如 OpenRouter：`"proxyBaseURL": "https://openrouter.ai/api/v1"`。没配置时 `Ctrl+T` 显示逐词近似释义。）

打字从不阻塞在网络上。没有代理时，候选右侧用 CEDICT 英文；配置了代理后，可见的一页会批量请求短释义，失败则继续用 CEDICT。

1. 先在本机启动 [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)。默认监听 **8317**，常见地址：

   `http://127.0.0.1:8317/v1`

2. 编辑（安装脚本会自动创建）：

   `~/Library/Application Support/Ciji/config.json`

   ```json
   {
     "proxyBaseURL": "http://127.0.0.1:8317/v1",
     "apiKey": "",
     "model": "gemini-2.5-flash"
   }
   ```

   仓库里的样例是 `Ciji/Resources/config.sample.json`，**默认 `proxyBaseURL` 和 `apiKey` 都是空字符串**，请自行粘贴地址。不要把密钥写进仓库。

3. 保存即生效（输入法会检测文件修改时间自动重读）。

请求：`POST {baseURL}/chat/completions`。若 `proxyBaseURL` 已经以 `/v1` 结尾，不会再拼一层 `/v1`；若写成完整的 `/v1/chat/completions` 也会原样使用。可选 `apiKey` 会放进 `Authorization: Bearer …`（CLIProxyAPI 的 api-keys）。超时约 1.6 秒，按词缓存到 `~/Library/Application Support/Ciji/gloss-cache.json`。

## 词库

`scripts/build_dict.py` 合并 CC-CEDICT（释义）、rime-essay（词频）、rime-luna-pinyin（多音字权重），写入 `Ciji/Resources/cedict.tsv.gz`（已入库，约 5 MB）。重新生成：

```bash
python3 scripts/build_dict.py
python3 -m unittest tests.test_engine -v   # 引擎测试（不需要 Mac）
```

## 架构

- Swift 5 + InputMethodKit。`CijiInputController` 只做门面；组词状态在 `InputSession`，按 client 弱引用缓存，避免 Caps Lock 切输入法时把重对象钉在短命的 controller 上。
- 候选窗是自定义 `NSPanel`，不用系统 `IMKCandidates`（新系统上玻璃效果容易把字衬没）。
- 组词编码与 `scripts/ciji_engine.py` 对齐，便于在 Linux 上测小鹤表和 `wodemkzi` 排序。
- 语言模式使用 Swift 5，避开 Swift 6 默认隔离和未标注的 IMK 头文件冲突。`InputMethodConnectionName` 为 `$(PRODUCT_BUNDLE_IDENTIFIER)_Connection`。

## 许可

- 输入法源码：MIT（见 `LICENSE`）
- 词库：CC-CEDICT（CC BY-SA 4.0）+ rime-essay / luna-pinyin（LGPL-3.0），见 `NOTICE`
