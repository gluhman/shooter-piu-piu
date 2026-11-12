#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys


VERSION = r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}"
VERSION_SETTING = re.compile(r"^config/version\s*=.*$", re.MULTILINE)
RELEASE_HEADING = re.compile(r"##\s+(.+)")
CHANGE_ITEM = re.compile(r"\s*[-*]\s+.*\w")
DOC_PATH = ":(glob)docs/**/*.md"


def git(*args):
    return subprocess.check_output(["git", *args], encoding="utf-8")


def project_version(revision, allow_unversioned=False):
    project = git("show", f"{revision}:project.godot")
    settings = VERSION_SETTING.findall(project)
    if not settings and allow_unversioned:
        return None
    match = re.fullmatch(rf'config/version="({VERSION})"', settings[0]) if len(settings) == 1 else None
    if match is None:
        raise ValueError(f'{revision}: укажи одну версию config/version="X.Y.Z" в project.godot.')
    return match[1]


def check_docs(base, head):
    if base:
        changes = git(
            "diff", "--name-status", "--no-renames", "--diff-filter=AMT", "-z", base, head, "--", DOC_PATH
        ).rstrip("\0").split("\0")
        candidates = zip(changes[::2], changes[1::2])
    else:
        paths = git("ls-tree", "-r", "--name-only", "-z", head, "--", "docs/")
        candidates = (("A", path) for path in paths.split("\0") if path.endswith(".md"))
    for status, path in candidates:
        mode, _, _ = git("ls-tree", head, "--", f":(literal){path}").partition(" ")
        if mode not in {"100644", "100755"}:
            continue
        content = git("show", f"{head}:{path}").split()
        if content and (status != "M" or content != git("show", f"{base}:{path}").split()):
            return
    raise ValueError("Добавь или обнови Markdown-документ в docs/ и включи его в отправляемые коммиты.")


def check_release(base, head):
    version = project_version(head)
    base_has_changelog = False
    if base:
        base_has_changelog = bool(git("ls-tree", "--name-only", base, "--", "CHANGELOG.md"))
        previous = project_version(base, allow_unversioned=not base_has_changelog)
        if previous and tuple(map(int, version.split("."))) <= tuple(map(int, previous.split("."))):
            raise ValueError(f"Увеличь версию игры: {version} должна быть выше {previous}.")

    changelog = git("show", f"{head}:CHANGELOG.md")
    headings = []
    changes = []
    for line in changelog.splitlines():
        heading = RELEASE_HEADING.fullmatch(line)
        if heading:
            headings.append(heading[1].strip())
        elif len(headings) == 1 and CHANGE_ITEM.match(line):
            changes.append(line)
    if not headings or headings[0] != version:
        raise ValueError(f"Добавь в начало CHANGELOG.md раздел «## {version}».")
    if headings.count(version) != 1:
        raise ValueError(f"Оставь один раздел «## {version}» в CHANGELOG.md.")
    if not changes:
        raise ValueError(f"Опиши изменения версии {version} списком в CHANGELOG.md.")
    if base_has_changelog and changelog.split() == git("show", f"{base}:CHANGELOG.md").split():
        raise ValueError(f"Обнови CHANGELOG.md для версии {version}.")
    check_docs(base, head)
    print(f"Версия {version}, журнал изменений и документация проверены.")


def main():
    parser = argparse.ArgumentParser(description="Проверить версию, журнал и документацию по коммитам Git.")
    parser.add_argument("--base", help="Коммит основной ветки до обновления")
    parser.add_argument("head", help="Проверяемый коммит")
    args = parser.parse_args()
    try:
        check_release(args.base, args.head)
    except (subprocess.CalledProcessError, ValueError) as error:
        print(f"Проверка выпуска: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
