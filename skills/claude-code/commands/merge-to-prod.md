从最新 main 创建分支，合并最新 prod，推送并创建 PR 到 prod。

Input: $ARGUMENTS (可选 flags: --dry-run 只显示将要合并的 commits 不执行)

触发短语: "merge to prod", "sync main to prod", "pr to prod", "deploy to prod"

## 流程

### 1. Fetch 最新远程分支

```bash
git fetch origin main prod
```

### 2. 计算日期后缀

格式: YYMMDD (当天日期，如 250527)

### 3. 创建新分支

```bash
git checkout -b merge-main-to-prod-<YYMMDD> origin/main
```

如果分支已存在，追加序号: `merge-main-to-prod-<YYMMDD>-v2`

### 4. 合并 prod

```bash
git merge origin/prod
```

- 无冲突 → 继续
- 有冲突 → 列出冲突文件，尝试解决，解决后 commit；无法自动解决则告知用户

### 5. 检查 diff (--dry-run 到此停止)

```bash
git log --oneline origin/prod..HEAD
```

展示将被合并到 prod 的 commits 数量和摘要。

### 6. Push

```bash
git push -u origin merge-main-to-prod-<YYMMDD>
```

### 7. 创建 PR

**PR title 格式**: `deploy {component1,component2,...} (<MMDD>)`

从 commits 中提取涉及的业务组件关键词，去重后以逗号分隔放入 `{}`。

组件识别规则（按 commit message 和**仅关注的文件**判断）:
- `moi-taas` — taas 相关
- `moi-core` — moi-core 子 chart (moi-backend/moi-catalog/moi-mowl/go-worker/python-worker)
- `moi4x` — MOI 4.x pipeline (cos-component 目录下的 mowl/catalog-service/workflow-scheduler)
- `moi5x` — MOI 5.x 整体 (cloud-service 目录)
- `mo` — MatrixOne 数据库相关
- `apiserver` — apiserver 服务
- `unoserver` — unoserver 服务
- `moi-frontend` — 前端相关
- `infra` — 基础设施/集群变更

**关注范围**: 只关注公共代码、`Pulumi.yaml` 和 `Pulumi.prod.yaml` 的变更。
**忽略**: `Pulumi.new-dev.yaml`、`Pulumi.qa.yaml` 及其他环境配置文件的变更。

识别组件和版本时，仅从 `Pulumi.yaml` / `Pulumi.prod.yaml` 的 diff 和公共代码变更中提取。

从 commits 中提取 image tag 版本号（如 `0.2.0`, `5.0.0-d6b28e2b` 等），多个版本用逗号分隔。

示例:
- `deploy(prod): {moi-taas} 0.2.0 (250527)`
- `deploy(prod): {moi-core,moi-frontend} 5.0.1 (250315)`
- `deploy(prod): {moi4x,moi-taas} 4.1.8,0.2.0 (250601)`

如果无法识别具体组件，用 `deploy(prod): {config-updates} (250527)`。

```bash
gh pr create --base prod --title "deploy(prod): {<components>} <tag-version> (<YYMMDD>)" --body "<body>"
```

PR body 结构:
```
## Summary
- <按类别归纳 commits: feat/fix/chore>
- 列出主要变更（不超过 10 条）

## Commits (<N>)
- <每条 commit 一行摘要，最多列 20 条>
```

### 输出

```
✅ Branch: merge-main-to-prod-<YYMMDD>
✅ Merged: origin/prod (no conflicts)
✅ Commits to prod: <N>
✅ Pushed: origin ← merge-main-to-prod-<YYMMDD>
✅ PR: <url>
```
