#!/usr/bin/env python3
"""
Idempotens script: minden megadott markdown fájl tetejére beilleszt egy
`status:` YAML frontmatter-t. Ha a fájl elején már van `---` frontmatter,
a script nem módosítja (nem duplikál).

A státusz-térképet a docs/STATUS.md tárolja autoritatívan; ez a script csak
a fájlokba illeszti be a tükrözött `status:` mezőt.
"""

from pathlib import Path
import sys

REPO = Path(__file__).resolve().parent.parent

STATUS_MAP = {
    "vision": [
        "docs/architecture-en.md", "docs/architecture-hu.md",
        "docs/authcode-en.md", "docs/authcode-hu.md",
        "docs/cfpu-ml-max-en.md", "docs/cfpu-ml-max-hu.md",
        "docs/chiplet-packaging-en.md", "docs/chiplet-packaging-hu.md",
        "docs/core-types-en.md", "docs/core-types-hu.md",
        "docs/ddr5-architecture-en.md", "docs/ddr5-architecture-hu.md",
        "docs/faq-en.md", "docs/faq-hu.md",
        "docs/hw-attack-immunity-en.md", "docs/hw-attack-immunity-hu.md",
        "docs/hw-boot-en.md", "docs/hw-boot-hu.md",
        "docs/interconnect-en.md", "docs/interconnect-hu.md",
        "docs/internal-bus-en.md", "docs/internal-bus-hu.md",
        "docs/microarch-philosophy-en.md", "docs/microarch-philosophy-hu.md",
        "docs/perf-vs-riscv-en.md", "docs/perf-vs-riscv-hu.md",
        "docs/quench-ram-en.md", "docs/quench-ram-hu.md",
        "docs/sealcore-en.md", "docs/sealcore-hu.md",
        "docs/secure-element-en.md", "docs/secure-element-hu.md",
        "docs/security-en.md", "docs/security-hu.md",
        "docs/use-case-video-en.md", "docs/use-case-video-hu.md",
        "docs/vision-en.md", "docs/vision-hu.md",
    ],
    "draft": [
        "docs/ISA-CIL-Seal-en.md", "docs/ISA-CIL-Seal-hu.md",
        "docs/certification/CFPU-SEC-v1-en.md",
        "docs/certification/CFPU-SEC-v1-hu.md",
    ],
    "decision": [
        "docs/decision-bus-rollback-en.md",
        "docs/decision-bus-rollback-hu.md",
    ],
    "spec-candidate": [
        "docs/ISA-CIL-T0-en.md", "docs/ISA-CIL-T0-hu.md",
    ],
    "policy": [
        "docs/brand-en.md", "docs/brand-hu.md",
        "docs/tool-openness-en.md", "docs/tool-openness-hu.md",
        "docs/blog/series-plan.md", "docs/blog/series-plan-hu.md",
    ],
    "living": [
        "docs/roadmap-en.md", "docs/roadmap-hu.md",
        "docs/STATUS-en.md", "docs/STATUS-hu.md",
    ],
    "archived": [
        "docs/nlnet-application-draft-en.md",
        "docs/nlnet-application-draft-hu.md",
        "docs/nlnet-corrections-en.md", "docs/nlnet-corrections-hu.md",
        "docs/nlnet-submission-record.md",
        "docs/nlnet-submission-record-hu.md",
        "docs/symphact-en.md", "docs/symphact-hu.md",
    ],
    "reference": [
        "docs/A7-Lite/A7-Lite-en.md", "docs/A7-Lite/A7-Lite-hu.md",
    ],
    "mirror": [
        "docs/osreq-from-os/osreq-001-tree-interconnect-en.md",
        "docs/osreq-from-os/osreq-001-tree-interconnect-hu.md",
        "docs/osreq-from-os/osreq-002-mmio-memory-map-en.md",
        "docs/osreq-from-os/osreq-002-mmio-memory-map-hu.md",
        "docs/osreq-from-os/osreq-003-core-reset-en.md",
        "docs/osreq-from-os/osreq-003-core-reset-hu.md",
        "docs/osreq-from-os/osreq-004-dma-engine-en.md",
        "docs/osreq-from-os/osreq-004-dma-engine-hu.md",
        "docs/osreq-from-os/osreq-005-mailbox-interrupt-en.md",
        "docs/osreq-from-os/osreq-005-mailbox-interrupt-hu.md",
        "docs/osreq-from-os/osreq-006-interchip-link-en.md",
        "docs/osreq-from-os/osreq-006-interchip-link-hu.md",
    ],
}


def add_frontmatter(path: Path, status: str) -> str:
    """Visszatérési érték: 'inserted', 'skipped' (már van fm), 'missing'."""
    if not path.exists():
        return "missing"
    text = path.read_text(encoding="utf-8")
    if text.startswith("---\n"):
        return "skipped"
    fm = f"---\nstatus: {status}\n---\n\n"
    path.write_text(fm + text, encoding="utf-8")
    return "inserted"


def main(dry_run: bool) -> int:
    summary = {"inserted": 0, "skipped": 0, "missing": 0}
    missing_files = []
    for status, files in STATUS_MAP.items():
        for rel in files:
            path = REPO / rel
            if dry_run:
                if not path.exists():
                    result = "missing"
                elif path.read_text(encoding="utf-8").startswith("---\n"):
                    result = "skipped"
                else:
                    result = "would-insert"
            else:
                result = add_frontmatter(path, status)
            if result == "missing":
                missing_files.append(rel)
            key = "inserted" if result == "would-insert" else result
            summary[key] = summary.get(key, 0) + 1
            print(f"  [{result:14s}] {status:14s}  {rel}")

    total = sum(len(v) for v in STATUS_MAP.values())
    print()
    print(f"Total fájl a térképen: {total}")
    for k, v in summary.items():
        print(f"  {k}: {v}")
    if missing_files:
        print()
        print("HIÁNYZÓ FÁJLOK (a script térképe szerint léteznének):")
        for m in missing_files:
            print(f"  {m}")
        return 2
    return 0


if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    sys.exit(main(dry_run=dry))
