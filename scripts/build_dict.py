#!/usr/bin/env python3
"""Build the lexicon bundled with 词记 (Ciji/Resources/cedict.tsv.gz).

Sources
-------
* CC-CEDICT (CC BY-SA 4.0)      — words, pinyin and English glosses.
* rime-essay essay.txt (LGPL-3) — word frequencies (traditional script).
* rime luna_pinyin.dict.yaml    — per-reading percentages for polyphonic
  characters (e.g. 的 de 99.97% / di 0.03%) and pinyin for essay words that
  CC-CEDICT lacks (e.g. 我是, 不知道).

Output columns: phrase, syllables, xiaohe, quanpin, gloss, freq
`freq` is a corpus count; the engines rank with log(freq).
"""

from __future__ import annotations

import argparse
import gzip
import io
import itertools
import math
import re
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from ciji_engine import VALID_SYLLABLES, encode_xiaohe, normalize_syllable  # noqa: E402

CACHE = SCRIPT_DIR / ".cedict_cache"
CEDICT_URLS = [
    "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz",
]
# pycccedict ships an unmodified CC-CEDICT export; used when mdbg.net is unreachable.
CEDICT_WHEEL = "https://files.pythonhosted.org/packages/py3/p/pycccedict/pycccedict-1.2.0-py3-none-any.whl"
ESSAY_URL = "https://raw.githubusercontent.com/rime/rime-essay/master/essay.txt"
LUNA_URL = "https://raw.githubusercontent.com/rime/rime-luna-pinyin/master/luna_pinyin.dict.yaml"

LINE_RE = re.compile(r"^(?P<trad>\S+)\s+(?P<simp>\S+)\s+\[(?P<pinyin>[^\]]+)\]\s+/(?P<gloss>.*)/$")
HAN_RE = re.compile(r"^[㐀-鿿豈-﫿\U00020000-\U0002ffff]+$")

# Minimum essay count for words that only exist in essay (no CEDICT entry).
ESSAY_ONLY_MIN = 400
GLOSS_LIMIT = 48


def fetch(url: str, dest: Path) -> Path:
    if dest.exists() and dest.stat().st_size > 1000:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url} …", file=sys.stderr)
    req = urllib.request.Request(url, headers={"User-Agent": "CijiIME-dict-builder/2.0"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        dest.write_bytes(resp.read())
    return dest


def fetch_cedict() -> bytes:
    dest = CACHE / "cedict.txt.gz"
    if dest.exists() and dest.stat().st_size > 1000:
        return dest.read_bytes()
    for url in CEDICT_URLS:
        try:
            return fetch(url, dest).read_bytes()
        except Exception as exc:  # noqa: BLE001
            print(f"  failed: {exc}", file=sys.stderr)
    import zipfile

    wheel = fetch(CEDICT_WHEEL, CACHE / "pycccedict.whl")
    with zipfile.ZipFile(wheel) as zf:
        name = next(n for n in zf.namelist() if n.endswith("cedict_1_0_ts_utf-8_mdbg.txt.gz"))
        data = zf.read(name)
    dest.write_bytes(data)
    return data


# --------------------------------------------------------------------------- glosses

_CL_RE = re.compile(r"\bCL:[^/]*")
_HANREF_RE = re.compile(r"[㐀-鿿]+\|([㐀-鿿]+)")  # 詞|词 -> 词
_PY_RE = re.compile(r"\[[a-zA-Z0-9: ]+\]")


def _clean_sense(sense: str) -> str:
    s = _CL_RE.sub("", sense)
    s = _HANREF_RE.sub(r"\1", s)
    s = _PY_RE.sub("", s)
    return re.sub(r"\s+", " ", s).strip(" ;,")


def _is_meta(sense: str) -> bool:
    low = sense.lower()
    return (
        not low
        or "variant of" in low
        or low.startswith(("see ", "erhua", "archaic", "used in ", "surname ", "(dialect)", "(old)", "abbr. for"))
        or low.startswith("also written")
        or low.startswith("also pr.")
    )


def gloss_senses(raw: str) -> list[str]:
    senses = [_clean_sense(s) for s in raw.split("/")]
    senses = [s for s in senses if s]
    good = [s for s in senses if not _is_meta(s)]
    return good or senses


def short_gloss(senses: list[str], limit: int = GLOSS_LIMIT) -> str:
    out = ""
    for sense in senses[:3]:
        cand = sense if not out else f"{out}; {sense}"
        if len(cand) > limit and out:
            break
        out = cand
    if len(out) > limit:
        out = out[: limit - 1].rstrip() + "…"
    return out


def is_meta_only(raw: str) -> bool:
    senses = [_clean_sense(s) for s in raw.split("/")]
    senses = [s for s in senses if s]
    return bool(senses) and all(_is_meta(s) for s in senses)


# --------------------------------------------------------------------------- sources


def load_essay() -> dict[str, int]:
    path = fetch(ESSAY_URL, CACHE / "essay.txt")
    freq: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1].isdigit():
            freq[parts[0]] = int(parts[1])
    return freq


def load_luna() -> dict[str, list[tuple[str, float]]]:
    """char -> [(syllable, share)] with shares summing to ~1."""
    path = fetch(LUNA_URL, CACHE / "luna_pinyin.dict.yaml")
    raw: dict[str, list[tuple[str, float | None]]] = defaultdict(list)
    started = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() == "...":
            started = True
            continue
        if not started or not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2 or len(parts[0]) != 1:
            continue
        syl = normalize_syllable(parts[1])
        if syl not in VALID_SYLLABLES:
            continue
        pct = None
        if len(parts) >= 3 and parts[2].endswith("%"):
            try:
                pct = float(parts[2][:-1]) / 100.0
            except ValueError:
                pct = None
        raw[parts[0]].append((syl, pct))
    out: dict[str, list[tuple[str, float]]] = {}
    for ch, items in raw.items():
        merged: dict[str, float | None] = {}
        for syl, pct in items:
            old = merged.get(syl)
            merged[syl] = pct if old is None else (old if pct is None else max(old, pct))
        known = sum(p for p in merged.values() if p is not None)
        unknown = [s for s, p in merged.items() if p is None]
        rest = max(0.0, 1.0 - known)
        shares = []
        for syl, pct in merged.items():
            if pct is None:
                pct = (rest / len(unknown)) if rest > 0.001 else 0.01
            shares.append((syl, max(pct, 0.0005)))
        out[ch] = sorted(shares, key=lambda x: -x[1])
    return out


# --------------------------------------------------------------------------- build


class Row:
    __slots__ = ("phrase", "syllables", "senses", "freq", "meta_only")

    def __init__(self, phrase: str, syllables: tuple[str, ...]):
        self.phrase = phrase
        self.syllables = syllables
        self.senses: list[str] = []
        self.freq = 0.0
        self.meta_only = True


def build(min_essay_only: int = ESSAY_ONLY_MIN) -> list[tuple[str, tuple[str, ...], str, int]]:
    essay = load_essay()
    luna = load_luna()
    text = gzip.decompress(fetch_cedict()).decode("utf-8")

    rows: dict[tuple[str, tuple[str, ...]], Row] = {}
    word_t2s: dict[str, str] = {}  # CEDICT traditional word -> simplified word
    char_t2s: dict[str, str] = {}  # traditional/variant char -> simplified char
    variant_t2s: dict[str, str] = {}

    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        trad, simp, gloss = m.group("trad"), m.group("simp"), m.group("gloss")
        if not HAN_RE.match(simp):
            continue
        meta = is_meta_only(gloss)
        word_t2s.setdefault(trad, simp)
        if len(trad) == 1 and len(simp) == 1:
            (variant_t2s if meta else char_t2s).setdefault(trad, simp)
        syllables = tuple(normalize_syllable(s) for s in m.group("pinyin").split())
        if len(syllables) != len(simp) or any(s not in VALID_SYLLABLES for s in syllables):
            continue
        row = rows.setdefault((simp, syllables), Row(simp, syllables))
        senses = gloss_senses(gloss)
        # Real senses first; a "variant of" entry never pushes out a real meaning.
        if not meta and row.meta_only:
            row.senses = senses + row.senses
            row.meta_only = False
        else:
            row.senses.extend(senses)
    for k, v in variant_t2s.items():
        char_t2s.setdefault(k, v)

    # rime-essay is traditional and uses variants (爲 for 為, 喫 for 吃, 裏 for 裡):
    # fold every essay word onto its simplified form and sum the counts.
    def to_simp(word: str) -> str:
        return word_t2s.get(word) or "".join(char_t2s.get(ch, ch) for ch in word)

    simp_count: dict[str, int] = defaultdict(int)
    for word, count in essay.items():
        simp_count[to_simp(word)] += count

    for row in rows.values():
        count = float(simp_count.get(row.phrase, 0))
        if row.meta_only:
            count *= 0.02
        if len(row.phrase) == 1:
            shares = dict(luna.get(row.phrase, []))
            if shares:
                count *= shares.get(row.syllables[0], 0.002)
        row.freq = count

    # Essay words that CC-CEDICT does not have (common collocations like 我是).
    by_phrase: dict[str, list[Row]] = defaultdict(list)
    for row in rows.values():
        by_phrase[row.phrase].append(row)
    longest = max(len(p) for p in by_phrase)

    def best_row(word: str) -> Row | None:
        cands = by_phrase.get(word)
        return max(cands, key=lambda r: r.freq) if cands else None

    def compose_gloss(phrase: str) -> str:
        """Gloss a CEDICT-less word from its most probable CEDICT segmentation."""
        n = len(phrase)
        best: list[tuple[float, list[str]] | None] = [None] * (n + 1)
        best[0] = (0.0, [])
        for i in range(n):
            if best[i] is None:
                continue
            for size in range(1, min(longest, n - i) + 1):
                row = best_row(phrase[i : i + size])
                if row is None or not row.senses:
                    continue
                score = best[i][0] + math.log(row.freq + 2) - 12.0
                if best[i + size] is None or score > best[i + size][0]:
                    best[i + size] = (score, best[i][1] + [phrase[i : i + size]])
        if best[n] is None:
            return ""
        parts = []
        for word in best[n][1]:
            sense = best_row(word).senses[0].split(";")[0]
            sense = re.sub(r"\s*\([^)]*\)\s*", " ", sense).strip() or sense.strip()
            parts.append(sense)
        return "≈ " + " + ".join(parts)

    added = 0
    for simp, count in simp_count.items():
        if count < min_essay_only or not 2 <= len(simp) <= 5:
            continue
        if not HAN_RE.match(simp) or simp in by_phrase:
            continue
        options = []
        for ch in simp:
            readings = luna.get(ch)
            if not readings:
                break
            top = [r for r in readings if r[1] >= 0.3][:2] or readings[:1]
            options.append(top)
        else:
            combos = list(itertools.product(*options))[:4]
            total = sum(_prod(c) for c in combos)
            for combo in combos:
                syllables = tuple(s for s, _ in combo)
                row = rows.setdefault((simp, syllables), Row(simp, syllables))
                row.freq += count * _prod(combo) / total
                row.meta_only = False
                if not row.senses:
                    g = compose_gloss(simp)
                    row.senses = [g] if g else []
            added += 1
    print(f"Added {added} essay-only words.", file=sys.stderr)

    out = []
    for row in rows.values():
        freq = int(round(row.freq))
        # Keep every real CEDICT word (floor 1), but drop zero-count variant stubs.
        if row.meta_only and freq == 0 and len(row.phrase) == 1:
            freq = 0
        else:
            freq = max(freq, 1)
        out.append((row.phrase, row.syllables, short_gloss(row.senses), freq))
    return out


def _prod(combo) -> float:
    p = 1.0
    for _, share in combo:
        p *= share
    return p


def write_tsv_gz(rows, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    buf = io.StringIO()
    buf.write("# Ciji lexicon: CC-CEDICT (CC BY-SA 4.0) + rime-essay frequencies (LGPL-3.0)\n")
    buf.write("# phrase\\tsyllables\\txiaohe\\tquanpin\\tgloss\\tfreq\n")
    written = 0
    encoded = []
    for phrase, syllables, gloss, freq in rows:
        xh = encode_xiaohe(syllables)
        if xh is None:
            continue
        encoded.append((xh, -freq, phrase, syllables, gloss, freq))
    encoded.sort()
    for xh, _, phrase, syllables, gloss, freq in encoded:
        gloss = gloss.replace("\t", " ").replace("\n", " ")
        buf.write(f"{phrase}\t{' '.join(syllables)}\t{xh}\t{''.join(syllables)}\t{gloss}\t{freq}\n")
        written += 1
    payload = buf.getvalue().encode("utf-8")
    # mtime=0 keeps the output byte-for-byte reproducible.
    with open(dest, "wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9, mtime=0) as fh:
        fh.write(payload)
    print(
        f"Wrote {written} rows → {dest} ({dest.stat().st_size} bytes gzipped, {len(payload)} raw).",
        file=sys.stderr,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the Ciji lexicon.")
    parser.add_argument("--output", type=Path, default=REPO_ROOT / "Ciji" / "Resources" / "cedict.tsv.gz")
    parser.add_argument("--min-essay", type=int, default=ESSAY_ONLY_MIN)
    args = parser.parse_args()
    rows = build(args.min_essay)
    if len(rows) < 50000:
        print("ERROR: dictionary is unexpectedly small.", file=sys.stderr)
        return 1
    write_tsv_gz(rows, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
