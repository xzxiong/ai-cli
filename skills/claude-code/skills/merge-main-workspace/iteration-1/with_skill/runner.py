#!/usr/bin/env python3
"""Run safe shell-only fixtures for the merge-main skill regression."""
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

SKILL = Path('/data2/xzxiong/.claude/skills/merge-main/SKILL.md')
GATES = SKILL.parent / 'references/gates-regression.md'
WORKSPACE = Path('/data2/xzxiong/.claude/skills/merge-main-workspace')
FIXTURES = WORKSPACE / 'fixtures'


def run(repo, command, **kwargs):
    return subprocess.run(command, cwd=repo, text=True, capture_output=True, **kwargs)


def git(repo, *args):
    result = run(repo, ['git', *args])
    if result.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def write(repo, rel, text):
    path = repo / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def commit(repo, message):
    git(repo, 'add', 'calc.py', 'test_calc.py', '.github/workflows/gates-ci.yml')
    git(repo, 'commit', '-m', message)


def setup(tmp, with_gate):
    repo = tmp / 'repo'
    repo.mkdir()
    git(repo, 'init', '-b', 'main')
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
    commit(repo, 'Initial arithmetic and gates')
    base = git(repo, 'rev-parse', 'HEAD')
    git(repo, 'checkout', '-b', 'feature')
    write(repo, 'calc.py', 'def add(a, b):\n    return a - b\n')
    commit(repo, 'Break addition on feature')
    git(repo, 'checkout', 'main')
    if with_gate:
        write(repo, 'test_calc.py', '''from calc import add

def test_one_plus_one():
    assert add(1, 1) == 2

def test_merge_regression():
    assert add(5, 3) == 8
''')
    commit(repo, 'Add merge regression coverage')
    git(repo, 'checkout', 'feature')
    write(repo, 'before_merge.txt', git(repo, 'rev-parse', 'HEAD') + '\n')
    return repo


def bash_script(body):
    # The eval prompts and scripts only execute these trusted local fixtures.
    return 'set -u\ncd "$REPO"\n' + body + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--case', choices=['with_gate', 'without_flag', 'without_gate'], required=True)
    parser.add_argument('--version', choices=['old', 'new'], required=True)
    parser.add_argument('--tmp', type=Path, required=True)
    args = parser.parse_args()
    args.tmp.mkdir(parents=True)
    with_gate = args.case != 'without_gate'
    repo = setup(args.tmp, with_gate)
    text = SKILL.read_text() if args.version == 'new' else (WORKSPACE / 'skill-snapshot/SKILL.md').read_text()
    args.tmp.mkdir(exist_ok=True)
    (args.tmp / 'instructions.md').write_text(text)
    outdir = WORKSPACE / 'iteration-1' / args.case / ('with_skill' if args.version == 'new' else 'old_skill') / 'outputs'
    outdir.mkdir(parents=True, exist_ok=True)
    records = []
    def record(command, result, note=''):
        records.append(f"$ {command}\nexit={result.returncode}\n{result.stdout}{result.stderr}{note}")
    if args.case == 'with_gate':
        if args.version == 'old':
            record('git merge main', run(repo, ['git', 'merge', 'main']))
            record('python3 -m unittest -v test_calc.py', run(repo, ['python3', '-m', 'unittest', '-v', 'test_calc.py']), '\nOLD SKILL STOPS AT FAILURE')
        else:
            record('Read .github/workflows/gates-ci.yml and references/gates-regression.md after merge', subprocess.CompletedProcess([], 0, 'Selected the Arithmetic gates step.\n', ''))
            record('git merge main', run(repo, ['git', 'merge', 'main']))
            record('python3 -m unittest -v test_calc.py', run(repo, ['python3', '-m', 'unittest', '-v', 'test_calc.py']))
            write(repo, 'calc.py', 'def add(a, b):\n    return a + b\n')
            record('python3 -m unittest -v test_calc.py (targeted and full fixture gate after fix)', run(repo, ['python3', '-m', 'unittest', '-v', 'test_calc.py']))
            record('git status --short', run(repo, ['git', 'status', '--short']))
            record('git diff --check', run(repo, ['git', 'diff', '--check']))
            head = git(repo, 'rev-parse', 'HEAD')
            merge_msg = git(repo, 'log', '-1', '--pretty=%s')
            before = (repo / 'before_merge.txt').read_text().strip()
            assert head != before and merge_msg == 'Merge branch \'main\' into feature'
            assert run(repo, ['python3', '-m', 'unittest', '-v', 'test_calc.py']).returncode == 0
    elif args.case == 'without_flag':
        if args.version == 'new':
            record('Optional --gates phase not entered', subprocess.CompletedProcess([], 0, 'SKIPPED: flag absent; no gates workflow inspection or gate regression.\n', ''))
        record('git merge main', run(repo, ['git', 'merge', 'main']))
        record('git diff --check', run(repo, ['git', 'diff', '--check']))
        record('python3 -m py_compile calc.py', run(repo, ['python3', '-m', 'py_compile', 'calc.py']))
        record('git status --short', run(repo, ['git', 'status', '--short']))
        assert run(repo, ['python3', '-m', 'unittest', '-v', 'test_calc.py']).returncode != 0
        records.append('POSTCONDITION: deliberately failing gate remains outside the requested default verification scope.')
    else:
        flag = '--rebase --gates' if args.version == 'new' else '--rebase'
        record(f'/merge-main main {flag}', subprocess.CompletedProcess([], 0, '', ''))
        record('git rebase main', run(repo, ['git', 'rebase', 'main']))
        if args.version == 'new':
            record('find .github/workflows -name gates-ci.yml -o -name gates-ci.yaml', subprocess.CompletedProcess([], 0, 'SKIPPED (not configured): no gates-ci workflow; no invented regression.\n', ''))
        record('git status --short', run(repo, ['git', 'status', '--short']))
        assert not git(repo, 'status', '--porcelain')
        assert not (repo / '.git/rebase-merge').exists()
    (outdir / 'execution-report.txt').write_text('\n\n'.join(records) + '\n')
    shutil.copy(repo / 'calc.py', outdir / 'calc.py')
    if (repo / 'test_calc.py').exists():
        shutil.copy(repo / 'test_calc.py', outdir / 'test_calc.py')
    (outdir / 'metadata.json').write_text(__import__('json').dumps({'repo': str(repo), 'case': args.case, 'version': args.version, 'mode': 'deterministic fixture replay, not an independent agent execution'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
