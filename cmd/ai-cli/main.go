package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

type toolPaths struct {
	name                string
	skillsCandidates    []string
	knowledgeCandidates []string
	learningCandidates  []string
	agentCandidates     []string
}

type cliConfig struct {
	Global   scopeConfig              `yaml:"global"`
	Projects map[string]projectConfig `yaml:"projects"`
}

type scopeConfig struct {
	Tools map[string]toolConfig `yaml:"tools"`
}

type projectConfig struct {
	Root  string                `yaml:"root"`
	Tools map[string]toolConfig `yaml:"tools"`
}

type toolConfig struct {
	Root                string   `yaml:"root"`
	SkillsCandidates    []string `yaml:"skills"`
	KnowledgeCandidates []string `yaml:"knowledge"`
	LearningCandidates  []string `yaml:"learning"`
	AgentCandidates     []string `yaml:"agents"`
}

const defaultConfigFileName = ".ai-cli.yaml"

const defaultConfigContent = `global:
  tools: {}

projects: {}
`

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
	var project string
	var configPath string

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

			repoRoot, err := os.Getwd()
			if err != nil {
				return err
			}

			cfg, err := loadConfig(repoRoot, configPath)
			if err != nil {
				return err
			}

			if install {
				return installTools(repoRoot, tools, project, cfg)
			}
			return uploadTools(repoRoot, tools, project, cfg)
		},
	}

	cmd.Flags().BoolVar(&install, "install", false, "Install skills/knowledge from repo to global tool dirs")
	cmd.Flags().BoolVar(&upload, "upload", false, "Upload local global skills/knowledge to this repo")
	cmd.Flags().StringVar(&toolsRaw, "tools", "all", "Comma separated tools: all,kiro,codex,claude-code")
	cmd.Flags().StringVar(&project, "project", "", "Project key or absolute path for project-level tool dirs")
	cmd.Flags().StringVar(&configPath, "config", "", "Path to config file (default: ~/.ai-cli.yaml)")
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

func repoSkillsDir(repoRoot, toolName string) string {
	if toolName == "claude-code" {
		return filepath.Join(repoRoot, "skills", toolName, "commands")
	}
	return filepath.Join(repoRoot, "skills", toolName, "skills")
}

func installTools(repoRoot string, tools []string, project string, cfg cliConfig) error {
	for _, t := range tools {
		paths, err := resolveToolPaths(t, project, cfg)
		if err != nil {
			return err
		}

		repoSkills := repoSkillsDir(repoRoot, paths.name)
		repoKnow := filepath.Join(repoRoot, "skills", paths.name, "knowledge")
		repoLearning := filepath.Join(repoRoot, "skills", paths.name, "learning")
		repoAgentCandidates := []string{
			filepath.Join(repoRoot, "skills", paths.name, "agents"),
			filepath.Join(repoRoot, "skills", paths.name, "agent"),
		}
		targetSkills := pickTargetPath(paths.skillsCandidates)
		targetKnowledge := pickTargetPath(paths.knowledgeCandidates)
		targetLearning := pickTargetPath(paths.learningCandidates)
		targetAgent := pickTargetPath(paths.agentCandidates)
		repoAgent := pickExistingPath(repoAgentCandidates)
		if repoAgent == "" {
			repoAgent = repoAgentCandidates[0]
		}

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

		if len(paths.learningCandidates) > 0 {
			if exists(repoLearning) {
				if err := copyDir(repoLearning, targetLearning); err != nil {
					return fmt.Errorf("install %s learning failed: %w", t, err)
				}
				fmt.Printf("installed %s learning: %s -> %s\n", t, repoLearning, targetLearning)
			} else {
				fmt.Printf("skip %s learning: repo dir not found %s\n", t, repoLearning)
			}
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

		if t == "claude-code" && project == "" {
			repoSettings := filepath.Join(repoRoot, "skills", "claude-code", claudeSettingsFile)
			if exists(repoSettings) {
				localSettings := filepath.Join(resolveClaudeHome(), "settings.json")
				if err := mergeClaudeSettings(repoSettings, localSettings); err != nil {
					return fmt.Errorf("install claude-code settings failed: %w", err)
				}
			}
		}
	}

	return nil
}

func uploadTools(repoRoot string, tools []string, project string, cfg cliConfig) error {
	for _, t := range tools {
		paths, err := resolveToolPaths(t, project, cfg)
		if err != nil {
			return err
		}

		repoSkills := repoSkillsDir(repoRoot, paths.name)
		repoKnow := filepath.Join(repoRoot, "skills", paths.name, "knowledge")
		repoLearning := filepath.Join(repoRoot, "skills", paths.name, "learning")
		repoAgentCandidates := []string{
			filepath.Join(repoRoot, "skills", paths.name, "agents"),
			filepath.Join(repoRoot, "skills", paths.name, "agent"),
		}
		sourceSkills := pickExistingPath(paths.skillsCandidates)
		sourceKnowledge := pickExistingPath(paths.knowledgeCandidates)
		sourceLearning := pickExistingPath(paths.learningCandidates)
		sourceAgent := pickExistingPath(paths.agentCandidates)
		repoAgent := pickExistingPath(repoAgentCandidates)
		if repoAgent == "" {
			repoAgent = repoAgentCandidates[0]
		}

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

		if len(paths.learningCandidates) > 0 {
			if sourceLearning != "" {
				if err := copyDir(sourceLearning, repoLearning); err != nil {
					return fmt.Errorf("upload %s learning failed: %w", t, err)
				}
				fmt.Printf("uploaded %s learning: %s -> %s\n", t, sourceLearning, repoLearning)
			} else {
				fmt.Printf("skip %s learning: local dir not found (candidates: %s)\n", t, strings.Join(paths.learningCandidates, ", "))
			}
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

		if t == "claude-code" && project == "" {
			localSettings := filepath.Join(resolveClaudeHome(), "settings.json")
			repoSettings := filepath.Join(repoRoot, "skills", "claude-code", claudeSettingsFile)
			if err := extractClaudeSettings(localSettings, repoSettings); err != nil {
				return fmt.Errorf("upload claude-code settings failed: %w", err)
			}
		}
	}

	if err := gitDiff(repoRoot); err != nil {
		return err
	}
	if err := gitCommit(repoRoot, tools); err != nil {
		return err
	}
	if err := gitMerge(repoRoot); err != nil {
		return err
	}
	if err := gitPush(repoRoot); err != nil {
		return err
	}

	return nil
}

func resolveToolPaths(tool string, project string, cfg cliConfig) (toolPaths, error) {
	if strings.TrimSpace(project) != "" {
		return resolveProjectToolPaths(tool, project, cfg)
	}
	return resolveGlobalToolPaths(tool, cfg)
}

func resolveGlobalToolPaths(tool string, cfg cliConfig) (toolPaths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return toolPaths{}, err
	}

	switch tool {
	case "codex":
		codexHome := getenvOrDefault("CODEX_HOME", filepath.Join(home, ".codex"))
		return mergeToolConfig(toolPaths{
			name:                "codex",
			skillsCandidates:    []string{filepath.Join(codexHome, "skills")},
			knowledgeCandidates: []string{filepath.Join(codexHome, "memories"), filepath.Join(codexHome, "knowledge")},
			learningCandidates:  nil,
			agentCandidates:     []string{filepath.Join(codexHome, "agents"), filepath.Join(codexHome, "agent")},
		}, cfg.Global.Tools["codex"]), nil
	case "kiro":
		kiroHome := getenvOrDefault("KIRO_HOME", filepath.Join(home, ".kiro"))
		return mergeToolConfig(toolPaths{
			name:                "kiro",
			skillsCandidates:    []string{filepath.Join(kiroHome, "skills")},
			knowledgeCandidates: []string{filepath.Join(kiroHome, "steering"), filepath.Join(kiroHome, "knowledge")},
			learningCandidates:  []string{filepath.Join(kiroHome, "learning")},
			agentCandidates:     []string{filepath.Join(kiroHome, "agents"), filepath.Join(kiroHome, "agent")},
		}, cfg.Global.Tools["kiro"]), nil
	case "claude-code":
		claudeHome := strings.TrimSpace(os.Getenv("CLAUDE_HOME"))
		claudeRoots := []string{}
		if claudeHome != "" {
			claudeRoots = append(claudeRoots, claudeHome)
		}
		claudeRoots = append(claudeRoots, filepath.Join(home, ".claudecode"), filepath.Join(home, ".claude-code"), filepath.Join(home, ".claude"))
		return mergeToolConfig(toolPaths{
			name:                "claude-code",
			skillsCandidates:    append(appendPaths(claudeRoots, "commands"), appendPaths(claudeRoots, "skills")...),
			knowledgeCandidates: appendPaths(claudeRoots, "knowledge"),
			learningCandidates:  nil,
			agentCandidates:     append(appendPaths(claudeRoots, "agents"), appendPaths(claudeRoots, "agent")...),
		}, cfg.Global.Tools["claude-code"]), nil
	default:
		return toolPaths{}, fmt.Errorf("unsupported tool %q", tool)
	}
}

func resolveProjectToolPaths(tool string, project string, cfg cliConfig) (toolPaths, error) {
	projectRoot, projectCfg, err := resolveProjectRoot(project, cfg)
	if err != nil {
		return toolPaths{}, err
	}

	switch tool {
	case "codex":
		defaultRoot := filepath.Join(projectRoot, ".codex")
		return mergeToolConfig(toolPaths{
			name:                "codex",
			skillsCandidates:    []string{filepath.Join(defaultRoot, "skills")},
			knowledgeCandidates: []string{filepath.Join(defaultRoot, "memories"), filepath.Join(defaultRoot, "knowledge")},
			learningCandidates:  nil,
			agentCandidates:     []string{filepath.Join(defaultRoot, "agents"), filepath.Join(defaultRoot, "agent")},
		}, projectCfg.Tools["codex"]), nil
	case "kiro":
		defaultRoot := filepath.Join(projectRoot, ".kiro")
		return mergeToolConfig(toolPaths{
			name:                "kiro",
			skillsCandidates:    []string{filepath.Join(defaultRoot, "skills")},
			knowledgeCandidates: []string{filepath.Join(defaultRoot, "steering"), filepath.Join(defaultRoot, "knowledge")},
			learningCandidates:  []string{filepath.Join(defaultRoot, "learning")},
			agentCandidates:     []string{filepath.Join(defaultRoot, "agents"), filepath.Join(defaultRoot, "agent")},
		}, projectCfg.Tools["kiro"]), nil
	case "claude-code":
		roots := []string{
			filepath.Join(projectRoot, ".claudecode"),
			filepath.Join(projectRoot, ".claude-code"),
			filepath.Join(projectRoot, ".claude"),
		}
		return mergeToolConfig(toolPaths{
			name:                "claude-code",
			skillsCandidates:    append(appendPaths(roots, "commands"), appendPaths(roots, "skills")...),
			knowledgeCandidates: appendPaths(roots, "knowledge"),
			learningCandidates:  nil,
			agentCandidates:     append(appendPaths(roots, "agents"), appendPaths(roots, "agent")...),
		}, projectCfg.Tools["claude-code"]), nil
	default:
		return toolPaths{}, fmt.Errorf("unsupported tool %q", tool)
	}
}

func resolveProjectRoot(project string, cfg cliConfig) (string, projectConfig, error) {
	project = strings.TrimSpace(project)
	if project == "" {
		return "", projectConfig{}, errors.New("project is empty")
	}
	if filepath.IsAbs(project) {
		return project, projectConfig{Root: project}, nil
	}

	projectCfg, ok := cfg.Projects[project]
	if !ok {
		return "", projectConfig{}, fmt.Errorf("project %q not found in config", project)
	}
	root := strings.TrimSpace(projectCfg.Root)
	if root == "" {
		return "", projectConfig{}, fmt.Errorf("project %q has empty root in config", project)
	}
	return root, projectCfg, nil
}

func mergeToolConfig(base toolPaths, override toolConfig) toolPaths {
	root := strings.TrimSpace(override.Root)
	if root != "" {
		switch base.name {
		case "codex":
			base.skillsCandidates = prependUnique(appendPaths([]string{root}, "skills"), base.skillsCandidates...)
			base.knowledgeCandidates = prependUnique(appendPaths([]string{root}, "memories"), appendPaths([]string{root}, "knowledge")...)
			base.agentCandidates = prependUnique(appendPaths([]string{root}, "agents"), appendPaths([]string{root}, "agent")...)
		case "kiro":
			base.skillsCandidates = prependUnique(appendPaths([]string{root}, "skills"), base.skillsCandidates...)
			base.knowledgeCandidates = prependUnique(appendPaths([]string{root}, "steering"), appendPaths([]string{root}, "knowledge")...)
			base.learningCandidates = prependUnique(appendPaths([]string{root}, "learning"), base.learningCandidates...)
			base.agentCandidates = prependUnique(appendPaths([]string{root}, "agents"), appendPaths([]string{root}, "agent")...)
		case "claude-code":
			base.skillsCandidates = prependUnique(append(appendPaths([]string{root}, "commands"), appendPaths([]string{root}, "skills")...), base.skillsCandidates...)
			base.knowledgeCandidates = prependUnique(appendPaths([]string{root}, "knowledge"), base.knowledgeCandidates...)
			base.agentCandidates = prependUnique(appendPaths([]string{root}, "agents"), appendPaths([]string{root}, "agent")...)
		}
	}

	base.skillsCandidates = prependUnique(override.SkillsCandidates, base.skillsCandidates...)
	base.knowledgeCandidates = prependUnique(override.KnowledgeCandidates, base.knowledgeCandidates...)
	base.learningCandidates = prependUnique(override.LearningCandidates, base.learningCandidates...)
	base.agentCandidates = prependUnique(override.AgentCandidates, base.agentCandidates...)
	return base
}

func prependUnique(paths []string, rest ...string) []string {
	out := make([]string, 0, len(paths)+len(rest))
	seen := make(map[string]struct{}, len(paths)+len(rest))
	for _, group := range [][]string{paths, rest} {
		for _, p := range group {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			if _, ok := seen[p]; ok {
				continue
			}
			seen[p] = struct{}{}
			out = append(out, p)
		}
	}
	return out
}

func loadConfig(repoRoot string, configPath string) (cliConfig, error) {
	path := strings.TrimSpace(configPath)
	if path == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return cliConfig{}, err
		}
		path = filepath.Join(home, defaultConfigFileName)
	}
	if !exists(path) {
		if err := ensureDefaultConfig(path); err != nil {
			return cliConfig{}, err
		}
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return cliConfig{}, fmt.Errorf("read config %s failed: %w", path, err)
	}

	var cfg cliConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return cliConfig{}, fmt.Errorf("parse config %s failed: %w", path, err)
	}
	if cfg.Global.Tools == nil {
		cfg.Global.Tools = map[string]toolConfig{}
	}
	if cfg.Projects == nil {
		cfg.Projects = map[string]projectConfig{}
	}
	return cfg, nil
}

func ensureDefaultConfig(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create config dir %s failed: %w", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte(defaultConfigContent), 0o644); err != nil {
		return fmt.Errorf("create default config %s failed: %w", path, err)
	}
	return nil
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

// claudeSettingsFile is the repo-side permissions template for Claude Code.
const claudeSettingsFile = "settings.json"

// mergeClaudeSettings merges permissions from repo settings.json into a local
// Claude Code settings.json. Only the "permissions.allow" list is merged;
// all other fields (model, theme, plugins, etc.) are preserved as-is.
func mergeClaudeSettings(repoSettings, localSettings string) error {
	repoPerms, err := readPermissions(repoSettings)
	if err != nil {
		return fmt.Errorf("read repo settings: %w", err)
	}
	if len(repoPerms) == 0 {
		return nil
	}

	local := map[string]interface{}{}
	if exists(localSettings) {
		data, err := os.ReadFile(localSettings)
		if err != nil {
			return fmt.Errorf("read local settings: %w", err)
		}
		if err := json.Unmarshal(data, &local); err != nil {
			return fmt.Errorf("parse local settings: %w", err)
		}
	}

	localPerms := extractStringSlice(local, "permissions", "allow")
	merged := mergeStringSlice(localPerms, repoPerms)

	perms, ok := local["permissions"].(map[string]interface{})
	if !ok {
		perms = map[string]interface{}{}
	}
	perms["allow"] = merged
	local["permissions"] = perms

	if err := writeJSON(localSettings, local); err != nil {
		return fmt.Errorf("write local settings: %w", err)
	}
	fmt.Printf("merged claude-code permissions: %d rules (%d from repo) -> %s\n", len(merged), len(repoPerms), localSettings)
	return nil
}

// extractClaudeSettings extracts the permissions.allow list from a local
// Claude Code settings.json and writes it as a standalone repo-side template.
func extractClaudeSettings(localSettings, repoSettings string) error {
	if !exists(localSettings) {
		fmt.Printf("skip claude-code settings: local file not found %s\n", localSettings)
		return nil
	}

	perms, err := readPermissions(localSettings)
	if err != nil {
		return fmt.Errorf("read local settings: %w", err)
	}
	if len(perms) == 0 {
		fmt.Println("skip claude-code settings: no permissions.allow in local settings")
		return nil
	}

	out := map[string]interface{}{
		"permissions": map[string]interface{}{
			"allow": perms,
		},
	}
	if err := os.MkdirAll(filepath.Dir(repoSettings), 0o755); err != nil {
		return err
	}
	if err := writeJSON(repoSettings, out); err != nil {
		return fmt.Errorf("write repo settings: %w", err)
	}
	fmt.Printf("uploaded claude-code settings: %d permission rules -> %s\n", len(perms), repoSettings)
	return nil
}

func readPermissions(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var obj map[string]interface{}
	if err := json.Unmarshal(data, &obj); err != nil {
		return nil, err
	}
	return extractStringSlice(obj, "permissions", "allow"), nil
}

func extractStringSlice(obj map[string]interface{}, keys ...string) []string {
	var cur interface{} = obj
	for _, k := range keys {
		m, ok := cur.(map[string]interface{})
		if !ok {
			return nil
		}
		cur = m[k]
	}
	arr, ok := cur.([]interface{})
	if !ok {
		return nil
	}
	out := make([]string, 0, len(arr))
	for _, v := range arr {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func mergeStringSlice(base, additions []string) []string {
	seen := make(map[string]struct{}, len(base))
	for _, s := range base {
		seen[s] = struct{}{}
	}
	merged := append([]string{}, base...)
	for _, s := range additions {
		if _, ok := seen[s]; !ok {
			merged = append(merged, s)
			seen[s] = struct{}{}
		}
	}
	sort.Strings(merged)
	return merged
}

func writeJSON(path string, v interface{}) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

// resolveClaudeHome returns the first existing Claude Code root directory.
func resolveClaudeHome() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	if v := strings.TrimSpace(os.Getenv("CLAUDE_HOME")); v != "" {
		if exists(v) {
			return v
		}
	}
	for _, name := range []string{".claudecode", ".claude-code", ".claude"} {
		p := filepath.Join(home, name)
		if exists(p) {
			return p
		}
	}
	return filepath.Join(home, ".claude")
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
