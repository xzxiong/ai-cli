# Scenario: Feature

**When**: new product capability or intentional behavior change (not a bug fix).  
**Default Issue Type**: `Feature`

## Title

- `[Feature] ...` or `[MOI 需求] ...` when product-facing
- State the capability, not the implementation ticket soup

## Labels / defaults hints

- `--type feature`
- Product feature may need `kind/feature-moi` only if the label exists
- 视角 stays `开发实现` unless user/PM says otherwise (user-demand path is a different filing guide)

## Body template

```markdown
## 背景

...

## 目标

...

成功标准：

1. ...

### 非目标

- ...

## 名词解释

| 名词 | 含义 |
|------|------|
| | |

## 事实依据（现状）

- 当前产品行为 / 代码入口：
- 相关配置或 API：
- 用户场景或工单：

## 数据依据（如有）

| 信号 | 来源 | 值 |
|------|------|----|
| 使用量 / 失败率 / 工单数 | | |

## 方案（预案）

### 方案 A（推荐）

...

### 方案 B

...

## 任务清单

- [ ] ...

## 测试方案

| 类型 | 内容 |
|------|------|
| UT / BVT | |
| 手动验收 | |
| 兼容 / 权限 | |

## 验收标准

- [ ] ...

## 关联

- ...
```

## Scenario-specific rules

- Keep 非目标 tight; features balloon without it.
- 事实依据 is **current product reality**, not aspirational design only.
- If this is pure PM product-function tracking, defer to MOI product feature filing guide when the user is in that workflow; otherwise use this template for engineering feature issues.
