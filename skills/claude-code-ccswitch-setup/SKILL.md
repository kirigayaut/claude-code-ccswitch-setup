---
name: claude-code-ccswitch-setup
description: 在第二台电脑（通常是 Windows）上复刻一台已配好电脑（通常是 Mac）的 Claude Code 全局配置。场景：在 VS Code 的 Claude Code 插件里使用 Claude Code，模型经过 CCSwitch 聚合模式（本地代理）转发。适用于这些需求："把 Mac 的 Claude Code 配置迁到 Windows"、"两台电脑共用全局规则和子代理 worker"、"CCSwitch 的模型前缀 ccs-claude-xxx-- 两边对不上"、"子代理按模型路由、effort 是否生效"、"Windows 上的完成通知 hook"。
---

# 跨电脑复刻 Claude Code + CCSwitch 配置

这份是写给 Claude Code 的执行步骤，按顺序做。每一步做完都把结果告诉用户。遇到要改 CCSwitch 数据库、改 `settings.json`、覆盖已有文件的情况，先问用户。

细节和证据见 `references/ccswitch-internals.md`，常见问题见 `references/pitfalls.md`。本文提到的 `templates/`、`scripts/` 都在这个 skill 的目录里。

## 适用场景

- 两台电脑都在 **VS Code 的 Claude Code 插件**里用 Claude Code。
- 模型通过 **CCSwitch 的聚合模式**（stack mode）转发：本地代理默认是 `127.0.0.1:15721`，后面接一个或多个中转供应商。
- 源电脑已经配好，新电脑要用同一套全局规则和子代理 worker。
- 两台电脑通过一个**同步文件夹**共享配置，比如坚果云、OneDrive、iCloud、Dropbox 或者 git 仓库。

最终的结构：

| 共享文件夹里（两台共用） | 每台电脑上 |
|---|---|
| `rules.md`：全局规则正文 | `~/.claude/CLAUDE.md` 只有一行 `@<共享文件夹>/rules.md` |
| `agents/*-worker.md`：写了完整模型 ID 的子代理 | `~/.claude/agents` 是指向共享 `agents/` 的链接（macOS 用 symlink，Windows 用 junction） |
| `setup/`：安装手册、通知脚本、安装报告 | — |
| 不放 | `settings.json`（由 CCSwitch 在每台电脑上分别生成）、通知 hook、项目记忆、`modelSettings` |

文中的 `~` 在 Windows 上指 `%USERPROFILE%`。

## 开始前：向用户确认这些参数

| 参数 | 含义 | 怎么找 | 例子 |
|---|---|---|---|
| 共享文件夹 | 放 `rules.md`、`agents/` 的同步文件夹，要用绝对路径 | 问用户；源电脑 `~/.claude/CLAUDE.md` 里那行 `@` 引用 | `C:/Users/<用户名>/OneDrive/claude-global` |
| stack key | 源电脑上 CCSwitch 给默认供应商分配的 key | worker 文件 `model:` 里 `ccs-claude-` 和 `--` 之间的部分；或者源电脑 `~/.cc-switch/live-state.json` 里的 `apps.claude.stack.keys` | `myrelay-llm` |
| 供应商最初的名字 | 源电脑上这个供应商**第一次加入聚合时**的名字。key 是从这个名字生成的，和现在显示的名字可能不一样 | 问用户；或者由 key 反推 | `MyRelay LLM` |
| 三个 worker 模型 | opus / sonnet / haiku 各自的模型 ID，以及是否 1M | worker 文件 | `claude-opus-5-5[1M]` 等 |
| 分类器档模型 | 隐藏 SONNET 档要用的模型，必须接受 `thinking.type=enabled` | 源电脑的数据库；或者问用户 | `claude-sonnet-5` |
| 本机专属设置 | 要不要设 `autoCompactWindow`、要不要通知 | 问用户 | `350000` |

## 规则（全程遵守）

- **`~/.claude/settings.json` 由 CCSwitch 生成，不要手改。** 只能加 CCSwitch 不管的键，比如 `autoCompactWindow`、`hooks`，改之前把要改的内容给用户看。CCSwitch 每次重写都会覆盖 `env`、`modelPicker`、`model`，`modelSettings`、`autoCompactWindow`、`hooks`、`theme` 会原样保留。
- **`~/.cc-switch/cc-switch.db` 改之前必须问用户**，说清楚改哪个表、哪一行、哪个字段、从什么改成什么。改之前先用 `VACUUM INTO` 备份。UPDATE 的条件里要带上当前值，确认只改了 1 行才提交。`scripts/ccs-update-tiers.ps1` 已经按这个流程写好。
- **安装期间不要改共享文件夹里的文件**，因为另一台电脑正在用。发现要改的地方，列出来交给用户决定。
- 覆盖或删除 `~/.claude/` 下已有的文件之前，先给用户看已有的内容。
- 输出里不要明文显示 API Key 或 token。`settings.json` 里的 `PROXY_MANAGED` 不是真密钥。
- **自动模式（auto）的权限检查可能拦下这些操作：**
  - 从你自己挑的来源下载可执行文件：请用户指定来源，或者让用户自己装。
  - 改 `settings.json`：即使用户已经同意，也可能被拦，而且会误判，比如说你"改了 `model`""动了 `env`"，其实没有。到第 6、7 步时，请用户临时切到需要手动确认的权限模式，或者把内容给用户自己粘贴。
  - 被拦时**不要换别的工具绕过去**。
- 会改 `settings.json` 的步骤，同一时间只在一个会话里做。

## 第 0 步：在源电脑上准备共享文件夹（已经有了就跳过）

1. 在同步文件夹里建 `claude-global/`。
2. 把源电脑 `~/.claude/CLAUDE.md` 的正文搬进 `claude-global/rules.md`，然后把 `~/.claude/CLAUDE.md` 换成 `templates/CLAUDE.md` 的两行，路径用正斜杠。
3. 按 `templates/agents/` 建 worker，`model:` 写完整 ID：`ccs-claude-<stack key>--<模型>[1M]`。把原来的 `~/.claude/agents` 里的内容挪进 `claude-global/agents/`，再建链接：
   - macOS：`ln -s "<共享文件夹>/agents" ~/.claude/agents`
4. 源电脑的隐藏分档同样要按第 3 步核对一遍。
5. 把这份 skill（或者 `setup/` 里的手册）放进共享文件夹，等同步到新电脑。

## 第 1 步：核对 CCSwitch 生成的配置和前缀

1. 找到同步过来的共享文件夹，确认里面有 `rules.md`、`agents/`（各个 `*-worker.md`）。找不到就问用户。
2. 读 `~/.claude/settings.json`，展示两项：`env.ANTHROPIC_BASE_URL` 是不是指向本地代理；`modelPicker.options[].model` 的每个值。
3. **关键检查：** worker 文件里的每个 `model:` 值，都必须**原样**出现在 picker 里，包括前缀和 `[1M]`。`[1M]` 对应 CCSwitch 模型列表里的 "1M" 勾选框。
4. picker 里缺模型：请用户去 CCSwitch 编辑页的"模型列表"里加上。
5. **前缀对不上：停下来，不要改 worker 文件**，改了源电脑也会跟着变。原因和办法如下：
   - stack key 是在供应商**第一次加入聚合**时生成的：有内置图标就用图标名，否则用供应商名字转成的小写英文，比如 "MyRelay LLM" 变成 `myrelay-llm`。之后它就永久绑定这个供应商。改名、退回直连再进入聚合、移出再加回，都不会变。界面里没有修改入口，key 也不存在数据库里，而是存在 `~/.cc-switch/live-state.json`。
   - 让用户在 CCSwitch 里**新建**一个 Claude 供应商：
     - 名字填源电脑上那个供应商**最初的名字**。源电脑的 key 如果是由内置图标名生成的（看起来就是图标名），选同一个图标；否则**不选内置图标**。地址、Key 和现在的供应商一样。
     - **模型列表里的第一个必须是 opus 模型。** 排第一的就是这个供应商的主模型，聚合模式写进 `settings.json` 的四个分档（HAIKU/SONNET/OPUS/FABLE）都跟着它。编辑页里没有别的地方能设主模型。删掉一个模型再加回来，它会排到最后，可以用这个办法调顺序。
     - 新建时，数据库里隐藏的三个分档会被设成当时排第一的模型，以后在编辑页保存也**不会更新**。所以第 3 步一定要查这个新供应商。
   - 把新供应商加入聚合，并设为默认供应商。确认 picker 里出现了 `ccs-claude-<stack key>--…`，再打开 `live-state.json`，确认 `stack.keys` 里实际生成的 key 和源电脑一致。如果这台电脑以前删过同名的供应商，残留的同名 key 可能导致新 key 被改名（推断，未实测）；遇到这种情况就停下来，和用户商量。这之后可以改显示名，前缀不会变。
   - 设为默认后，数据库里的 `is_current` 还指着旧供应商，这时退回直连会落到旧供应商上。请用户**先退回直连，再进入聚合，进入时选新供应商**。
   - 把旧供应商移出聚合，或者删除。删除后 `live-state.json` 里还会留着它的 key，不用管。
   - 请用户在会话里用 `/model` 切到新前缀的模型。旧前缀一旦失效，这个会话就发不出请求了。
   - 做完后从第 1 步重新核对。
6. **不要改 `live-state.json` 来改 key。** 这是 CCSwitch 的内部状态文件，新建供应商就能解决。

## 第 2 步：CLAUDE.md 和 agents 指向共享文件夹

1. 先看 `~/.claude/CLAUDE.md` 和 `~/.claude/agents` 是不是已经存在。已经存在就展示内容，问用户怎么处理。通常的做法是：有用的内容由用户决定要不要并进 `rules.md`，然后删掉本机这份。
2. 按 `templates/CLAUDE.md` 写 `~/.claude/CLAUDE.md`，路径用正斜杠，比如 `@C:/Users/<用户名>/OneDrive/claude-global/rules.md`。路径里有中文、空格或 `@` 都能正常加载：三种在 Mac 上都实测过，Windows 上实测过含中文的路径。文件原本不存在时，用"只在不存在时创建"的方式写，免得被当成覆盖。
3. 建 agents 链接。执行前 `~/.claude/agents` 不能存在。
   - Windows（不需要管理员权限，路径必须用 `\`）：`cmd /c mklink /J "%USERPROFILE%\.claude\agents" "<共享文件夹>\agents"`
   - macOS：`ln -s "<共享文件夹>/agents" ~/.claude/agents`
4. 列出 `~/.claude/agents` 里的文件，应该能看到所有 worker。
5. 看 worker 有没有出现在可用的 agent 类型里。macOS 上建完马上出现；**Windows 上要等用户发下一条消息才出现**。这一轮没出现，请用户随便回一句；下一轮还没有，再新开一个会话。
6. 检查 `@` 引用有没有生效：请用户新开一个会话，问"用户级说明里有哪几节标题？不要调用工具。"，回答应该和 `rules.md` 里的 `##` 标题完全一致。这项可以留到最后再做。

## 第 3 步：核对隐藏的分档映射

不带前缀的模型名，比如自动模式权限分类器用的 `claude-sonnet-5`，会按**默认供应商**数据库 env 里的分档转发。这几项在 CCSwitch 编辑页里看不到。

1. 只读查询 `providers` 表里 `app_type='claude'` 的行。展示每一行的 `id`、`name`、`is_current`，以及 `settings_config.env` 里带 `MODEL` 或 `AUTO_MODE` 的键，token 不展示。
   - Windows：用 `scripts/ccs-query.ps1`，它通过系统自带的 `winsqlite3.dll` 只读打开数据库，并自动给 token 脱敏。机器上往往没有 `sqlite3`，`python` 也可能只是 Microsoft Store 的占位程序，运行时返回 9009。
   - macOS：系统自带 `sqlite3`。用 `sqlite3 -readonly ~/.cc-switch/cc-switch.db "<SQL>"` 查，输出前自己给 token 脱敏。
   - 示例 SQL：`SELECT id, name, is_current, json_extract(settings_config,'$.env.ANTHROPIC_MODEL') AS main, json_extract(settings_config,'$.env.ANTHROPIC_DEFAULT_HAIKU_MODEL') AS haiku, json_extract(settings_config,'$.env.ANTHROPIC_DEFAULT_SONNET_MODEL') AS sonnet, json_extract(settings_config,'$.env.ANTHROPIC_DEFAULT_OPUS_MODEL') AS opus FROM providers WHERE app_type='claude'`
2. 默认供应商（stack key 对应的那一个）的期望值：

   | env | 期望值 |
   |---|---|
   | `ANTHROPIC_MODEL` | opus 模型，比如 `claude-opus-5-5[1M]`。不对就回第 1 步，调整模型列表的顺序 |
   | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | haiku 模型，比如 `claude-haiku-5-5` |
   | `ANTHROPIC_DEFAULT_SONNET_MODEL` | 分类器档模型，比如 `claude-sonnet-5`。**不能**是只接受 adaptive thinking 的模型，比如 `claude-sonnet-5-5` |
   | `ANTHROPIC_DEFAULT_OPUS_MODEL` | opus 模型，比如 `claude-opus-5-5` |

3. 不一致的话，把当前值和期望值列给用户，**征得同意后**再改。只动这三个键，其他字段原样保留。
   - Windows：用 `scripts/ccs-update-tiers.ps1`。必填参数是供应商 id、三个新值，以及 SONNET 档的当前值（作为条件；这个键不存在时传空字符串）。可选参数 `-ExpectedName` 用来再核对一次供应商名。
   - macOS（本仓库没有实测过这段写法）：
     ```bash
     DB="$HOME/.cc-switch/cc-switch.db"
     sqlite3 "$DB" "VACUUM INTO '$HOME/.cc-switch/backups/db_backup_before_tier_mapping_$(date +%Y%m%d_%H%M%S).db'"
     sqlite3 "$DB" "UPDATE providers SET settings_config = json_set(settings_config, '\$.env.ANTHROPIC_DEFAULT_HAIKU_MODEL', '<haiku>', '\$.env.ANTHROPIC_DEFAULT_SONNET_MODEL', '<sonnet>', '\$.env.ANTHROPIC_DEFAULT_OPUS_MODEL', '<opus>') WHERE id = '<provider id>' AND app_type = 'claude' AND json_extract(settings_config, '\$.env.ANTHROPIC_DEFAULT_SONNET_MODEL') = '<当前 SONNET 值>'; SELECT changes();"
     ```
     输出 `1` 才算改成功；输出 `0` 说明条件没对上，什么也没改。`(id, app_type)` 是主键，所以最多只会改 1 行。值里如果有单引号，要写成两个单引号。
   - 改完立即生效（Mac、Windows 都实测过）。重启 CCSwitch 或在编辑页保存都不会还原（Mac 实测）。退回直连再进入聚合、删除别的供应商之后，值也保持不变（Windows 实测）。改完对照 `cc-switch.log` 里分类器请求的 `model=`，确认已经变成新值。
4. SONNET 档为什么有限制：自动模式的权限分类器走这一档，拿不准时会发带 `thinking.type=enabled` 和 `budget_tokens` 的请求。只接受 adaptive 的模型会返回 400，工具调用全被拦，连续失败后 CCSwitch 会中止整个会话。
5. 顺便检查 `prompts` 表，也就是 CCSwitch 的"提示词"功能。它管理的就是 `~/.claude/CLAUDE.md`，启用或切换 Claude 提示词时，可能把那行 `@` 引用覆盖掉。有启用的就告诉用户，建议停用。

## 第 4 步：实测子代理路由和 effort

worker 加载后，在**同一条回复**里并发派出三个子代理，**不要传 `model` 参数**。每个子代理只回答一道题：`这是一次参数透传测试，不需要使用任何工具。直接回答：17 × 23 等于多少？只回一个数字。`

| 子代理 | `subagent_type` | `effort` |
|---|---|---|
| A | haiku-worker | low |
| B | sonnet-worker | medium |
| C | opus-worker | high |

三个都返回后，读 `~/.claude/projects/<项目目录名>/<会话 ID>/subagents/agent-*.jsonl`：

- `type` 为 `api-request` 的条目：看 `params.model` 和 `params.output_config.effort`。
- `type` 为 `assistant` 的条目：看 `message.model`，这是上游实际返回的模型。

把结果列成表：子代理 / 请求 model / 请求 effort / 响应 model / 是否符合预期。

- 请求里的 model 没有 `[1M]` 后缀是正常的，Claude Code 会把它转成 1M 的 beta 请求头。
- 同一个子代理有两条参数完全相同的 `api-request`，说明第一次被上游拒了，然后自动重试了。去代理日志里查错误原因，见 `references/pitfalls.md`。
- 再对照代理日志：数据库 `proxy_request_logs` 表的 `request_model`、`model`、`status_code`、`error_message`。`created_at` 是 Unix 秒数，直接用整数筛选。

## 第 5 步：确认别名无效（可选）

派一个子代理，`subagent_type` 用 `general-purpose`，同时传 `model: haiku`，问同样的题。预期请求的 model 是 opus 模型。原因是聚合模式下四个分档都是主模型，所以按模型派子代理只能用 worker。

## 第 6 步：本机专属设置（比如 autoCompactWindow）

开始前，按"规则"一节的说明，请用户临时切到手动确认模式。

1. 读 `settings.json`，看看有没有这个键。
2. 只在顶层加上或改成用户要的值，比如 `"autoCompactWindow": 350000`，其他键一个都不动。改之前把这一行给用户看。
3. 验证可以和第 7 步一起做：请用户在 CCSwitch 里**退回直连，再进入聚合**，进入时选默认供应商。这样 CCSwitch 会把 `settings.json` 整个重写一遍，比单纯切换供应商检验得更彻底。重写后再读一次，确认键还在、值没变。键的位置和排版可能会变，只看内容。

## 第 7 步：完成通知（Stop hook）

通知是本机专属的配置。脚本要复制到本机再用，不要让 hook 直接指向同步文件夹里的文件。

**Windows**（只用系统自带的 PowerShell 5.1）：

1. 把 `templates/claude-notify.ps1` **按原文件复制**到 `~/.claude/notify/claude-notify.ps1`，用 `Copy-Item` 之类的命令，不要重新生成或另存。它是带 BOM 的 UTF-8，编码一变，PowerShell 5.1 显示的中文就会乱码。复制后对比哈希，确认开头 3 个字节是 `EF BB BF`。
2. 手动测一次：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<完整路径>"`。右下角应该弹出"Claude Code / Claude 已完成，等你回复"。没弹的话，请用户检查：设置 → 系统 → 通知，是否允许 "Windows PowerShell"；有没有开勿扰或专注助手。
3. 按 `templates/stop-hook.windows.json` 在 `settings.json` 顶层加 `hooks`，路径换成实际路径，反斜杠写两个。改之前给用户看。已经有 `hooks` 的话就合并，不要覆盖。
   - `args` 数组的写法在 Claude Code 2.1.325 上实测可用。如果提示 `args` 无效，改成单个 `command` 字段：`"command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\Users\\<用户名>\\.claude\\notify\\claude-notify.ps1\""`。
   - `async: true` 让会话不用等脚本里那 6 秒。
4. 验证：请用户随便问一句，回复结束时应该弹出通知。Windows 实测加上后的下一轮就会弹，不用新开会话。可能会闪一下 PowerShell 黑框，属于正常现象。这个脚本**不放声音**。如果用户想要提示音，可以加一行播放 `C:\Windows\Media\*.wav`，先让用户试听再选。
5. 和第 6 步一起，在"退回直连再进入聚合"之后确认 `hooks` 还在。

**macOS**（本仓库没有实测过）：可以把 `osascript` 作为 Stop hook 的命令，先在终端手动跑一次，确认能弹出通知。第一次运行时，系统可能要求在"系统设置 → 通知"里允许它发通知（推断）。

```json
"hooks": {
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "osascript -e 'display notification \"Claude 已完成，等你回复\" with title \"Claude Code\" sound name \"Glass\"'",
          "async": true
        }
      ]
    }
  ]
}
```

## 第 8 步：汇报

给用户一份汇总，内容包括：

- 共享文件夹在本机的路径；`@` 引用和 agents 链接是否生效。
- 前缀是否和源电脑一致；做了哪些 CCSwitch 界面操作。
- 分档映射查到了什么、有没有改、备份放在哪；"提示词"功能的状态。
- 第 4、5 步的结果表，以及代理日志里的异常，比如 400 和重试次数。
- 本机专属设置和通知是否生效；重写之后是否保留；用的是哪种 hook 写法。
- 没做或者没验证的项；对共享文件夹的修改建议（只列出来，不改）。

如果用户同意，可以把汇总写成 `setup/<系统>/install-report-<日期>.md` 放进共享文件夹，让源电脑那边的 Claude Code 审核。报告里只写脱敏后的值。

## 以后的维护

- 改规则或 worker：直接改共享文件夹里的文件，另一台电脑下次开会话就生效。
- 新增模型：在共享文件夹的 `agents/` 里加一个 worker，`model:` 写完整 ID。两台电脑 CCSwitch 的模型列表里都要有这个模型，1M 勾选状态也要一致。
- 共享文件夹里出现同步冲突副本时，告诉用户，不要自己合并或删除。
