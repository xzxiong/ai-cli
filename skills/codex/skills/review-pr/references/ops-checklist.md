# Ops 模式 — 审查 Checklist

面向基础设施/部署仓库（ops、gitops、moi-gitops、moi-op）。侧重资源配置、安全、影响范围、环境一致性。

## 仓库识别与审查侧重

| 仓库 | 技术栈 | 管理范围 | 审查侧重 |
|------|--------|---------|---------|
| `ops` | Pulumi (Go + TS) | IDC/AWS/TKE 基础设施：MetalLB、MinIO、Harbor、监控栈、CI runner、GPU operator | 资源配置合理性、安全、影响范围 |
| `gitops` | Pulumi (Go) | ACK 云服务部署：mocloud-services + moi-core + Ingress | 服务配置一致性、Ingress 路由、环境差异 |
| `moi-gitops` | Pulumi (Go) + Helm | IDC moi-core 部署：Catalog + Mowl + Workers + 前端 + TLS | Helm values 正确性、unit 配置、secret 管理 |
| `moi-op` | Pulumi (Go) + Helm | IDC 私有化全套：BYOA + RocketMQ + Redis + 连接器 + 前端 | chart 优先级、hook 逻辑、配置完整性 |

## 报告结构

```
# Code Review: <PR title>

PR 基础信息
## 〇、总结（TL;DR）
## 一、变更影响分析
## 二、资源配置审查
## 三、安全审查
## 四、Pulumi / Helm 代码审查
## 五、运维风险检查
```

---

## PR 基础信息

```markdown
- **PR**: [#<number> <title>](<pr_url>)
- **分支**: `<head>` → `<base>` | **变更**: +<additions> / -<deletions>，<file_count> 个文件
- **模式**: 🔧 Ops Review | **仓库类型**: <ops/gitops/moi-gitops/moi-op>
```

---

## 〇、总结（TL;DR）

- 一句话概括变更目的
- 影响环境：dev / qa / prod / IDC
- 风险等级：🟢 低风险 / 🟡 需确认 / 🔴 高风险
- 关键发现摘要

---

## 一、变更影响分析

### 1.1 影响范围

| 维度 | 内容 |
|------|------|
| 影响环境 | 哪些 stack/环境受影响？ |
| 影响组件 | 哪些 K8s 资源会创建/修改/删除？ |
| 影响时间 | 需要停机？滚动更新？ |
| 回滚方案 | 出问题如何回滚？Pulumi state 可逆？ |

### 1.2 环境一致性

- 多环境（dev/qa/prod/多 stack）配置是否一致？
- 是否只改了某个环境遗漏了其他？
- 环境间差异是否有合理原因？

---

## 二、资源配置审查

### 2.1 计算资源

- CPU/Memory requests 和 limits 是否合理？与现有组件对齐？
- 副本数合理？考虑高可用？
- Node selector / tolerations / affinity 正确？

### 2.2 存储资源

- PVC 大小合理？StorageClass 正确？
- MinIO tenant：pool 数量、磁盘数、容量是否匹配物理资源？
- 数据持久化策略正确？

### 2.3 网络资源

- LoadBalancer IP 在 MetalLB IP pool 范围内？与现有分配冲突？
- Ingress 规则：host/path 正确？TLS 证书配置？
- Service 端口与应用实际监听端口匹配？
- NodePort 是否冲突？

---

## 三、安全审查

### 3.1 Secret 管理

- 有明文密码/Token/AK-SK 提交？（`Pulumi secure:` 加密值除外）
- Secret 引用正确？（`secure:` 字段、Helm secret template）
- 新 Secret 在所有需要的环境都有配置？

### 3.2 权限控制

- RBAC 遵循最小权限原则？
- ServiceAccount 权限过大？（如 cluster-admin）
- 镜像仓库凭证正确配置？

### 3.3 网络安全

- 内网地址/端口暴露到公网？
- Ingress 配置 TLS？HTTP → HTTPS 重定向？
- 不必要的 hostNetwork 使用？

---

## 四、Pulumi / Helm 代码审查

### 4.1 Pulumi 代码（Go/TypeScript）

- 资源命名遵循项目约定？
- `DependsOn` 依赖链正确？循环依赖？
- Provider 配置正确？（kubeconfig、region）
- 资源泄漏？（创建了但未纳入 state 管理）
- `IgnoreChanges` 使用合理？导致配置漂移？

### 4.2 Helm chart / values

- values 层级正确？（chart 默认 → 基础覆盖 → stack 覆盖 → unit 覆盖）
- 新 values key 在 chart `values.yaml` 有默认值？
- template 语法正确？（`{{ }}` 嵌套、条件、range）
- chart 版本与 `Chart.yaml` / `Chart.lock` 一致？

### 4.3 Pulumi 配置（Pulumi.*.yaml）

- 配置命名遵循 `<project>:<key>` 格式？
- 敏感值使用 `secure:` 加密？
- 类型正确？（string vs number vs bool vs object）
- 新配置在 README/文档中说明？

---

## 五、运维风险检查

### 5.1 破坏性变更

- 导致 Pod 重启？（ConfigMap/Secret 变更、image tag 变更）
- 导致数据丢失？（PVC 删除、StorageClass 变更）
- 导致服务中断？（Ingress 路由变更、Service 删除）
- StatefulSet 变更需手动干预？（volumeClaimTemplates 不可变）

### 5.2 部署顺序

- 组件间有部署顺序依赖？（CRD 先于 CR）
- Pulumi priority 设置正确？
- before/after hook 需调整？

### 5.3 监控 & 告警

- 新组件有对应监控配置？（Prometheus scrape、Grafana dashboard）
- 告警规则需更新？
- 日志采集覆盖新组件？

### 5.4 CI/CD 流水线

- GitHub Actions workflow 变更正确？
- preview / up 触发条件合理？
- workflow 权限足够？

---

## 输出分级

- 🔴 **必须修改**：服务中断、数据丢失、安全问题
- 🟡 **建议修改**：配置不一致、资源浪费、运维风险
- 🟢 **可选优化**：最佳实践建议
- ⚠️ **需确认**：无法从代码判断，需作者确认

---

## Ops 模式审查原则

1. **安全第一**：密钥泄漏、权限过大是 🔴 级别
2. **影响范围**：可能影响生产的变更需明确标注
3. **可回滚**：评估变更可逆性，不可逆需特别标注
4. **环境一致**：多环境配置应保持合理一致性
5. **最小变更**：基础设施应小步迭代，避免大范围同时变更

---

## 注意事项

- `Pulumi.*.yaml` 中的 `secure:` 字段是加密值，**不要**标记为安全问题
- 非 `secure:` 的明文密码/Token **必须**标记
- Helm chart 的 `values.yaml` 中 placeholder 值（如 `CHANGE_ME`）需检查是否在 stack overlay 中被覆盖
