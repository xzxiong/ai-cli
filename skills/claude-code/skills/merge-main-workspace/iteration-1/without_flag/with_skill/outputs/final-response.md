合并已提交，但修复和验证被权限策略阻塞：

- 已将本地 `main` 合并到 `feature`，merge commit：`0e66f21`。
- Git 未报告文本冲突，自动保留了 feature 的 `add(a, b) = a - b`。
- main 新增 `test_merge_regression`，预期 `add(5, 3) == 8`；当前实现与该断言不符。
- 尝试将 `calc.py` 修为 `a + b`，但编辑被自动拒绝；测试命令也未获执行许可，因此**问题尚未修复，测试未运行**。
- 未运行额外 gates 回归，未 push、amend 或追加 commit。
- 工作区干净，仓库无 remote。
