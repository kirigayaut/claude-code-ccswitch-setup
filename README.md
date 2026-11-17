# claude-code-ccswitch-setup

把一台电脑上配好的 **Claude Code + CCSwitch** 环境，复刻到另一台电脑上（典型情况是 Mac → Windows），两台共用同一套全局规则和子代理。

做成了一个 Claude Code **skill**：装好后，在新电脑的 Claude Code 里让它按步骤自己执行。遇到需要你决定或者需要你在界面里操作的地方，它会停下来问你。

## 适合谁

满足下面这些条件就适用：

- 在 **VS Code 的 Claude Code 插件**里用 Claude Code（命令行版也基本适用）。
- 用 **[CCSwitch](https://github.com/farion1231/cc-switch)** 的**聚合模式**接入模型。本地代理默认是 `127.0.0.1:15721`，后面接一个或几个中转供应商。picker 里的模型名长这样：`ccs-claude-<stack key>--claude-opus-5-5[1M]`。
- 有两台或以上的电脑，希望共用：
  - 全局规则 `CLAUDE.md`
  - 按模型路由的子代理 worker，比如 haiku / sonnet / opus 各一个
- 有一个能在电脑之间同步的文件夹：坚果云、OneDrive、iCloud、Dropbox 或者 git 仓库都可以。

## 它解决的问题

照着做下来，大多数人会踩到这些坑，skill 里都写了怎么查、怎么改：

1. **两台电脑的模型前缀对不上。** CCSwitch 给供应商分配的 key 在第一次加入聚合时就定死了，改名不会变，界面里也改不了。结果是共享的 worker 在新电脑上找不到模型。
2. **主模型等于模型列表里的第一个。** 列表顺序不对的话，所有分档都会悄悄变成别的模型。
3. **有几项分档映射在界面里看不到。** 自动模式的权限分类器走的就是其中的 SONNET 档。这一档用错模型，工具调用会被全部拦下，严重时会话直接被中止。
4. **在 Agent 工具里写 `model: haiku` 不起作用。** 聚合模式下这些别名全部指向主模型，要按模型派子代理只能用 worker。
5. **Windows 上的特有问题：**
   - 系统里没有 sqlite3，`python` 也只是个占位程序
   - 自动模式的权限检查会拦下对 `settings.json` 的修改
   - worker 要等下一轮对话才会加载
   - 通知脚本存成别的编码会显示乱码
   - ……

## 目录

```
skills/claude-code-ccswitch-setup/
├── SKILL.md                     # 给 Claude 的执行步骤（第 0–8 步）
├── references/
│   ├── ccswitch-internals.md    # CCSwitch 的数据存在哪、什么时候会被重写，每条注明实测还是推断
│   └── pitfalls.md              # 现象 → 原因 → 处理
├── templates/
│   ├── CLAUDE.md                # ~/.claude/CLAUDE.md：只有一行 @ 引用
│   ├── agents/*-worker.md       # 三个 worker，把 <stack key> 换成你的
│   ├── claude-notify.ps1        # Windows 完成通知（UTF-8 带 BOM，按原文件复制，不要另存）
│   └── stop-hook.windows.json   # 加到 settings.json 里的 Stop hook
└── scripts/
    ├── ccs-query.ps1            # Windows：用系统自带的 winsqlite3.dll 只读查询 CCSwitch 数据库，自动遮掉 token
    └── ccs-update-tiers.ps1     # Windows：先备份，再改隐藏的三个分档；改之前会核对当前值，只改 1 行
```

## 怎么用

### 1. 安装 skill

把 `skills/claude-code-ccswitch-setup/` 整个文件夹放进新电脑的 `~/.claude/skills/` 目录：

```powershell
# Windows（PowerShell）
git clone https://github.com/kirigayaut/claude-code-ccswitch-setup.git
Copy-Item -Recurse .\claude-code-ccswitch-setup\skills\claude-code-ccswitch-setup "$env:USERPROFILE\.claude\skills\"
```

```bash
# macOS
git clone https://github.com/kirigayaut/claude-code-ccswitch-setup.git
cp -R claude-code-ccswitch-setup/skills/claude-code-ccswitch-setup ~/.claude/skills/
```

不用 git 的话，在 GitHub 页面上点 **Code → Download ZIP**，解压后照样复制。不要在网页上复制 `claude-notify.ps1` 的内容再粘贴保存，那样会丢掉 BOM，通知里的中文会变成乱码。

### 2. 在新电脑上让 Claude 开始做

新开一个 Claude Code 会话，输入：

```
/claude-code-ccswitch-setup
```

或者直接用自然语言说，比如："按 claude-code-ccswitch-setup 这个 skill，把我 Mac 上的 Claude Code 配置迁到这台 Windows。每一步做完告诉我结果，要改 CCSwitch 数据库、改 settings.json 或覆盖已有文件时先问我。"

它会先问你几个参数：同步文件夹的路径、源电脑的 stack key、供应商最初叫什么名字、要用哪几个模型。然后按步骤一步步做。

### 3. 你需要亲自做的事

- 在 **CCSwitch 界面**里操作：新建供应商、调整模型顺序、加入聚合、设默认供应商、退回直连再进入聚合。Claude 会告诉你点哪里。
- 同意它修改**数据库里的分档映射**。它会先列出改哪一项、从什么改成什么。
- 改 `settings.json` 之前，把权限模式**临时切到需要手动确认的模式**。
- 新开一个会话，帮它验证规则文件有没有加载上。

## 不用 skill，自己手动照着做

`SKILL.md` 本身就是一份完整的操作步骤，可以直接照着做。最短的检查清单：

1. 共享文件夹里放 `rules.md` 和 `agents/`；每台电脑的 `~/.claude/CLAUDE.md` 只写一行 `@<路径>/rules.md`，`~/.claude/agents` 做成指向共享文件夹的链接。
2. 新电脑上 CCSwitch 生成的前缀必须和 worker 里写的一样。不一样就**新建**一个供应商，名字用源电脑上它最初的名字，不选图标，**模型列表里 opus 放第一个**。
3. 检查数据库里那三项隐藏分档：HAIKU 用 haiku 模型；SONNET 用分类器能用的模型，比如 `claude-sonnet-5`，**不要**用 `claude-sonnet-5-5`；OPUS 用 opus 模型。
4. 派三个 worker 子代理，看记录里每个请求的 model 和 effort 是否符合预期。
5. 本机专属的设置（`autoCompactWindow`、通知 hook）加完以后，在 CCSwitch 里退回直连再进入聚合，确认这些设置没有被覆盖掉。

## 测试环境

2026-11 在下面这套环境里，把 **Windows 这一端（第 1–8 步）** 完整跑过一遍。源电脑是一台已经配好的 macOS：

- Windows 10 Enterprise 22H2，Windows PowerShell 5.1
- Claude Code 2.1.325（VS Code 插件）
- CCSwitch 4.0.32

下面这些**没有**在本仓库里实测过：第 0 步（在源电脑上搭共享文件夹）、macOS 上用 `sqlite3` 查询和修改数据库的写法、macOS 的 `osascript` 通知。SKILL.md 里也标出了这几处。

CCSwitch 升级后，内部行为可能会变。`references/ccswitch-internals.md` 里每一条都写了是怎么验证的，拿不准时按那里的方法重新验证。

## 注意

- 仓库里没有任何密钥。脚本输出时会遮掉 token，但只是按字段名匹配，不保证遮全；中转地址（`ANTHROPIC_BASE_URL`）也会原样显示。往 issue 或报告里贴日志之前，请自己再检查一遍。
- 这些 skill 会让 Claude 操作你本机的 CCSwitch 数据库和 Claude Code 配置。每一步改什么都会先问你，看清楚了再同意。
