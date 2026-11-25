# merge-main `--gates` eval notes

- Updated skill: `/data2/xzxiong/.claude/skills/merge-main`.
- Test repositories are isolated minimal fixtures, not real MatrixFlow worktrees.
- Three with-skill runs completed: gate failure repair, default opt-out, and rebase with no gates workflow.
- Gate fixture's arithmetic assertions were independently rerun successfully after the agent fix; the fix remains uncommitted as required.
- MatrixFlow planner was smoke-tested using a synthetic `moi/pkg/service/example.go` changed path, producing `moi=true`. Full MatrixFlow gates were intentionally not run: this task only modifies the skill and has no merged production candidate.
- Some old-skill controls were blocked by child-session read permissions, not by product behavior. Do not interpret their pass rates as a valid comparison.
- Timing JSON preserves each agent's reported usage. Child stdout/stderr are retained for audit.

No git commit, push, or modification of any real project branch was performed.
