#!/usr/bin/env python3
"""Create disposable merge-main fixtures; never runs the skill itself."""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path('/data2/xzxiong/.claude/skills/merge-main-workspace/iteration-1')


def git(repo, *args):
    subprocess.run(['git', *args], cwd=repo, check=True, capture_output=True, text=True)


def write(repo, rel, content):
    path = repo / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def commit(repo, message):
    git(repo, 'add', 'calc.py')
    if (repo / 'test_calc.py').exists():
        git(repo, 'add', 'test_calc.py', '.github/workflows/gates-ci.yml')
    git(repo, 'commit', '-m', message)


def create(repo, with_gate):
    repo.mkdir(parents=True)
    git(repo, 'init')
    git(repo, 'checkout', '-b', 'main')
    git(repo, 'config', 'user.name', 'Skill Eval')
    git(repo, 'config', 'user.email', 'skill-eval@localhost')
    write(repo, 'calc.py', 'def add(a, b):\n    return a + b\n')
    if with_gate:
        write(repo, 'test_calc.py', 'from calc import add\n\ndef test_one_plus_one():\n    assert add(1, 1) == 2\n')
        write(repo, '.github/workflows/gates-ci.yml', '''name: Gates CI
on: [pull_request, workflow_dispatch]
jobs:
  gates:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Arithmetic gates
        run: python3 -m unittest -v test_calc.py
''')
    commit(repo, 'Initial arithmetic')
    git(repo, 'checkout', '-b', 'feature')
    write(repo, 'calc.py', 'def add(a, b):\n    return a - b\n')
    commit(repo, 'Feature arithmetic implementation')
    git(repo, 'checkout', 'main')
    if with_gate:
        write(repo, 'test_calc.py', '''from calc import add

def test_one_plus_one():
    assert add(1, 1) == 2

def test_merge_regression():
    assert add(5, 3) == 8
''')
    else:
        write(repo, 'calc.py', '"""Arithmetic API."""\n\ndef add(a, b):\n    return a + b\n')
    commit(repo, 'Main adds regression coverage')
    git(repo, 'checkout', 'feature')


for case in ('with_gate', 'without_flag', 'without_gate'):
    for config in ('with_skill', 'old_skill'):
        dest = ROOT / case / config / 'fixture'
        if dest.exists():
            shutil.rmtree(dest)
        create(dest, case != 'without_gate')
        print(dest)
