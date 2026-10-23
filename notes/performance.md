# Neovim 性能调查与优化

> 本文记录 2026-10 这轮性能排查的结论、证据与改动。所有数字都是本机（Apple Silicon / nvim 0.12.4 / LuaJIT 2.1）实测。

## 结论速览

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 启动（`nvim --startuptime`） | 222ms | ~40–45ms |
| 首次按 `w`（中文分词） | 96ms | 4.5ms |
| 单行 700KB 压缩 JS：每次重绘 | 561.9ms | 3.7ms |
| 单行 700KB 压缩 JS：LSP 常驻 CPU | 100%（tsrs 4.95s + harper-ls） | 无子进程，clients=0 |
| 普通文件重绘（1578 行 Vue / 29k 行 d.ts） | 2–3ms | 2–3ms（本来就是好的） |

一句话总结：**syntax highlight 从来不是瓶颈**。真正的三块是启动期的 eager 插件加载、jieba 字典构建、以及 LSP semantic tokens 在超长行上的二次方重绘。

---

## 1. 启动：222ms → 40ms

`--startuptime` 定位后逐项干掉（每一项都复测过）：

| 改动 | 省 |
|---|---|
| `vim.fn.expand '$MASON/...'` → `vim.env.MASON` + `vim.fs.joinpath` | **30ms**（`$MASON` 未设置时这个调用在扫 `/packages`） |
| jieba/wordmotion 改为按键懒加载（`keys = w/b/e/ge/W/B/E/gE`，n/x 模式） | ~50ms |
| nvim-cmp / LuaSnip / console-log snippets 延到 `InsertEnter` | ~25ms |
| eslint-codemod 不再在 setup 里 `require('cmp')`（`pcall` 拦不住 lazy 的 require 钩子） | 含在上面 |
| mason / mason-lspconfig 延到 `VeryLazy`；fidget 延到 `LspAttach`；lazydev 提到顶层 `ft='lua'` | ~20ms |
| telescope 不再开机加载（去掉 `keymaps.lua` 顶层 `require 'telescope.builtin'`，spec 加 `cmd='Telescope'`，删掉 cmdr/theme 里把 telescope 当 eager 依赖的两行） | ~11ms |

剩余地板：`config.lazy` 约 28–32ms（lazy.nvim 自身元编程 + 30 个 spec 文件）。再往下只能换插件管理器或合并 spec，性价比不高。

## 2. jieba：Rust + FFI

- `lua/jieba-native/rust/`：`jieba-rs` 的 C-ABI cdylib，只跨边界传 `(start,end)` 字节偏移，不分配字符串；`just build-native` 构建并装到 `stdpath('data')/jieba-native/`。
- `lua/jieba-native.lua`：LuaJIT FFI 胶水，缺库时返回 `nil, reason` 并回退纯 Lua 实现；token 覆盖保证（jieba 丢掉的分隔符补成独立 token，因为 wordmotion 靠拼接 token 算偏移）。
- `init.lua`：启动后 1 秒后台预热共享实例，首次按键不再付字典构建的钱。

| 指标 | Lua 后端 | Rust 后端 |
|---|---|---|
| 首次按 `w`（含预热） | 96.3ms | **4.5ms** |
| `cut` 4200 字节 | 11.27ms | 0.082ms（137x） |
| `get_tokens` 3150 字节 | 9.05ms | 0.157ms（58x） |
| `Jieba::new()` 建字典 | 51.5ms | 46.6ms |

**代价**：jieba-rs 与 jieba-lua 词典版本不同，分词边界有差异（实测 5 个真实句子里 3 个不同，例如 `处理结果` vs `处理|结果`、`今天天气` vs `今天|天气`），`w`/`b` 的跳词粒度会略有变化。

**语言选择已是最优**：用 clang 17 `-O3` 编译 C++ 版 `cppjieba` 对比（同一份字典、同一段文本）：init 138ms、cut 4200B 0.106ms —— 都比 Rust 慢。rustc 与 clang 共用 LLVM 后端，codegen 极限调优（fat LTO + CGU=1 + `target-cpu=native`）在 cut 上只有约 10%，init 完全没变。瓶颈是词典 trie 构建与 DAG+DP，不是编译器。

## 3. 单行大文件 562ms/帧：LSP semantic tokens 的二次方

**症状**：700KB 单行压缩 JS 每次重绘 545–562ms；打开约 3 秒后才发作，重设 `filetype` 能瞬间恢复、3 秒后复发。

**排除法**（全部实测无效）：`vim.treesitter.stop()`、关闭 fold/ufo、关闭诊断、`statuscolumn=''`、`winbar=''`、`statusline=''`。

**定位**：macOS `sample` 采原生栈 2 秒，97% 的样本落在

```
win_line → decor_redraw_col_impl (+756) → _platform_memmove
```

对应 nvim 0.12.4 `src/nvim/decoration.c:753` 的「future range 按优先级插入 active 列表」：

```c
int *const item = indices + begin;
memmove(item + 1, item, (size_t)(cur_end - begin) * sizeof(*item));
```

每列插一次 → 同一行有 N 个 decoration range 时是 **O(N²)**。

再按命名空间数 extmark，真凶出现：

```
nvim.lsp.semantic_tokens:4    200000
```

nvim 0.11+ **默认开启 LSP semantic tokens**，压缩文件的那一行被塞进 20 万个 token extmark，于是每帧几十亿次 int 移动。清掉该命名空间后 561.9ms → 15.1ms；`vim.lsp.semantic_tokens.enable(false, { bufnr = buf })` 后 → 4.8ms。

**修复**（`lua/config/lsp.lua`）：新增 `LspAttach` 钩子，对**含超长行（>2000 字符）** 的 buffer 关闭 semantic tokens。扫描分块读取（每 2000 行一次 `nvim_buf_get_lines`），1.3MB / 29k 行实测 2.1ms，只在 attach 时执行一次。

| 文件 | 修复前 | 修复后 |
|---|---|---|
| `min.js`（1 行 / 700KB） | 561.9ms，200000 tokens | **3.7ms**，0 tokens |
| `weilapb.d.ts`（29k 行 / 1.3MB） | ~1ms | 0.9ms，88 tokens（保留） |
| `FloorStage.vue`（1578 行，maxlen=156） | 1.4ms | 1.4ms（不受影响） |

这是 nvim core 的问题（`decoration.c` 的插入策略），guard 只是绕过；值得给上游报一个带最小复现的 issue。

## 4. 为什么 syntax highlight 本身不是瓶颈

- nvim 0.12 的 `TSHighlighter.new()` 会自动把 `vim.bo.syntax` 清空（`runtime/lua/vim/treesitter/highlighter.lua:160`），所以不存在「regex + treesitter 双重高亮」。
- 每帧成本按视口算：1578 行 Vue 全窗重绘 2–3ms，29k 行 d.ts 同样 ~2ms（全量 reparse 68ms，只在大编辑/全量重载时付）。
- 逐帧 Lua 回调都很便宜：`snacks.statuscolumn` 0.0068ms/行、`winbar`+`statusline` 0.05ms/帧。
- FFI 调用 4ns、msgpack-RPC 往返 19µs —— 都远低于感知阈值。

## 5. 单行大文件：LSP 全部退让（bigfile guard）

修复 semantic tokens 之后，`min.js` 仍然会吃掉一个核：LSP server 在 `didOpen` 时解析整个文件。

实测（8 秒窗口）：

| | 修复前 | 修复后 |
|---|---|---|
| nvim CPU | 100% | 0.99s（首帧解析 700KB 单行的一次性成本） |
| 子进程 | `tsrs`(node) 4.95s、`harper-ls` 0.49s | 无 |
| `vim.lsp.get_clients` | 2 | 0 |

做法：

- `lua/bigfile.lua`：按 buffer 缓存（`changedtick` 变化才重算）的「超长行」判定（>2000 字符）。1.3MB / 29k 行的 `.d.ts` 首次扫描 1.2ms、命中缓存 0ms
- `lua/config/lsp.lua` 包住 `vim.lsp.start`：bigfile buffer 直接返回 nil，**服务进程不会 spawn**（nvim 0.12 的 `vim.lsp.config` 没有 per-buffer 开关、`vim.lsp.enable()` 是全局的，这是唯一能在 spawn 前拦住的点）
- 同时把 `harper_ls` 收窄到 `markdown/text/gitcommit/asciidoc`（lspconfig 默认还把它挂到 c/cpp/cs/go/js/ts，而它是文案检查器）

同一类 buffer 还要关掉 treesitter：parse 进行中时，**每一次重绘都会重新求值整棵树的 highlight query predicate**（`highlighter.lua:402` → `query:iter` → `get_node_text`），70 万字符单行上约 500ms/帧，表现就是"打开后卡死几分钟"。`lua/plugins/treesitter.lua` 现在对 bigfile buffer 直接跳过 `vim.treesitter.start`，退回 regex syntax（`synmaxcol=3000` 兜住成本）。

修复后实测（10 秒窗口）：`min.js` **0.39s CPU（0.4%）**、`syntax=javascript`、treesitter 未启动、clients=0；普通文件（Vue/TS）仍是 treesitter。

退让清单（按抓到的证据排）：

| 组件 | 证据 | 修复 |
|---|---|---|
| LSP server | `tsrs`(node) 8 秒用 4.95s CPU、`harper-ls` 0.49s | `vim.lsp.start` 拦住 spawn |
| treesitter 高亮 | `sample`: `query.lua:_match_predicates` → `get_node_text` → `strchr`，parse 期间每帧 ~500ms | 跳过 `vim.treesitter.start`，退回 regex `synmaxcol` |
| statusline 的 `virtcol("$")` | `sample`: `win_redr_status` → `build_stl_str_hl` → `f_virtcol` → `getvcol`，每帧整行扫描 | bigfile buffer 改用字节列 `%c` |

第三条是编辑卡顿的真凶：`mini.statusline.section_location` 返回 `%l|%L│%2v|%-2{virtcol("$") - 1}`，`virtcol('$')` 要扫完整行才能得到总虚拟列。每次重绘都算一次，70 万字符的单行就是 ~13ms/帧。

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 单字符编辑 + 重绘 | 15.1ms | **0.1ms** |
| 整窗重绘 | 13.5ms | **1.1ms** |
| 整窗重绘（光标在 40 万列） | — | 1.4ms |

注意 `%v`（`virtcol('.')`）同样是 O(光标所在列)，所以 bigfile buffer 里也没用它，而是 `%c`（字节列，O(1)）。

代价：这类 buffer 没有跳转/诊断/补全、没有 treesitter 高亮（只有 regex 语法色）、状态栏显示字节列而不是虚拟列；没有 marker 的目录里也不再有 TODO 计数（见下一节）。

## 6. 状态栏 TODO 计数在 `/tmp` 暴走

症状：在 `/tmp` 打开代码文件后，nvim 100% CPU，屏幕上是 `TodoComments` 浮窗 `rg failed with code 2` + 一串 `Permission denied`。

原因在 `lua/project-todos.lua`：

1. `project_root()` 在没有 `.git` 时兜底成 `vim.fn.getcwd()` —— 于是 `/tmp` 成了「项目根」，`rg` 扫遍整个 `/tmp`
2. `rg` 撞到不可读文件返回 2，`todo-comments` 弹错误通知，但状态栏每帧都会调用 `section()` → `count()` → `refresh()`，失败结果没有缓存/退避，于是反复重扫

修复：

- 项目根必须含 marker（`.git` / `package.json` / `pnpm-workspace.yaml` / `Cargo.toml` / `go.mod` / `pyproject.toml`），不再兜底任意 cwd
- 每个 root 30s 节流，`BufWritePost` 时清零（保存后立刻刷新）
- 回调里 `#(results or {})` 防御空结果

## 7. 尚未处理（按收益排序）

1. **保存时 lint 阻塞**：`lua/config/lsp.lua` 中 eslint 的 `BufWritePre: LspEslintFixAll` 与 oxlint 的 `oxlint_fix_all` 都是同步（`buf_request_sync`，最多 5 轮 × `vim.wait(300)`），大文件保存可能到几百 ms。未实测。
2. **LSP 冗余**：`tsrs` / `tsc` 新旧 TS server 二选一；`typos_lsp` 是否常用（`harper_ls` 已收窄到 prose）。
3. lazy `checker.frequency = 3600`：每小时对 45 个插件做网络 `ls-remote`，可改 86400。
4. `vim-wakatime`、`mini.test` 仍 eager（各 ~2.4ms）。
5. 上游 issue：semantic tokens + 超长行的二次方重绘。
