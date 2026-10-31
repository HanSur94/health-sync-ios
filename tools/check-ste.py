#!/usr/bin/env python3
"""Check README.md against the ASD-STE100 limits that a script can test.

STE asks for short sentences, active voice, simple tenses and no contractions.
This checks sentence length, contractions and progressive forms. It cannot
judge vocabulary, so a clean run is a floor, not a certificate.
"""
import pathlib
import re
import sys

MAX_DESCRIPTIVE = 25     # STE: 25 words for descriptive text
MAX_INSTRUCTION = 20     # STE: 20 words for an instruction
README = pathlib.Path(__file__).resolve().parent.parent / "README.md"


def prose_lines(text):
    """Drop fenced code, tables, HTML and bare URLs: only the sentences we wrote."""
    fenced = False
    for n, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("```"):
            fenced = not fenced
            continue
        if fenced or not line.strip():
            continue
        if line.lstrip().startswith(("|", "<", "#")) or line.strip().startswith("*The screenshots"):
            continue
        yield n, re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)


def sentences(line):
    # a period inside a version number or a file name is not a sentence end
    return [s for s in re.split(r"(?<=[.!?])\s+(?=[A-Z*`])", line) if s.strip()]


def main():
    text = README.read_text()
    problems = []
    for n, line in prose_lines(text):
        for s in sentences(line):
            words = re.findall(r"[\w'-]+", s)
            limit = MAX_INSTRUCTION if s.lstrip().startswith(("-", "1.", "2.", "3.", "4.", "5.")) else MAX_DESCRIPTIVE
            if len(words) > limit:
                problems.append(f"line {n}: {len(words)} words (max {limit}): {s.strip()[:90]}")
            # a quoted string is data, not our prose: Apple's own error text may use contractions
            own = re.sub(r'"[^"]*"', '""', s)
            if re.search(r"\b\w+'(t|s|re|ll|ve|d|m)\b", own):
                problems.append(f"line {n}: contraction: {s.strip()[:90]}")
            if re.search(r"\b(is|are|was|were)\s+\w+ing\b", own):
                problems.append(f"line {n}: progressive form: {s.strip()[:90]}")

    if problems:
        print(f"{len(problems)} problem(s):")
        print("\n".join(problems))
        return 1
    print("README is inside the STE limits: every sentence has 25 words or fewer (20 for instructions),")
    print("no contractions, no progressive forms.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
