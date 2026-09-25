词记 Ciji — macOS 中文输入法（小鹤双拼 / 全拼，候选栏实时英文释义）

安装
1. 双击「安装词记.command」。
   如果提示“无法验证开发者”：右键 →「打开」，或到
   系统设置 → 隐私与安全性 → 仍要打开。
   （也可以在终端运行：bash /Volumes/词记*/安装词记.command）
2. 系统设置 → 键盘 → 输入法 → 编辑… →「+」→ 简体中文 → 词记。
   列表里没有的话，注销并重新登录一次。

使用
- Shift 单击：中 / 英切换（Caps Lock 也可切到英文）
- Ctrl+Shift+P：小鹤双拼 ⇄ 全拼（菜单栏输入法菜单也能切）
- 空格：上屏高亮候选；1–9：选择；↑↓ 移动高亮
- - / = 、[ / ]、Tab、←/→：翻页
- 回车：上屏原始字母；Esc：取消
- 全拼可用 ' 分隔音节（xi'an → 西安）
- 直接打英文（hello / why）也能出中文候选
- 输入法会记住你选过的词和词序，越用越顺手

背单词（组字时）
- Ctrl+S：加入/移出生词本（配置了 Relingo token 会同步到 Relingo）
- Ctrl+R：朗读英文　Ctrl+T：整句翻译（再按一次上屏英文）
- Ctrl+`：立即让 Jev 重排
- 标记：✦ Jev 推荐　★ 生词本　复习 今天该复习　R 你的 Relingo 生词
- 菜单栏「词」：生词本导出（CSV/Anki）、Relingo 同步/导入/导出、Jev 开关

英文释义来自 CC-CEDICT；带「≈」的是由词素拼出来的近似释义。
配置（可选）：~/Library/Application Support/Ciji/config.json
  jev.apiKey = OpenRouter Key → 开启 Jev 智能重排
  relingo.token = Relingo 插件的 x-relingo-token → 同步生词本
  proxyBaseURL/apiKey/model = AI 释义与整句翻译

卸载：双击「卸载词记.command」。
