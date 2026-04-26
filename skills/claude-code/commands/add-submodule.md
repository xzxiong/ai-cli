在当前仓库的 third/ 目录下添加 git submodule，并更新 AGENTS.md。

Input: $ARGUMENTS (repo URL, 可选: --name <dir>, --branch <branch>)

## 流程

### 1. 确认在 git 仓库中
```bash
git rev-parse --is-inside-work-tree
```

### 2. 从 URL 推导目录名
```
git@github.com:matrixorigin/mocloud-services.git → mocloud-services
https://github.com/matrixorigin/matrixone.git    → matrixone
```
用户 `--name` 指定则使用指定值。

### 3. 检查是否已存在
```bash
git submodule status third/<dir> 2>/dev/null
```

### 4. 添加 submodule
```bash
mkdir -p third
git submodule add [-b <branch>] <repo-url> third/<dir>
git submodule status third/<dir>
```

### 5. 更新 AGENTS.md
在 `## Submodules` 段落下追加 `### third/<dir>` 小节，包含初始化和更新命令。
如果已有该小节则跳过。如果 AGENTS.md 不存在则创建。

### 6. 输出
```
✅ Submodule 已添加: third/<dir> ← <repo-url>
✅ AGENTS.md 已更新
下一步: git commit -m "chore: add submodule third/<dir>"
```
