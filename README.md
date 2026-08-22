# 词记（Ciji）

macOS 原生中文输入法：默认 **小鹤双拼**，也可切到全拼。候选栏跟随时跟随光标，在汉字旁边显示英文释义，方便边打边背单词。

灵感来自 Windows 上的[水杉输入法](https://github.com/metasequoiaime/MetasequoiaImeTsf)「实时背单词」功能。本项目是全新的 InputMethodKit 实现，**不依赖腾讯云**。释义优先走本机可配置的 [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)（OpenAI 兼容接口），离线则回退到 CC-CEDICT 英译。

- 产品名：词记
- Bundle ID：`com.shengtao.ciji.inputmethod`
- 安装位置：`~/Library/Input Methods/Ciji.app`
- 系统要求：macOS 13+

## 功能

- 小鹤双拼（默认）/ 全拼，菜单栏或 `Ctrl+Shift+P` 切换
- 深色候选窗：顶栏是带撇号的拼音分段（如 `wo'de'mk'zi`），下面是「序号 + 中文 + 英文」
- `wodemkzi`（小鹤：`ming=mk`）首选 **我的名字**，而不是「帽子」（`mao=mc` → `wodemczi`）
- 组词：空格 / `1` 上屏首选，`2`–`9` 上屏对应候选，`-` / `=` 翻页，回车上屏，Esc 取消，退格删码
- 中文标点；Caps Lock 进入 ASCII 直通
- 本地词库来自 CC-CEDICT（拼音 / 小鹤索引 + 离线英文）
- 可见候选整页一次请求 LLM，按词缓存；网络失败或超时时不卡住打字

## 编译与安装

在 Mac 上：

```bash
git clone https://github.com/s546126/ciji-ime.git
cd ciji-ime
chmod +x scripts/install.sh
./scripts/install.sh
```

脚本会调用 `xcodebuild`，再把 `Ciji.app` 拷到 `~/Library/Input Methods/`。

手动构建：

```bash
# 若尚未生成词库（仓库已带预处理结果，一般不用）
python3 scripts/build_dict.py

xcodebuild -project Ciji.xcodeproj -scheme Ciji -configuration Release \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual build
```

## 启用输入法

1. 打开 **系统设置 → 键盘 → 输入法**（或「输入源」）
2. 点 **+**，在简体中文下列表里找到 **词记**
3. **第一次**加入输入法后，macOS 可能要 **注销并重新登录** 才会出现；若列表里没有，可先运行一次：

   ```bash
   open ~/Library/Input\ Methods/Ciji.app
   ```

   然后注销再试。
4. 菜单栏切换到「词记」后即可输入。菜单栏图标「词」也可切换方案。

更新或重装后执行 `killall Ciji`（或再跑一遍 `scripts/install.sh`）。

## 输入方案

| 操作 | 效果 |
| --- | --- |
| `Ctrl+Shift+P` | 小鹤双拼 ↔ 全拼 |
| 菜单栏「词」或输入法菜单 | 同样可以切换 |
| Caps Lock | 英文 ASCII 直通 |
| 空格 / `1` | 上屏第 1 条 |
| `2`–`9` | 上屏对应候选（不足一页则忽略） |
| `-` / `=` | 上一页 / 下一页 |
| 回车 | 上屏当前选中项 |
| Esc | 清空编码 |
| 退格 | 删一个按键 |

小鹤零声母：单字母韵母双击（`a`→`aa`），双字母保持全拼（`en`→`en`），三字母为首字母 + 韵母键（`ang`→`ah`）。每个音节两键。

v1 **没有**小鹤音形辅助码（如 `(pV)`）。

## 英文释义与 CLIProxyAPI

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

3. 保存后执行 `killall Ciji`（或注销）让输入法重新读配置。之后只需改这个文件即可换代理地址。

请求：`POST {baseURL}/chat/completions`。若 `proxyBaseURL` 已经以 `/v1` 结尾，不会再拼一层 `/v1`；若写成完整的 `/v1/chat/completions` 也会原样使用。可选 `apiKey` 会放进 `Authorization: Bearer …`（CLIProxyAPI 的 api-keys）。超时约 1.6 秒，按词缓存到 `~/Library/Application Support/Ciji/gloss-cache.json`。

## 词库

`scripts/build_dict.py` 会下载 [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict)，编成小鹤 / 全拼前缀索引，并写入 `Ciji/Resources/cedict.tsv.gz`（约 3.2 MB，已入库）。重新生成：

```bash
python3 scripts/build_dict.py
```

引擎测试（不需要 Xcode）：

```bash
python3 -m unittest tests.test_engine -v
```

## 架构

- Swift 5 + InputMethodKit。`CijiInputController` 只做门面；组词状态在 `InputSession`，按 client 弱引用缓存，避免 Caps Lock 切输入法时把重对象钉在短命的 controller 上。
- 候选窗是自定义 `NSPanel`，不用系统 `IMKCandidates`（新系统上玻璃效果容易把字衬没）。
- 组词编码与 `scripts/ciji_engine.py` 对齐，便于在 Linux 上测小鹤表和 `wodemkzi` 排序。
- 语言模式使用 Swift 5，避开 Swift 6 默认隔离和未标注的 IMK 头文件冲突。`InputMethodConnectionName` 为 `$(PRODUCT_BUNDLE_IDENTIFIER)_Connection`。

## 许可

- 输入法源码：MIT（见 `LICENSE`）
- 词库：CC-CEDICT 为 CC BY-SA 3.0，见 `NOTICE`
