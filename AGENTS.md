# AGENTS.md

本文件是 album-app 仓库的协作约定。改动代码前先读本文件。

## 构建与验证

- Flutter 3.24（`/home/mikey/work/.toolchain/flutter/bin`）。
- 校验命令（必须带 `--no-pub`，且不要并发跑多个 flutter 命令）：

  ```bash
  export PATH=/home/mikey/work/.toolchain/flutter/bin:$PATH
  export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
  flutter --no-version-check analyze --no-pub
  flutter --no-version-check test --no-pub
  ```

- 提交前 `analyze` 必须 No issues found，`test` 必须全绿。
- 不提交 `build/`、`dist/` 产物；不动 `album-server`。

## UI 文案与布局规则

界面表达优先：先靠结构说话，文案是最后手段。

1. **用布局表达层级，而不是用文字解释层级。** 优先级依次为：布局、对齐、分组、留白、图标。能用间距分组、用对齐建立主次、用图标暗示含义的地方，不要加辅助标签、说明文字或副标题。
2. **一行能说清的不拆两行。** 不要把一个语义拆成"标题 + 副标题 + 说明"三层。数值靠右对齐，不要写成"标题：值"的句子。
3. **加任何说明性文案前先自问：删掉它用户还能看懂吗？** 能，就别加。新增文案要在 PR/提交说明里说清它为什么不能被删。
4. **例外（必须保留明确提示）：** 破坏性/不可逆操作（删除、清理、覆盖）、隐私相关（谁可见、谁能访问）、计费相关（会产生费用、额度消耗）。这类场景必须保留清晰的确认与后果说明，不受上面三条约束。
