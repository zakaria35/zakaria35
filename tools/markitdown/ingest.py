#!/usr/bin/env python3
"""تحويل مصادر المنهاج إلى Markdown يقرأه كيميا.

يمشي على مجلّد المصادر (PDF · Word · PowerPoint · Excel · صور · HTML)،
يحوّل كل ملفٍ مدعوم إلى Markdown عبر MarkItDown، ويحفظه في مجلّد المخرجات
مع الحفاظ على بنية المجلّدات، ثم يبني فهرساً لكل ما تحوّل.

    python tools/markitdown/ingest.py
    python tools/markitdown/ingest.py --source knowledge/raw --out knowledge/md --force
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# الصيغ التي نعتمدها لمصادر المنهاج. MarkItDown يدعم أكثر من ذلك،
# لكن هذه هي ما يصلنا فعلياً: كتب وزارية، أوراق عمل، عروض، جداول، صور أسئلة.
SUPPORTED_SUFFIXES = {
    ".pdf",
    ".docx",
    ".doc",
    ".pptx",
    ".ppt",
    ".xlsx",
    ".xls",
    ".csv",
    ".html",
    ".htm",
    ".epub",
    ".txt",
    ".json",
    ".xml",
    ".jpg",
    ".jpeg",
    ".png",
    ".zip",
}


@dataclass
class Result:
    source: Path
    target: Path
    status: str  # converted | skipped | empty | failed
    detail: str = ""


def display_path(path: Path) -> str:
    """مسار مختصر نسبةً للمستودع، أو مطلق إن كان خارجه."""
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(path)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="تحويل مصادر المنهاج إلى Markdown لقاعدة معرفة كيميا"
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=REPO_ROOT / "knowledge" / "raw",
        help="مجلّد الملفات الأصلية (افتراضياً knowledge/raw)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=REPO_ROOT / "knowledge" / "md",
        help="مجلّد مخرجات Markdown (افتراضياً knowledge/md)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="أعد تحويل الملفات حتى لو كان مخرجها أحدث من مصدرها",
    )
    return parser.parse_args(argv)


def front_matter(source: Path, source_root: Path) -> str:
    """ترويسة تحفظ أصل النصّ — لأن كل معلومة علمية يجب أن تُنسب لمصدرها."""
    relative = source.relative_to(source_root).as_posix()
    return "\n".join(
        [
            "---",
            f'source_file: "{relative}"',
            f'source_format: "{source.suffix.lstrip(".").lower()}"',
            f"converted_on: {date.today().isoformat()}",
            'converted_by: "markitdown"',
            "---",
            "",
            "",
        ]
    )


def convert_one(
    converter, source: Path, source_root: Path, out_root: Path, force: bool
) -> Result:
    relative = source.relative_to(source_root)
    target = out_root / relative.with_suffix(".md")

    if target.exists() and not force and target.stat().st_mtime >= source.stat().st_mtime:
        return Result(source, target, "skipped", "المخرج محدّث")

    try:
        text = converter.convert(str(source)).text_content
    except Exception as exc:  # noqa: BLE001 — نريد الاستمرار لبقية الملفات
        return Result(source, target, "failed", f"{type(exc).__name__}: {exc}")

    if not text or not text.strip():
        return Result(source, target, "empty", "لا نصّ مستخرج (قد يكون PDF ممسوحاً ضوئياً)")

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(front_matter(source, source_root) + text.strip() + "\n", encoding="utf-8")
    return Result(source, target, "converted")


def write_index(results: list[Result], out_root: Path, source_root: Path) -> None:
    usable = sorted(
        (r for r in results if r.status in {"converted", "skipped"}),
        key=lambda r: r.target.as_posix(),
    )
    lines = [
        "# فهرس قاعدة معرفة كيميا",
        "",
        "مولَّد آلياً بواسطة `tools/markitdown/ingest.py` — لا تحرّره يدوياً.",
        "",
        f"عدد الملفات: **{len(usable)}** · آخر تحديث: {date.today().isoformat()}",
        "",
        "| الملف | المصدر الأصلي |",
        "| --- | --- |",
    ]
    for r in usable:
        name = r.target.relative_to(out_root).as_posix()
        origin = r.source.relative_to(source_root).as_posix()
        lines.append(f"| [`{name}`]({name}) | `{origin}` |")
    lines.append("")
    (out_root / "INDEX.md").write_text("\n".join(lines), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    source_root: Path = args.source.resolve()
    out_root: Path = args.out.resolve()

    if not source_root.is_dir():
        print(f"✗ مجلّد المصادر غير موجود: {source_root}", file=sys.stderr)
        return 1

    try:
        from markitdown import MarkItDown
    except ImportError:
        print(
            "✗ MarkItDown غير مثبّت. ثبّته بـ:\n"
            "    pip install -r tools/markitdown/requirements.txt",
            file=sys.stderr,
        )
        return 1

    sources = sorted(
        p
        for p in source_root.rglob("*")
        if p.is_file() and p.suffix.lower() in SUPPORTED_SUFFIXES and not p.name.startswith(".")
    )
    if not sources:
        print(f"لا ملفات مدعومة في {source_root}. ضع مصادر المنهاج هناك ثم أعد التشغيل.")
        return 0

    out_root.mkdir(parents=True, exist_ok=True)
    converter = MarkItDown(enable_plugins=False)

    results = [convert_one(converter, s, source_root, out_root, args.force) for s in sources]

    marks = {"converted": "✓", "skipped": "·", "empty": "⚠", "failed": "✗"}
    for r in results:
        detail = f" — {r.detail}" if r.detail else ""
        print(f"{marks[r.status]} {r.source.relative_to(source_root)}{detail}")

    write_index(results, out_root, source_root)

    tally = {status: sum(1 for r in results if r.status == status) for status in marks}
    print(
        f"\nالخلاصة: {tally['converted']} محوّل · {tally['skipped']} متجاوَز · "
        f"{tally['empty']} فارغ · {tally['failed']} فاشل"
    )
    print(f"الفهرس: {display_path(out_root / 'INDEX.md')}")

    return 1 if tally["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
