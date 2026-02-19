#!/usr/bin/env python3
"""Format raw GitHub generated release notes into clean, categorized markdown.

Expects Conventional Commits PR titles (feat:, fix:, etc.) and the output
format of `gh release create --generate-notes`.

Usage:
    python3 format-release-notes.py <raw_notes_file> <tag> [--html]

    --html  Output HTML instead of markdown (for Sparkle appcast).
"""

import html
import re
import sys
from pathlib import Path

SECTIONS = {
    "feat": "What's New",
    "fix": "Fixes",
    "perf": "Performance",
    "refactor": "Under the Hood",
    "docs": "Documentation",
    "style": "Style",
    "test": "Testing",
}

# Skip changes that aren't relevant to end users
SKIP_TYPES = {"build", "ci", "chore"}

# PR line pattern from --generate-notes:
#   * feat(scope): description by @user in https://...
PR_RE = re.compile(
    r"^\*\s+"
    r"(?:(?P<type>[a-z]+)(?:\([^)]*\))?:\s*)?"
    r"(?P<desc>.+?)"
    r"(?:\s+by\s+@[\w-]+)?"
    r"(?:\s+in\s+https?://\S+)?"
    r"\s*$"
)

CHANGELOG_RE = re.compile(r"^\*\*Full Changelog\*\*:\s*(?P<url>https?://\S+)")


def parse_notes(raw: str) -> tuple[dict[str, list[str]], str | None]:
    """Parse raw release notes into categorized entries and changelog URL."""
    sections: dict[str, list[str]] = {}
    changelog_url = None

    for line in raw.splitlines():
        line = line.strip()

        changelog_match = CHANGELOG_RE.match(line)
        if changelog_match:
            changelog_url = changelog_match.group("url")
            continue

        pr_match = PR_RE.match(line)
        if not pr_match:
            continue

        pr_type = pr_match.group("type") or ""
        desc = pr_match.group("desc").strip()

        if pr_type in SKIP_TYPES:
            continue

        section = SECTIONS.get(pr_type, "Other")
        sections.setdefault(section, []).append(desc)

    return sections, changelog_url


def format_markdown(tag: str, sections: dict[str, list[str]], changelog_url: str | None) -> str:
    """Render categorized notes as markdown."""
    lines = [f"## Brewy {tag}", ""]

    ordered_keys = list(dict.fromkeys(SECTIONS.values()))
    ordered_keys.append("Other")

    for heading in ordered_keys:
        entries = sections.get(heading)
        if not entries:
            continue
        lines.append(f"### {heading}")
        for entry in entries:
            lines.append(f"- {entry}")
        lines.append("")

    if changelog_url:
        lines.append("---")
        lines.append(f"**Full Changelog**: {changelog_url}")
        lines.append("")

    return "\n".join(lines)


def format_html(tag: str, sections: dict[str, list[str]], changelog_url: str | None) -> str:
    """Render categorized notes as HTML (for Sparkle appcast <description>)."""
    parts: list[str] = []

    ordered_keys = list(dict.fromkeys(SECTIONS.values()))
    ordered_keys.append("Other")

    for heading in ordered_keys:
        entries = sections.get(heading)
        if not entries:
            continue
        parts.append(f"<h2>{html.escape(heading)}</h2>")
        parts.append("<ul>")
        for entry in entries:
            parts.append(f"  <li>{html.escape(entry)}</li>")
        parts.append("</ul>")

    return "\n".join(parts)


def main() -> None:
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <raw_notes_file> <tag> [--html]", file=sys.stderr)
        sys.exit(1)

    raw = Path(sys.argv[1]).read_text()
    tag = sys.argv[2]
    output_html = "--html" in sys.argv

    sections, changelog_url = parse_notes(raw)

    if output_html:
        print(format_html(tag, sections, changelog_url))
    else:
        print(format_markdown(tag, sections, changelog_url))


if __name__ == "__main__":
    main()
