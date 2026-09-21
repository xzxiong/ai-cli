Create GitHub issues with structured task breakdown and automatic sub-issue linking.

Input: $ARGUMENTS (mode and options)

## Modes

### 1. Create from Chat/Text
Convert chat discussions or requirements into structured GitHub issues.

```bash
/issue-manager create --from-text "讨论内容..." --title "Issue 标题"
```

**Process:**
1. Extract key points: background, goals, technical approach
2. Identify actionable tasks from discussion
3. Create parent issue with structured body:
   - 背景 (Background)
   - 目标 (Goal)
   - 技术方案 (Technical Approach)
   - 任务清单 (Task List)
   - 优先级 (Priority)

### 2. Breakdown Parent Issue
Read parent issue, extract tasks from checklist, create and link sub-issues.

```bash
/issue-manager breakdown --parent <issue_number> [--body-format simple|tasklist|none]
```

**Process:**
1. Read parent issue body via `gh issue view <number> --json body`
2. Extract checklist items: `grep -P '^\s*-\s*\[\s*\]\s*'`
3. For each task:
   - Create sub-issue with structured body
   - Get GraphQL node IDs
   - Link via `addSubIssue` mutation
4. Optionally update parent body with task references

**Body formats:**
- `simple` (default): `- [ ] #1234 Description`
- `tasklist`: ` ```[tasklist] ``` ` block with full URLs
- `none`: No body modification, GraphQL linking only

### 3. Link Existing Issues
Link already-created issues as sub-issues to a parent.

```bash
/issue-manager link --parent <number> --children <num1,num2,...> [--update-body]
```

**Process:**
1. Get GraphQL node IDs for parent and children
2. Execute `addSubIssue` mutations
3. Optionally update parent body with task list

## Implementation Details

### Task Extraction
```bash
# Extract checklist items from markdown
gh issue view 9676 --json body -q .body | \
  grep -P '^\s*-\s*\[\s*\]\s*' | \
  sed 's/^\s*-\s*\[\s*\]\s*//'
```

### GraphQL Operations

**Get Issue ID:**
```bash
gh api graphql -f query='
{
  repository(owner: "matrixorigin", name: "matrixflow") {
    issue(number: 9676) { id }
  }
}'
```

**Link Sub-Issue:**
```bash
gh api graphql -f query='
mutation {
  addSubIssue(input: {
    issueId: "I_kwDON_K6-s8AAAABAz5Nvw"
    subIssueId: "I_kwDON_K6-s8AAAABAz88Yg"
  }) {
    issue { id }
  }
}'
```

### Sub-Issue Template
```markdown
## 目标
<Specific, actionable objective>

## 技术细节
- Implementation approach
- Technical considerations
- Resources needed

## 验证标准
- [ ] Acceptance criteria 1
- [ ] Acceptance criteria 2
- [ ] Testing completed

## 关联
Part of #<parent_number>

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## Examples

### Example 1: From Chat to Issues

**Input:**
```
邓楠: taas 没检测到不可用？那taas 就没做到位啊
张旭: embedding没有接入taas，所有的外部服务都是单点
赵晨阳: embedding 模型上海机房可以支撑的，用 2-3 张卡覆盖
张旭: 上海机房+硅基流动？部署一个服务，和硅基相互备份
```

**Command:**
```bash
/issue-manager create --from-text "<chat>" --title "在 IDC 上搭建 embedding 服务"
```

**Output:**
- Creates issue #9676 with:
  - Background: 单点故障、缺乏监控、已发生多次事故
  - Goal: IDC 搭建 embedding 服务，与硅基流动相互备份
  - Technical approach: 上海机房 2-3 张 GPU 卡
  - Task list: 5 actionable items

### Example 2: Breakdown Tasks

**Input:** Issue #9676 with task list

**Command:**
```bash
/issue-manager breakdown --parent 9676 --body-format simple
```

**Output:**
- Creates sub-issues #9678-#9682:
  1. 在上海机房 IDC 部署 embedding 服务（bge-m3）
  2. 配置 embedding 服务外网访问（域名/端口/证书）
  3. 实现 embedding 服务与硅基流动的负载均衡/故障切换
  4. embedding 服务接入 taas 监控体系
  5. 建立 embedding 服务运维监控告警机制
- Links all sub-issues via GraphQL
- Updates parent body: `- [ ] #9678 Description`

### Example 3: Link Existing Issues

**Input:** Already created issues 9678-9682

**Command:**
```bash
/issue-manager link --parent 9676 --children 9678,9679,9680,9681,9682 --update-body
```

**Output:**
- GraphQL links established
- Parent body updated with task references
- Sub-issues show "Part of #9676" in timeline

## Decision Logic

1. **When to break down:**
   - ✅ Parent has 3+ distinct technical tasks
   - ✅ Tasks can be worked independently
   - ✅ Different owners for different parts
   - ❌ Task < 1 day effort
   - ❌ Subtasks tightly coupled

2. **Body format selection:**
   - `simple`: Best readability, compatible with all editors
   - `tasklist`: GitHub native, auto progress tracking
   - `none`: Keep body clean, rely on sidebar

3. **Title conventions:**
   - Parent: High-level goal or feature
   - Sub-issues: Specific, actionable tasks with context

## Error Handling

**Issue not found:**
```bash
gh issue view 9999 || echo "Issue not found, verify number and repo"
```

**GraphQL permission denied:**
```bash
gh auth refresh -s write:discussion -s repo
```

**Duplicate sub-issues:**
```bash
gh issue list --search "is:issue is:open linked:issue:9676"
```

## Files

Reference implementation:
- `/skills/issue-manager/SKILL.md` - Full documentation
- `/skills/issue-manager/issue-manager.sh` - Bash implementation
- `/skills/issue-manager/README.md` - Detailed guide
- `/skills/issue-manager/QUICKSTART.md` - Quick start
- `/skills/issue-manager/test.sh` - Test suite

## Testing

Run test suite to verify environment:
```bash
cd /path/to/repo/skills/issue-manager
./test.sh
```

Tests include:
- gh CLI availability
- Authentication status
- GraphQL query execution
- Task extraction logic
- Script syntax validation

## Best Practices

1. **Always include context** in sub-issue titles (service name, component)
2. **Use consistent structure** for issue bodies
3. **Link early** - establish parent-child relationships immediately
4. **Verify links** - check sidebar shows sub-issues correctly
5. **Update status** - close sub-issues as work completes

## Related Commands

- `/new-pr` - Create PR linked to issue
- `/review-pr` - Review PR with issue context
- `/update-pr-desc` - Update PR description from issue
