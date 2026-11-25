# 4.6 数据访问 / SQL 专项审查

> 触发条件：diff 中出现 SQL（裸 SQL / GORM / sqlx / 其他 ORM / 存储过程 / migration）、DB 事务、权限相关的 SQL（GRANT / REVOKE / SET ROLE / USE ACCOUNT 等）、或调用 `db.Query/Exec/First/Find/Transaction` 等数据访问入口。
>
> 不触发时输出「**4.6 不适用**（本 PR 无数据访问变更）」跳过整节。

---

## D1. SQL 必要性（是否存在「不必要」的 SQL）

逐条 SQL 反问：**「这条 SQL 真的必须吗？」**

- **可消除**：能否复用同函数内已查出的对象/字段，避免重复 SELECT？
  - 反例：刚 `First(&user)` 拿到 `user.TenantID`，紧接着又 `SELECT tenant_id FROM users WHERE id=?`
- **可合并**：相邻两次 `SELECT a` 和 `SELECT b` 同表/同条件，能否一次 `SELECT a,b`？
- **可下移**：在循环外的查询，能否移到循环内按需惰性触发？反之，循环内的查询能否提到循环外批量？
- **可删除**：写入后立刻 SELECT 回读，只为拿到刚写入的字段？（多数驱动支持 RETURNING / LastInsertId）
- **死代码**：查询结果未被使用？或仅在 log/debug 中用到？

输出：
- 🟢 **可优化**：能省 1 次 RTT，但不影响正确性
- 🟡 **建议删除/合并**：明显冗余
- 🔴 **必须修改**：在热路径上造成可量化的额外 RTT

## D2. N+1 检测

**识别模式**（在 diff 中 grep 以下组合）：

```go
// 反例 1：range 内查询
for _, item := range items {
    db.Where("parent_id = ?", item.ID).Find(&item.Children)  // N+1
}

// 反例 2：range 内写入
for _, id := range ids {
    db.Create(&Record{ID: id})  // 应改为 CreateInBatches / 单条 INSERT...VALUES (...),(...),(...)
}

// 反例 3：range 内 UPDATE / DELETE
for _, u := range users {
    db.Model(&u).Update("status", "active")  // 应改为 WHERE id IN (...)
}
```

**反向验证**：
- 该函数被调用时，循环上限是多少？（N=10 vs N=10000 差异巨大）
- 是否已在调用方做了 batch / preload / join？
- ORM 的 Preload 是否被遗漏？

**允许 N+1 的例外**（需作者在代码注释中说明）：
- N 明确 ≤ 5 且非热路径
- 子查询依赖前一次结果（链式）
- 涉及外部服务调用无法 batch

输出：
- 🔴 热路径 N+1（QPS > 1 或 N 可能 > 100）
- 🟡 温路径 N+1（低频调用但可改写）
- ✅ 已使用 Preload / JOIN / IN (...) / batch 写入

## D3. SQL 效率（单条 SQL 本身是否高效）

- **字段选择**：是否 `SELECT *`？改为显式列名（减少 IO + 网络）
- **WHERE 走索引**：查询条件是否命中索引？
  - 反例：`WHERE DATE(created_at) = '2026-11-06'`（函数包裹列，索引失效）
  - 反例：`WHERE name LIKE '%foo%'`（前缀通配，索引失效）
- **JOIN 顺序**：驱动表是否是小表？
- **LIMIT**：返回行数是否有上限？无 LIMIT 的 SELECT 在数据量增长后变慢查询
- **COUNT(*)**：大表 COUNT 是否有近似值/缓存替代？
- **OFFSET 翻页**：深翻页（OFFSET > 10000）是否改用 keyset pagination（`WHERE id > ?`）？
- **OR vs IN**：多个 OR 同字段条件，能否合并为 `IN (...)`？
- **DISTINCT**：是否必要？能否用 GROUP BY 或先去重后 JOIN？

输出示例：
```
🟡 I-N — pkg/store/user.go L142
问题：ListUsers 使用 `SELECT * FROM users WHERE name LIKE '%'+kw+'%'`，索引失效且返回所有列
建议：1) 显式列出所需字段 2) 若为前缀匹配，改为 `LIKE kw+'%'` 或加全文索引
```

## D4. 权限 / 越权 SQL

> 任何涉及鉴权、租户隔离、行级权限的 SQL 必须审查。

**鉴权查询**：
- 是否每次请求都重新查权限？还是信任了上游已注入的 user/tenant context？
- 权限查询是否带缓存？缓存失效策略？
- 权限判断是否在 SQL 层完成（`WHERE tenant_id=?`），还是在应用层（拿到数据后再 filter）？
  - **🔴 反例**：先 `SELECT * FROM orders` 再 `if order.TenantID == ctx.TenantID` —— 已造成跨租户扫描，且行数大时性能差

**DDL / 管理操作**：
- `GRANT / REVOKE / CREATE USER / DROP / ALTER` 是否仅允许在 migration 或 admin 路径中执行？
- 是否校验调用方角色后再执行？还是直接信任参数？
- 权限变更是否有审计日志？

**SQL 注入**：
- 是否使用参数化查询？（`db.Where("id = ?", id)` ✅；`db.Where("id = " + id)` 🔴）
- 动态表名/列名是否经过白名单校验？

**租户隔离**：
- 所有跨表 JOIN 是否都带 `tenant_id` 过滤？
- 子查询 / EXISTS 是否也带租户条件？（🔴 高频漏洞）

输出：
- 🔴 任何未参数化的 SQL、任何在应用层过滤租户、任何未审计的权限变更
- 🟡 权限查询无缓存 / 缓存时间过长
- ✅ 参数化 + 索引化 tenant_id + 权限变更有审计

## D5. 事务边界

- 事务范围是否最小化？（事务内不做网络调用 / 文件 IO / 长计算）
- 事务内是否有 SELECT ... 然后基于结果 UPDATE 的模式？是否需要 `SELECT ... FOR UPDATE` 或乐观锁（version 列）防丢失更新？
- 事务内是否调用其他服务 / 发消息？（分布式事务问题）
- 错误处理：事务内任一步失败，是否 defer rollback？
- 长事务：是否有预估时长？可能阻塞 DDL / 备份？
- **MatrixOne 特别注意**：MO 是 READ COMMITTED（RC），**不存在 REPEATABLE READ**。事务内多次 SELECT 看到的是不同快照，不要假设"同一事务内视图一致"。
  - 🔴 反例：在事务内先 `SELECT count` 判断存在性，再 `INSERT`，假设中间不会有别的 txn 插入——在 RC 下会出唯一键冲突

## D6. Migration / DDL

- 新增索引：`CREATE INDEX` 是否并发安全（Postgres `CONCURRENTLY` / MO 对应的 online DDL）？
- 新增列：是否有 DEFAULT 值？大表 ADD COLUMN NOT NULL DEFAULT x 是否锁表？
- 删列 / 改列类型：是否有存量数据兼容方案？
- 回滚：down migration 是否实现了？
- Migration 是否幂等？（重复执行安全）

## D7. 读写一致性

- 写后立即读，是否保证读到？（读写分离场景）
- 缓存与 DB 是否双写一致？失效顺序？
- 是否存在"先删缓存再写 DB"导致的脏读？

---

## 输出模板

每条 finding 使用标准 `I-N` 编号，引用文件/行：

```
<a id="issue-N"></a>
**🔴/🟡/🟢 I-N** — `<file_path>` L<line>
类别：D1 不必要 SQL / D2 N+1 / D3 低效 SQL / D4 权限越权 / D5 事务 / D6 Migration / D7 一致性
问题：<具体描述 + 触发场景>
影响：<RTT 增加 / 越权 / 死锁 / ...>
建议：<改写示例 或 验证方式>
```

**整节结论**：
- ✅ 数据访问无问题
- 🟡 存在 N 条优化建议，不阻塞合并
- 🔴 存在 N 条必须修改项，request changes
