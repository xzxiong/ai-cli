package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCopyDirOverwritesReadOnlyFile(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "src")
	dst := filepath.Join(root, "dst")
	name := filepath.Join("fixture", ".git", "objects", "object")
	srcFile := filepath.Join(src, name)
	dstFile := filepath.Join(dst, name)

	if err := os.MkdirAll(filepath.Dir(srcFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(srcFile, []byte("new content"), 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(dstFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dstFile, []byte("old content"), 0o444); err != nil {
		t.Fatal(err)
	}

	if err := copyDir(src, dst); err != nil {
		t.Fatalf("copyDir() failed to overwrite a read-only file: %v", err)
	}

	content, err := os.ReadFile(dstFile)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "new content" {
		t.Errorf("copied content = %q, want %q", content, "new content")
	}
	info, err := os.Stat(dstFile)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := info.Mode().Perm(), os.FileMode(0o444); got != want {
		t.Errorf("copied permissions = %o, want %o", got, want)
	}
}
