#!/usr/bin/env python3
import sys

import yaml

SEVERITIES = {"critical", "warning", "info"}
AREAS = {"infra", "data", "energy", "car", "security"}
ANNOTATIONS = ("summary", "description", "dashboard", "runbook")
LINKS = ("dashboard", "runbook")


def rule_problems(rule):
    labels = rule.get("labels") or {}
    annotations = rule.get("annotations") or {}
    if labels.get("severity") not in SEVERITIES:
        yield f"severity is {labels.get('severity')!r}, expected one of {sorted(SEVERITIES)}"
    if labels.get("area") not in AREAS:
        yield f"area is {labels.get('area')!r}, expected one of {sorted(AREAS)}"
    for name in ANNOTATIONS:
        if not str(annotations.get(name, "")).strip():
            yield f"annotation {name} is missing"
    for name in LINKS:
        value = str(annotations.get(name, ""))
        if value and not value.startswith("https://"):
            yield f"annotation {name} is not an https URL: {value}"


def file_problems(path):
    with open(path) as f:
        groups = yaml.safe_load(f).get("groups", [])
    for group in groups:
        for rule in group.get("rules", []):
            if "alert" not in rule:
                continue
            for problem in rule_problems(rule):
                yield f"{path}: {group['name']}/{rule['alert']}: {problem}"


def main(paths):
    problems = [p for path in paths for p in file_problems(path)]
    for problem in problems:
        print(problem)
    alerts = sum(
        1
        for path in paths
        for group in yaml.safe_load(open(path)).get("groups", [])
        for rule in group.get("rules", [])
        if "alert" in rule
    )
    print(f"{alerts} alert rules checked, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
