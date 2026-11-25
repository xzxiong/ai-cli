未能完成修复与门禁验证，因当前会话没有审批入口，以下操作被权限策略自动拒绝：

- 编辑 `calc.py:2`，将 `return a - b` 修复为 `return a + b`
- 执行 `gates-ci` 命令：`python3 -m unittest -v test_calc.py`

已确认：

- `feature` 已包含 `main`；`git merge main` 返回 `Already up to date`
- 无未解决冲突，工作区保持干净
- 两个回归测试均要求加法语义
- 未 push、未 amend、未创建额外 commit

需要允许文件编辑和测试命令后，才能完成修复及验证。
