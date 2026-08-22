#!/usr/bin/env python3
"""Fetch CC-CEDICT and write the compact lexicon bundled with 词记."""

from __future__ import annotations

import argparse
import gzip
import io
import os
import re
import sys
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from ciji_engine import (  # noqa: E402
    EXTRA_PHRASES,
    LexEntry,
    base_freq,
    encode_xiaohe,
    normalize_syllable,
    shorten_gloss,
)


def _gloss_quality(gloss: str) -> int:
    low = gloss.lower()
    if not gloss:
        return 0
    if "variant of" in low or low.startswith("see "):
        return 1
    return 10 + min(len(gloss), 40)


def _better_entry(new: LexEntry, old: LexEntry) -> bool:
    nq, oq = _gloss_quality(new.gloss), _gloss_quality(old.gloss)
    if nq != oq:
        return nq > oq
    return new.freq > old.freq

CEDICT_URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
LINE_RE = re.compile(
    r"^(?P<trad>\S+)\s+(?P<simp>\S+)\s+\[(?P<pinyin>[^\]]+)\]\s+/(?P<gloss>.*)/$"
)


def download_cedict(cache_path: Path) -> bytes:
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    if cache_path.exists() and cache_path.stat().st_size > 1000:
        return cache_path.read_bytes()
    print(f"Downloading CC-CEDICT from {CEDICT_URL} …", file=sys.stderr)
    req = urllib.request.Request(
        CEDICT_URL,
        headers={"User-Agent": "CijiIME-dict-builder/1.0"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    cache_path.write_bytes(data)
    return data


def parse_cedict(raw_gz: bytes) -> list[LexEntry]:
    text = gzip.decompress(raw_gz).decode("utf-8")
    seen: dict[tuple[str, str], LexEntry] = {}
    skipped = 0
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        m = LINE_RE.match(line)
        if not m:
            skipped += 1
            continue
        phrase = m.group("simp")
        if any(ord(ch) < 128 for ch in phrase):
            # Skip entries that mix ASCII (measure words with letters, etc.)
            if not all(ord(ch) >= 128 for ch in phrase):
                skipped += 1
                continue
        raw_syllables = m.group("pinyin").split()
        syllables = tuple(normalize_syllable(s) for s in raw_syllables)
        if not syllables or any(not s for s in syllables):
            skipped += 1
            continue
        xh = encode_xiaohe(syllables)
        if xh is None:
            skipped += 1
            continue
        quanpin = "".join(syllables)
        gloss = shorten_gloss(m.group("gloss"), limit=40)
        freq = base_freq(phrase, len(syllables))
        key = (phrase, xh)
        entry = LexEntry(
            phrase=phrase,
            syllables=syllables,
            xiaohe=xh,
            quanpin=quanpin,
            gloss=gloss,
            freq=freq,
        )
        prev = seen.get(key)
        if prev is None or _better_entry(entry, prev):
            seen[key] = entry
    for phrase, syllables, gloss, extra_freq in EXTRA_PHRASES:
        xh = encode_xiaohe(syllables)
        if xh is None:
            continue
        quanpin = "".join(syllables)
        key = (phrase, xh)
        entry = LexEntry(
            phrase=phrase,
            syllables=syllables,
            xiaohe=xh,
            quanpin=quanpin,
            gloss=gloss,
            freq=extra_freq,
        )
        prev = seen.get(key)
        if prev is None or entry.freq > prev.freq:
            seen[key] = entry
    print(f"Parsed {len(seen)} entries (skipped {skipped}).", file=sys.stderr)
    return sorted(seen.values(), key=lambda e: (e.xiaohe, -e.freq, e.phrase))


def write_tsv_gz(entries: list[LexEntry], dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    buf = io.StringIO()
    buf.write("# Ciji lexicon derived from CC-CEDICT (CC BY-SA 3.0)\n")
    buf.write("# phrase\\tsyllables\\txiaohe\\tquanpin\\tgloss\\tfreq\n")
    for e in entries:
        syl = " ".join(e.syllables)
        gloss = e.gloss.replace("\t", " ").replace("\n", " ")
        buf.write(f"{e.phrase}\t{syl}\t{e.xiaohe}\t{e.quanpin}\t{gloss}\t{e.freq}\n")
    payload = buf.getvalue().encode("utf-8")
    with gzip.open(dest, "wb", compresslevel=9) as fh:
        fh.write(payload)
    print(
        f"Wrote {len(entries)} rows → {dest} "
        f"({dest.stat().st_size} bytes gzipped, {len(payload)} uncompressed).",
        file=sys.stderr,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the Ciji CEDICT resource.")
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "Ciji" / "Resources" / "cedict.tsv.gz",
    )
    parser.add_argument(
        "--cache",
        type=Path,
        default=SCRIPT_DIR / ".cedict_cache" / "cedict.txt.gz",
    )
    args = parser.parse_args()
    raw = download_cedict(args.cache)
    entries = parse_cedict(raw)
    if len(entries) < 10000:
        print("ERROR: dictionary is unexpectedly small.", file=sys.stderr)
        return 1
    write_tsv_gz(entries, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
