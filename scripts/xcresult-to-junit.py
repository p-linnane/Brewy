#!/usr/bin/env python3
"""Convert an Xcode xcresult bundle to JUnit XML for Codecov test analytics.

Usage: xcresult-to-junit.py <path-to-xcresult> > junit.xml

Uses `xcrun xcresulttool get test-results tests` (Xcode 16+).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from xml.etree.ElementTree import Element, ElementTree, SubElement, indent

DURATION_RE = re.compile(r"([\d.]+)\s*(ms|s|m|h)")


def parse_duration(raw: str | None) -> float:
    if not raw:
        return 0.0
    total = 0.0
    for value, unit in DURATION_RE.findall(raw):
        value = float(value)
        if unit == "ms":
            total += value / 1000
        elif unit == "s":
            total += value
        elif unit == "m":
            total += value * 60
        elif unit == "h":
            total += value * 3600
    return total


def collect_failure_messages(node: dict) -> list[str]:
    messages: list[str] = []
    for child in node.get("children", []):
        if child.get("nodeType") == "Failure Message":
            text = child.get("name", "")
            if text:
                messages.append(text)
        messages.extend(collect_failure_messages(child))
    return messages


def walk_tests(node: dict, suite: str | None):
    node_type = node.get("nodeType")
    name = node.get("name", "")
    if node_type == "Test Case":
        yield suite or "Unknown", node
        return
    next_suite = suite
    if node_type in ("Test Suite", "Test Bundle"):
        next_suite = name if suite is None else f"{suite}.{name}"
    for child in node.get("children", []):
        yield from walk_tests(child, next_suite)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: xcresult-to-junit.py <xcresult>", file=sys.stderr)
        return 2

    xcresult = sys.argv[1]
    proc = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresult],
        capture_output=True,
        check=True,
    )
    data = json.loads(proc.stdout)

    suites: dict[str, list[dict]] = {}
    for plan in data.get("testNodes", []):
        for suite_name, test in walk_tests(plan, None):
            suites.setdefault(suite_name, []).append(test)

    root = Element("testsuites")
    for suite_name, tests in suites.items():
        failed = sum(1 for t in tests if t.get("result") == "Failed")
        skipped = sum(1 for t in tests if t.get("result") == "Skipped")
        total_time = sum(parse_duration(t.get("duration")) for t in tests)
        suite_elem = SubElement(
            root,
            "testsuite",
            {
                "name": suite_name,
                "tests": str(len(tests)),
                "failures": str(failed),
                "skipped": str(skipped),
                "time": f"{total_time:.3f}",
            },
        )
        for test in tests:
            tc = SubElement(
                suite_elem,
                "testcase",
                {
                    "name": test.get("name", ""),
                    "classname": suite_name,
                    "time": f"{parse_duration(test.get('duration')):.3f}",
                },
            )
            result = test.get("result")
            if result == "Failed":
                messages = collect_failure_messages(test)
                failure = SubElement(tc, "failure", {"message": messages[0] if messages else "Test failed"})
                failure.text = "\n".join(messages) if messages else "Failed"
            elif result == "Skipped":
                SubElement(tc, "skipped")

    indent(root, space="  ")
    ElementTree(root).write(sys.stdout.buffer, xml_declaration=True, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
