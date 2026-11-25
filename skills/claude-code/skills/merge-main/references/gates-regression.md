# Gates CI 本地回归与修复

仅在用户显式传入 `--gates` 时执行本阶段。先完成原有合并/rebase、冲突适配和基础验证，再运行本阶段；未加参数时不要扫描 workflow 或扩大测试范围。

## 1. 从合并后的 workflow 建立执行清单

1. 先读取仓库根 `AGENTS.md` / `CLAUDE.md` 及目标模块规则。涉及 GitHub Actions 时读取仓库的 workflow 文档；涉及仓库内技能或规则时遵循其维护流程。
2. 在当前合并结果中查找 `.github/workflows/gates-ci.yml`、`.yaml`，并检查其他 workflow 的 `name`、`jobs` 或 `uses` 是否引用 gates-ci。以合并后的 HEAD 为准，不使用目标分支旧文件或记忆代替。
3. 记录 workflow 文件、caller、触发事件、path filters、job 依赖与 `if`、workflow inputs、环境/工具版本、setup 步骤和最终测试命令。不要将 `moi-ci`、integration 或产品 E2E 自动并入 `--gates`，除非它们确实是 gates-ci 自身步骤。
4. 优先使用仓库提供的本地调度器/统一 Make 入口。它通常同时编码了路径选择、检查命令和工具版本，比手工复制若干 `run:` 更接近 CI。
5. 未找到 gates-ci 时报告 `SKIPPED (not configured)`，不拿通用测试冒充 gates-ci 回归。

对于有路径选择器的仓库，先记录**合并前当前分支 HEAD**。若最终目标 PR 的 base 就是本次目标分支，使用目标 remote/branch 最新 ref 作为 base，列出 `base...合并前 HEAD` 的三点 diff（实际 PR 变更集），完成合并后据此选择检查。PR base 无法确定时，退回到 `merge-base(合并前 HEAD, 目标 ref)..合并后 HEAD`，并标明这是本地近似选择。路径重命名同时检查新旧路径。不要错误地用合并后 merge commit 对目标分支的 `A...B` 差异代替 PR diff——那可能排除当前分支原有改动。

没有 PR 事件时不要伪造 `github.event` 或假设所有 selector 都为 true；按文档的本地/manual 模式运行，不能确定的 selector 单独报告。若仓库要求 planner 文件来自可信 base 而非当前分支，遵守该信任边界，并明确这是本地所选变更集的模拟，不冒充真实 PR 调度。

## 2. 分类执行，不把“没跑”写成“通过”

将步骤分为：

- **本地执行**：静态检查、格式化、lint、vet、单元测试、合同测试，以及环境已具备的集成依赖。
- **准备后执行**：可按照仓库 setup/action 文档安装或启用的工具、编译资产、测试容器。安装版本以 workflow、`go.mod`、`.nvmrc` 等事实源为准；不得把外部服务凭据写入日志。
- **CI 专用**：GitHub 事件/checkout/artifact/label/schema Action、runner 标签、secrets 或部署发布。寻找仓库定义的本地合同测试；无法等价复现时标为 `NOT RUN`，记录原因，不视为失败，也不宣称通过。

遵循 workflow 的 `needs` 和串行前置条件；真正独立且资源足够的检查可并行。注意 Node/pnpm workspace、编译缓存和测试数据库等共享资源，不能为了并行制造假失败。

若 workflow 提供手动全量入口且环境满足，默认跑所选 gates 的完整本地等价检查；环境不足时先跑受影响的最小充分集合，再明确列出未覆盖项。不要把手动筛选的测试集合称为“gates 全绿”。

### MatrixFlow 实例

当前 MatrixFlow 的 `gates-ci.yml` 是统一 `gates` job。先读 `.github/workflows/README.md`、`pr-ci.yml` 和当前 `.github/scripts/pr_ci_path_plan.py`。将确定后的 PR diff 路径写入临时 JSONL，用 planner 的 `--files-jsonl` 生成实际 selector；planner 信任边界和 `PR_CI_*` 开关按当前 CI 文档处理。然后映射到 `parallel_go_gates.py --all-checks --phase checks` 的同名参数，另运行所选独立前置步骤；`run_moi=true` 时按 workflow 最后运行 `--phase deadcode --moi true`。

workflow 的命令必须在仓库根目录运行。检查 Python 3.11 和 `CI_PYTHON_311`，按当前 runner 要求创建 `base/<BASE_REF>` 本地 ref、准备 `make ensure-moi-assets` 等资产；`BASE_REF` 取目标分支名。runner 硬编码 `base/<BASE_REF>`，不能只在命令行指定 `upstream/dev` 而不创建对应 ref。不要把过往运行结果或另一 worktree 的结果当作当前合并结果的证据。原生集成属于 `moi-ci`，不因 `--gates` 自动运行。

## 3. 失败 -> 归因 -> 修复 -> 回归

1. 保存每个检查的命令、工作目录、退出码和关键失败输出；完整日志放仓库外的临时目录。不要只凭最后一行猜根因。
2. 区分合并引入的回归、当前分支已有问题、目标分支已有问题、环境问题和偶发失败。需要基线对照时使用独立 worktree，避免切换/覆盖当前工作树。
3. 对合并回归，复查双方实现意图、调用方、mock、fixtures、测试资产和外围工具。修复真正的 owner/实现或随合同更新测试，保留必要回归覆盖。
4. 不得通过跳过测试、放宽断言、缩减扫描、增加例外/白名单、调整阈值或超时来换取通过。确需修改门禁本身，先展示原始失败证据、修改原因、影响范围和验证方式，并取得用户明确授权。
5. 按批次处理当前失败：先修同批根因，再运行受影响的定向测试；定向通过后复跑整个所选 gates 集合。只有最终实际退出码和日志均成功，才标为 `PASS`。测试发现为 0、意外 skip、缺少目标测试或预期 artifact 时，退出码 0 也不是有效通过；先核对发现规则与路径，不能靠添加例外掩盖。
6. 环境阻塞时保留代码修复证据，标为 `BLOCKED`，给出缺少的工具/服务/权限及可执行的后续命令。不要把“安装成功”或“部分测试成功”当作完整回归。

修复 gates 失败后，再检查一次基础编译/vet/相关测试是否仍通过。已有未提交改动时不得回退或夹带无关文件。

## 4. 提交边界与报告

原 Step 7 已完成合并；gates 修复属于后续变更，不要通过 amend 或再次 `git commit` 擅自制造提交。展示新增 diff，按现有用户授权和对应提交流程处理。rebase 完成后的修复也不能默认 rebase 回历史。

报告逐项包含：

```text
Gates workflow: <path> / <job>；caller: <path or none>
Selection: <base..head / manual scope / unavailable>
PASS: <实际运行的检查与命令>
FIXED: <失败 -> 根因 -> 修复文件 -> 定向与全量复跑结果>
FAIL: <仍失败的检查、直接证据与下一步>
NOT RUN / BLOCKED: <CI-only 或缺失环境；本地等价覆盖范围>
Commit: <merge/rebase commit>；gates fixes uncommitted unless separately authorized
```

若用户明确要求远端 CI 跟进，先确认 push/dispatch 已获授权，再核对当前 head 的 `gates-ci / gates` 结果。远端 pending、旧 head 成功、workflow_dispatch 启动成功均不等于 gates 通过。
