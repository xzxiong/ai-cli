✅ 已将 `main` 合入 `feature`，生成 merge commit `d5b8c1c`。

- **文本冲突**：0；合并自动完成。
- **问题根因**：`feature` 的 `add` 错误实现为 `a - b`。
- **修复**：`calc.py:2` 改为 `a + b`，未修改测试。
- **回归结果**：修复前 pytest 两项失败；修复后 **2 passed**。
- **gates-ci 说明**：workflow 配置的 `python3 -m unittest -v test_calc.py` 实际发现 **0 tests**，退出码为 0；因此另用 pytest 执行了文件中的两项断言。

修复按要求保留为未提交修改，最终仅有 `M calc.py`。未 push、未 amend、未创建额外 commit。
