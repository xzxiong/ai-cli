package main

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

type toolPaths struct {
	name                string
	skillsCandidates    []string
	knowledgeCandidates []string
	agentCandidates     []string
}

func main() {
	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "ci-cli",
		Short: "Developer helper CLI",
	}
	rootCmd.SilenceUsage = true
	rootCmd.AddCommand(newSkillsCmd())
	return rootCmd
}

func newSkillsCmd() *cobra.Command {
	var install bool
	var upload bool
	var toolsRaw string

	cmd := &cobra.Command{
		Use:   "skills",
		Short: "Sync skills/knowledge across tools",
		RunE: func(cmd *cobra.Command, args []string) error {
			if (install && upload) || (!install && !upload) {
				return errors.New("choose exactly one: --install or --upload")
			}

			tools, err := parseTools(toolsRaw)
			if err != nil {
				return err
			}

			if install {
				return installTools(tools)
			}
			return uploadTools(tools)
		},
	}

	cmd.Flags().BoolVar(&install, "install", false, "Install skills/knowledge from repo to global tool dirs")
	cmd.Flags().BoolVar(&upload, "upload", false, "Upload local global skills/knowledge to this repo")
	cmd.Flags().StringVar(&toolsRaw, "tools", "all", "Comma separated tools: all,kiro,codex,claude-code")
	return cmd
}

func parseTools(raw string) ([]string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		raw = "all"
	}

	allowed := map[string]struct{}{
		"kiro":        {},
		"codex":       {},
		"claude-code": {},
		"claude":      {},
	}

	seen := make(map[string]struct{})
	var out []string
	for _, t := range strings.Split(raw, ",") {
		t = strings.TrimSpace(strings.ToLower(t))
		if t == "" {
			continue
		}
		if t == "all" {
			return []string{"codex", "kiro", "claude-code"}, nil
		}
		if t == "claude" {
			t = "claude-code"
		}
		if _, ok := allowed[t]; !ok {
			return nil, fmt.Errorf("unsupported tool %q, allowed: all,kiro,codex,claude-code", t)
		}
		if _, ok := seen[t]; ok {
			continue
		}
		seen[t] = struct{}{}
		out = append(out, t)
	}
	if len(out) == 0 {
		return nil, errors.New("no valid tools found in --tools")
	}
	return out, nil
}

func installTools(tools []string) error {
	repoRoot, err := os.Getwd()
	if err != nil {
		return err
	}

	for _, t := range tools {
		paths, err := resolveToolPaths(t)
		if err != nil {
			return err
		}

		repoSkills := filepath.Join(repoRoot, "skills", paths.name, "skills")
		repoKnow := filepath.Join(repoRoot, "skills", paths.name, "knowledge")
		repoAgent := filepath.Join(repoRoot, "skills", paths.name, "agent")
		targetSkills := pickTargetPath(paths.skillsCandidates)
		targetKnowledge := pickTargetPath(paths.knowledgeCandidates)
		targetAgent := pickTargetPath(paths.agentCandidates)

		if exists(repoSkills) {
			if err := copyDir(repoSkills, targetSkills); err != nil {
				return fmt.Errorf("install %s skills failed: %w", t, err)
			}
			fmt.Printf("installed %s skills: %s -> %s\n", t, repoSkills, targetSkills)
		} else {
			fmt.Printf("skip %s skills: repo dir not found %s\n", t, repoSkills)
		}

		if exists(repoKnow) {
			if err := copyDir(repoKnow, targetKnowledge); err != nil {
				return fmt.Errorf("install %s knowledge failed: %w", t, err)
			}
			fmt.Printf("installed %s knowledge: %s -> %s\n", t, repoKnow, targetKnowledge)
		} else {
			fmt.Printf("skip %s knowledge: repo dir not found %s\n", t, repoKnow)
		}

		if len(paths.agentCandidates) > 0 {
			if exists(repoAgent) {
				if err := copyDir(repoAgent, targetAgent); err != nil {
					return fmt.Errorf("install %s agent failed: %w", t, err)
				}
				fmt.Printf("installed %s agent: %s -> %s\n", t, repoAgent, targetAgent)
			} else {
				fmt.Printf("skip %s agent: repo dir not found %s\n", t, repoAgent)
			}
		}
	}

	return nil
}

func uploadTools(tools []string) error {
	repoRoot, err := os.Getwd()
	if err != nil {
		return err
	}

	for _, t := range tools {
		paths, err := resolveToolPaths(t)
		if err != nil {
			return err
		}

		repoSkills := filepath.Join(repoRoot, "skills", paths.name, "skills")
		repoKnow := filepath.Join(repoRoot, "skills", paths.name, "knowledge")
		repoAgent := filepath.Join(repoRoot, "skills", paths.name, "agent")
		sourceSkills := pickExistingPath(paths.skillsCandidates)
		sourceKnowledge := pickExistingPath(paths.knowledgeCandidates)
		sourceAgent := pickExistingPath(paths.agentCandidates)

		if sourceSkills != "" {
			if err := copyDir(sourceSkills, repoSkills); err != nil {
				return fmt.Errorf("upload %s skills failed: %w", t, err)
			}
			fmt.Printf("uploaded %s skills: %s -> %s\n", t, sourceSkills, repoSkills)
		} else {
			fmt.Printf("skip %s skills: local dir not found (candidates: %s)\n", t, strings.Join(paths.skillsCandidates, ", "))
		}

		if sourceKnowledge != "" {
			if err := copyDir(sourceKnowledge, repoKnow); err != nil {
				return fmt.Errorf("upload %s knowledge failed: %w", t, err)
			}
			fmt.Printf("uploaded %s knowledge: %s -> %s\n", t, sourceKnowledge, repoKnow)
		} else {
			fmt.Printf("skip %s knowledge: local dir not found (candidates: %s)\n", t, strings.Join(paths.knowledgeCandidates, ", "))
		}

		if len(paths.agentCandidates) > 0 {
			if sourceAgent != "" {
				if err := copyDir(sourceAgent, repoAgent); err != nil {
					return fmt.Errorf("upload %s agent failed: %w", t, err)
				}
				fmt.Printf("uploaded %s agent: %s -> %s\n", t, sourceAgent, repoAgent)
			} else {
				fmt.Printf("skip %s agent: local dir not found (candidates: %s)\n", t, strings.Join(paths.agentCandidates, ", "))
			}
		}
	}

	if err := gitDiff(repoRoot); err != nil {
		return err
	}
	if err := gitMerge(repoRoot); err != nil {
		return err
	}
	if err := gitCommit(repoRoot, tools); err != nil {
		return err
	}
	if err := gitPush(repoRoot); err != nil {
		return err
	}

	return nil
}

func resolveToolPaths(tool string) (toolPaths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return toolPaths{}, err
	}

	switch tool {
	case "codex":
		codexHome := getenvOrDefault("CODEX_HOME", filepath.Join(home, ".codex"))
		return toolPaths{
			name:                "codex",
			skillsCandidates:    []string{filepath.Join(codexHome, "skills")},
			knowledgeCandidates: []string{filepath.Join(codexHome, "memories"), filepath.Join(codexHome, "knowledge")},
			agentCandidates:     []string{filepath.Join(codexHome, "agents"), filepath.Join(codexHome, "agent")},
		}, nil
	case "kiro":
		kiroHome := getenvOrDefault("KIRO_HOME", filepath.Join(home, ".kiro"))
		return toolPaths{
			name:                "kiro",
			skillsCandidates:    []string{filepath.Join(kiroHome, "skills")},
			knowledgeCandidates: []string{filepath.Join(kiroHome, "steering"), filepath.Join(kiroHome, "knowledge")},
			agentCandidates:     []string{filepath.Join(kiroHome, "agent")},
		}, nil
	case "claude-code":
		claudeHome := strings.TrimSpace(os.Getenv("CLAUDE_HOME"))
		claudeRoots := []string{}
		if claudeHome != "" {
			claudeRoots = append(claudeRoots, claudeHome)
		}
		claudeRoots = append(claudeRoots, filepath.Join(home, ".claudecode"), filepath.Join(home, ".claude-code"), filepath.Join(home, ".claude"))
		return toolPaths{
			name:                "claude-code",
			skillsCandidates:    appendPaths(claudeRoots, "skills"),
			knowledgeCandidates: appendPaths(claudeRoots, "knowledge"),
			agentCandidates:     append(appendPaths(claudeRoots, "agents"), appendPaths(claudeRoots, "agent")...),
		}, nil
	default:
		return toolPaths{}, fmt.Errorf("unsupported tool %q", tool)
	}
}

func appendPaths(roots []string, suffix string) []string {
	out := make([]string, 0, len(roots))
	seen := make(map[string]struct{})
	for _, r := range roots {
		p := filepath.Join(r, suffix)
		if _, ok := seen[p]; ok {
			continue
		}
		seen[p] = struct{}{}
		out = append(out, p)
	}
	return out
}

func pickExistingPath(paths []string) string {
	for _, p := range paths {
		if exists(p) {
			return p
		}
	}
	return ""
}

func pickTargetPath(paths []string) string {
	if p := pickExistingPath(paths); p != "" {
		return p
	}
	if len(paths) > 0 {
		return paths[0]
	}
	return ""
}

func getenvOrDefault(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func copyDir(src, dst string) error {
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}

	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}

		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}

		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}

		if err := copyFile(path, target); err != nil {
			return err
		}
		return nil
	})
}

func copyFile(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}

	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}

	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}

	if err := out.Close(); err != nil {
		return err
	}

	if info, err := os.Stat(src); err == nil {
		_ = os.Chmod(dst, info.Mode().Perm())
	}
	return nil
}

func gitDiff(repoRoot string) error {
	fmt.Println("running git diff...")
	if err := runGit(repoRoot, "status", "--short"); err != nil {
		return err
	}
	if err := runGit(repoRoot, "diff", "--stat"); err != nil {
		return err
	}
	return nil
}

func gitMerge(repoRoot string) error {
	fmt.Println("running git merge (pull --rebase)...")
	branch, err := outputGit(repoRoot, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return err
	}
	branch = strings.TrimSpace(branch)
	if branch == "" {
		return errors.New("cannot detect current git branch")
	}

	if err := runGit(repoRoot, "pull", "--rebase", "origin", branch); err != nil {
		return fmt.Errorf("git pull --rebase failed: %w", err)
	}
	return nil
}

func gitCommit(repoRoot string, tools []string) error {
	fmt.Println("running git commit...")
	if err := runGit(repoRoot, "add", "skills"); err != nil {
		return err
	}

	if err := runGit(repoRoot, "diff", "--cached", "--quiet"); err == nil {
		fmt.Println("no staged changes, skip commit")
		return nil
	} else {
		if code := exitCode(err); code != 1 {
			return err
		}
	}

	msg := fmt.Sprintf("chore(skills): upload %s (%s)", strings.Join(tools, ","), time.Now().Format("2006-01-02 15:04:05"))
	if err := runGit(repoRoot, "commit", "-m", msg); err != nil {
		return err
	}
	return nil
}

func gitPush(repoRoot string) error {
	fmt.Println("running git push...")
	branch, err := outputGit(repoRoot, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return err
	}
	branch = strings.TrimSpace(branch)
	if branch == "" {
		return errors.New("cannot detect current git branch")
	}
	if err := runGit(repoRoot, "push", "origin", branch); err != nil {
		return err
	}
	return nil
}

func runGit(repoRoot string, args ...string) error {
	cmd := exec.Command("git", args...)
	cmd.Dir = repoRoot
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func outputGit(repoRoot string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = repoRoot
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}

func exitCode(err error) int {
	var e *exec.ExitError
	if errors.As(err, &e) {
		if status := e.ProcessState; status != nil {
			code := status.ExitCode()
			if code >= 0 {
				return code
			}
		}
	}
	if err == nil {
		return 0
	}
	if s := strings.TrimSpace(err.Error()); s != "" {
		parts := strings.Split(s, "exit status ")
		if len(parts) > 1 {
			if code, convErr := strconv.Atoi(strings.TrimSpace(parts[len(parts)-1])); convErr == nil {
				return code
			}
		}
	}
	return -1
}
