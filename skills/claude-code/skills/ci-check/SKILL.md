---
name: ci-check
description: 检查 GitHub PR CI、用少量后台轮询等待终态，并只在失败时读取局部日志。用户说“检查 CI”“CI 怎么样了”“CI 跑完告诉我”“继续等 CI”“看新 CI 结果”、给出 PR/Actions URL，或刚 push/rerun 后需要跟进时使用。重点是减少助手轮次和 token，不自动修复或 rerun。
---

# CI Check

只使用 `gh` 和简单 Bash，不引入 Python helper、状态机或测试框架。

## 1. 先查一次

```bash
gh pr view <PR> --repo <owner/repo> --json headRefOid,statusCheckRollup \
  --jq '{head: .headRefOid, checks: [.statusCheckRollup[] | {name: (.name // .context), status, conclusion: (.conclusion // .state)}]}'
```

fork PR 的 `--repo` 填目标仓库，不是 fork 仓库。确认 head 是用户关心的提交；全绿时不读日志，不查无关元数据。

`statusCheckRollup` 为空不代表通过：新 head 可能尚未创建检查，合并后的 PR 也可能不再展示 rollup。此时报告“当前无检查摘要”，不要拿旧 head 的结果替代。

## 2. 未结束时只启动一个后台等待

**多次检索都是“等待”时，要增加 `interval` 参数，不要固定每分钟轮询。** 初始 `interval=60`，每次仍 pending 就扩大为 `120 → 240 → 300` 秒，封顶 5 分钟；状态或 head 变化后可重置为 60 秒。由同一个后台任务调整等待间隔，不反复手动检索。

使用 Bash 的 `run_in_background: true`，把下面 `<PR>`、`<owner/repo>` 替换为真实值。不要在助手回合里反复 `gh pr checks`。

```bash
pr=<PR>
repo=<owner/repo>
interval=60
end=$((SECONDS + 7200))
while (( SECONDS < end )); do
  if output=$(gh pr checks "$pr" --repo "$repo" 2>&1); then
    printf 'CI terminal: PASS\n%s\n' "$output"
    exit 0
  fi
  code=$?
  if (( code != 8 )); then
    printf 'CI terminal: FAIL or query error (exit=%s)\n%s\n' "$code" "$output"
    exit "$code"
  fi
  sleep "$interval"
  (( interval < 300 )) && interval=$((interval * 2 > 300 ? 300 : interval * 2))
done
printf 'Watch timeout after 2h; this is not a CI failure.\n'
exit 4
```

等待间隔为 **60 → 120 → 240 → 300 秒**封顶。中间 pending 不输出，只有终态或超时输出一次，节省对话轮次和 token。`gh pr checks` 的 pending 退出码当前为 8；如果你的 gh 版本不同，先用 `gh pr checks ...; printf '%s\n' "$?"` 确认。

- 已有同一 PR 的后台任务时，等它的通知，不重复启动。
- 换 head 后停止旧 watch，再启动新的 watch。
- 超时不是 CI 失败；需要继续时重新建立一个 watch。

## 3. 失败才读取局部证据

```bash
gh run view <run-id> --repo <owner/repo> --log-failed > /tmp/ci-failure-<run-id>.log
```

只读匹配失败位置的少量上下文：

```bash
python3 -I -c 'from pathlib import Path
lines = Path("/tmp/ci-failure-<run-id>.log").read_text(errors="replace").splitlines()
hits = [i for i, line in enumerate(lines) if any(k in line for k in ("--- FAIL:", "Error Trace:", "panic:", "context deadline exceeded", "Process completed with exit code"))]
for i in hits[-10:]:
    print("\n".join(lines[max(0, i-2):i+4]))'
```

先用 job 的最终状态和失败 step 确定真实失败；`::error`、重试记录、模拟失败不等于 job 失败。未定位根因时明确说“只有失败证据”，不要猜。其他 PR 的同签名失败或上游修复仅是证据，不自动等于本 PR 根因。

只检查，不自动 rerun、改代码、推送、调整门禁、合并或编辑 PR。后续操作按用户已有授权和对应工作流处理。

## 汇报

用 3–6 行说明：当前 head、CI 通过/失败/进行中、失败测试的一行直接证据、后台等待或后续动作。只有实际查过才报告 review/merge 状态；CI 全绿不等于产品端到端验收。
