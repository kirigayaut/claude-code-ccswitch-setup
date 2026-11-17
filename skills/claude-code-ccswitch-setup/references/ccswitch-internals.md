# CCSwitch 聚合模式：内部机制与证据

这份文档记录在 CCSwitch 4.0.32 上观察到的行为。证据分三种：

- **Windows 实测**：2026-11 在 Windows 10、Claude Code 2.1.325 上实际验证过。
- **Mac 实测**：在源电脑（macOS）上验证过。
- **推断**：根据现象推出来的，没有直接证据。

CCSwitch 换版本后，这些行为可能会变。拿不准的时候，先按这里的方法重新验证。

## 文件和数据在哪里

| 位置 | 内容 |
|---|---|
| `~/.cc-switch/cc-switch.db` | SQLite 数据库，journal_mode 是 `delete`。下面列出相关的表 |
| `~/.cc-switch/live-state.json` | 每个应用当前用的模式、聚合模式的路由、成员和 **stack key** |
| `~/.cc-switch/logs/cc-switch.log` | 运行日志：代理转发记录（`请求目标: … (model=…)`）和模式切换记录（`[MODE] …`） |
| `~/.cc-switch/backups/` | CCSwitch 自己做的数据库备份，也适合放你手动做的备份 |
| `~/.claude/settings.json` | 由 CCSwitch 生成。聚合模式下 `env.ANTHROPIC_BASE_URL=http://127.0.0.1:15721`，`ANTHROPIC_AUTH_TOKEN=PROXY_MANAGED` |

### 数据库里相关的表

- `providers`：主键是 `(id, app_type)`。和 Claude 相关的列有这些：
  - `name`：显示名
  - `icon`：内置图标名，可以为空
  - `is_current`：直连模式下当前用的供应商
  - `settings_config`：JSON，里面的 `env` 有 `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_MODEL`、`ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS}_MODEL` 等
  - `meta`：JSON，里面的 `stackModels` 是编辑页里的模型列表，**顺序有意义**，带 `oneM` 标记
- `proxy_request_logs`：每次经过代理的请求一行。列有 `request_model`（客户端请求的模型名）、`model`（实际转发的模型名）、`status_code`、`error_message`、`provider_id`、`created_at`（**Unix 秒数**）。
- `prompts`：CCSwitch "提示词"功能的数据，Claude 用的那部分对应 `~/.claude/CLAUDE.md`。

### live-state.json 的结构（节选）

```json
"claude": {
  "mode": "proxy",
  "proxy_route": "<默认供应商 id>",
  "stack": {
    "enabled": true,
    "members": ["<供应商 id>", "..."],
    "keys": { "<stack key>": "<供应商 id>", "...": "..." }
  }
}
```

## 模型名前缀与路由

- 聚合模式下，picker 里的模型名格式是 `ccs-claude-<stack key>--<模型>`，勾了 1M 的还会带 `[1M]`。代理按前缀找到对应的供应商，再按 `--` 后面的部分转发模型。（Mac 实测、Windows 实测）
- 不带前缀的模型名，比如自动模式权限分类器请求的 `claude-sonnet-5`，会转给**默认供应商**，并按该供应商数据库 env 里的 `ANTHROPIC_DEFAULT_*_MODEL` 分档映射。（Windows 实测：改了数据库里的 SONNET 档之后，下一条分类器请求的 `model=` 立刻就变了）
- 客户端发出去的请求里，model 没有 `[1M]` 后缀，1M 改成用 beta 请求头表示。（Windows 实测）

## stack key 是怎么来的

- 供应商**第一次加入聚合**时生成。供应商有内置图标就用图标名；没有就把名字转成小写，空格换成 `-`，比如 "MyRelay LLM" 变成 `myrelay-llm`，"X｜Anthropic" 变成 `x-anthropic`。（Mac 根据 CCSwitch 源码确认；Windows 实测了按名字生成）
- **生成以后就固定了**。下面几种操作都不会改变 key：
  - 改名：只有 picker 里的显示名会变（Windows 实测）
  - 聚合模式退回直连，再进入聚合（Windows 实测）
  - 默认路由切到别的供应商，再切回来（Windows 实测）
- key 不存在数据库里，只存在 `live-state.json`。界面里没有修改入口。
- 删除供应商之后，`live-state.json` 里它的 key 还会留着。它不在 `members` 里，所以没有影响。（Windows 实测）以后再新建一个同名供应商时，残留的 key 会不会导致新 key 被改名，没有测过；加入聚合后要去 `live-state.json` 核对实际生成的 key。
- 想在另一台电脑上得到同样的 key：新建一个供应商，用相同的初始名字，不选图标（源电脑的 key 如果来自图标名，就选同一个图标），然后加入聚合。（Windows 实测了不选图标的情况）

## 主模型与分档

- `meta.stackModels` 的**第一个**模型，就是这个供应商的 `ANTHROPIC_MODEL`（主模型）。编辑页里没有单独设主模型的地方。（Windows 实测：顺序先后让主模型变成了 DeepSeek、haiku、opus，每次都跟着第一个变）
- 聚合模式写进 `settings.json` 的四个分档 `ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS,FABLE}_MODEL`，全都是**带前缀的默认供应商主模型**。所以 Agent 工具里用 `model: haiku` 这类别名不起作用。（Mac 实测、Windows 实测）
- 在模型列表里删掉一个模型再加回来，它会排到**最后**。可以用这个办法调顺序。（Windows 实测）
- 数据库 env 里的 `ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS}_MODEL` 这三个隐藏分档，在**新建供应商时**被设成当时排第一的模型。之后在编辑页保存，即使主模型变了，它们也**不会更新**。（Windows 实测：主模型从 DeepSeek 变成 haiku 再变成 opus，三个分档一直停在 DeepSeek）
- 直接用 SQL 改这三个键，改完立即生效（Mac 实测、Windows 实测）。之后重启 CCSwitch 或在编辑页保存，都不会被还原（Mac 实测）。退回直连再进入聚合、删除别的供应商之后，值也保持不变（Windows 实测）。

## is_current 与模式切换

- 聚合模式按 `live-state.json` 的 `proxy_route` 路由，不看 `is_current`。（Windows 实测）
- 退回直连时，确认框默认落到 `is_current` 指向的供应商。（Windows 实测，日志："回到直连确认框：确认，落到 <id>"）
- 进入聚合时选哪个供应商，那个供应商就会被设成 `is_current=1`。（Windows 实测）
- 每次进入聚合或切换路由，日志里都会出现"客户端配置已重写"，`settings.json` 被整个重写一遍：
  - `env`、`modelPicker` 会被覆盖，顶层的 `model` 可能被删掉。
  - `modelSettings`、`autoCompactWindow`、`hooks`、`theme` 原样保留，只是位置和缩进可能变。（Windows 实测）

## 提示词功能

- CCSwitch 的"提示词"功能管理的是 `~/.claude/CLAUDE.md`。启用或切换一条 Claude 提示词，可能会覆盖 `@` 引用那一行。如果用共享 `rules.md` 的方案，就不要在 CCSwitch 里管理 Claude 的提示词。（推断：来自 Mac 上的使用经验和表结构，没有在 Windows 上触发过）

## 子代理记录

- 位置：`~/.claude/projects/<项目目录名>/<会话 ID>/subagents/agent-<id>.jsonl`，旁边还有一个 `.meta.json`。
- `type: "api-request"` 的条目：`querySource` 形如 `agent:custom:<worker 名>` 或 `agent:builtin:general-purpose`；`params.model`；`params.output_config.effort`。
- `type: "assistant"` 的条目：`message.model` 是上游实际返回的模型；`requestedModel`；`effort`。
- 没传 `effort` 时，子代理继承主会话当前的 effort。（Windows 实测：general-purpose 子代理用了 xhigh）
