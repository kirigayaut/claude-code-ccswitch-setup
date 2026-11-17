# 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| worker 发出的请求失败，或者跑在了别的模型上 | 两台电脑的 stack key（前缀）不一样 | 不要改 worker。在新电脑上新建一个和源电脑**初始名字相同**的供应商，不选图标，加入聚合（SKILL 第 1 步） |
| 改了供应商名字，前缀还是旧的 | key 在第一次加入聚合时就固定了 | 同上，新建供应商 |
| 新建供应商后，所有分档都变成了某个奇怪的模型（比如 DeepSeek 或 haiku） | 模型列表里排第一的就是主模型 | 把 opus 模型调到第一位：删掉排在它前面的模型再加回来，它们就会排到后面 |
| 自动模式下工具调用频繁被拦，会话被中止 | 隐藏的 SONNET 档是只接受 adaptive thinking 的模型，分类器带 `thinking.type=enabled` 发请求时收到 400 | 用 SQL 把 SONNET 档改成能接受 enabled thinking 的模型，比如 `claude-sonnet-5`（SKILL 第 3 步） |
| 分类器请求被转到了非 Claude 模型 | 新建供应商时，隐藏分档被设成了当时排第一的模型 | 同上，改三个隐藏分档 |
| 退回直连后用的是已经弃用的旧供应商 | `is_current` 还指着旧供应商 | 退回直连，再进入聚合，进入时选新供应商 |
| `model: haiku` / `model: sonnet` 的子代理实际跑在 opus 上 | 聚合模式下四个分档都是主模型 | 不传 `model`，改用写了完整 ID 的 worker |
| 建好 junction 后，worker 没出现在可用 agent 类型里（Windows） | Windows 上要等下一轮对话才加载 | 让用户随便回一句；还没有就新开会话 |
| 子代理记录里有两条参数相同的 `api-request` | 第一次请求被上游拒了，Claude Code 自动重试 | 查 `proxy_request_logs.error_message`。如果是 `output_config: Extra inputs are not permitted`（错误信息里有 Bedrock 字样；推测是中转把请求分到了不支持 effort 的后端），偶尔出现、重试能成功的话不用处理，频繁出现就反馈给中转 |
| 已经征得用户同意，改 `settings.json` 仍被自动模式拦下，理由还对不上（比如"改了 model""动了 env"） | 自动模式的权限检查误判 | 请用户临时切到手动确认模式，或者让用户自己粘贴。**不要换工具绕过** |
| 自动模式拦下下载工具（比如 sqlite3） | 下载来源是 agent 自己选的 | Windows 上改用系统自带的 `winsqlite3.dll`（`scripts/ccs-query.ps1`）；或者请用户指定来源 |
| 用 Write 新建 `~/.claude/CLAUDE.md` 被当成覆盖拦下 | 权限检查不知道这个文件原本不存在 | 先确认文件不存在，再用"只在不存在时创建"的方式写，比如 .NET 的 `FileMode.CreateNew` |
| `python` 运行后返回 9009（Windows） | 那只是 Microsoft Store 的占位程序 | 别用它，用 `winsqlite3.dll` |
| 通知弹出来了，但中文是乱码（Windows） | 脚本丢了 UTF-8 BOM | 用复制文件的方式重新复制，不要另存 |
| 通知弹出来了，但没有声音（Windows） | 脚本本身不放声音，或者电脑没有可用的扬声器 | 先确认电脑能出声，再在脚本里加一行播放 `C:\Windows\Media\*.wav` |
| winget 报 `0x8a15000f 缺少源所需的数据`，或者 `api.github.com` 连不上（Windows 实测，发生在装 git/gh 时，不在安装步骤里） | Windows 开了系统代理（`127.0.0.1:<端口>`），代理对这些域名不通；不走代理时可以直连 | 先用 `curl.exe --noproxy '*'` 测一下。用户同意的话，从官方发布页下载，下载后核对 SHA256 |
| `git push` 报 `Empty reply from server` / `Connection was reset`（Windows 实测） | git 不读 Windows 的系统代理设置，只认 `http.proxy` 配置和环境变量，所以会直连；在某些网络下直连 github.com 会被重置。gh 同样直连，访问 api.github.com 反而正常 | 只给这一次推送加代理：`git -c http.proxy=http://127.0.0.1:<端口> push`。哪条路能通取决于网络环境，直连和走代理都试一下 |
| `datetime(created_at,'unixepoch','localtime')` 返回 NULL（Windows 实测，winsqlite3 3.43.2） | 原因没查 | 直接用整数比较 `created_at` |
| 同时开着两个会话，都在执行安装步骤 | 两边都可能改 `settings.json`，会互相覆盖 | 只保留一个会话执行，另一个停下或者只读 |
