#!/usr/bin/env python3
"""Xiaohe / Quanpin helpers shared by the dictionary builder and tests.

The Swift engine in Ciji/Engine must stay aligned with these tables.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple

# Xiaohe initials: most map to themselves; retroflex cluster remap.
INITIAL_KEYS = {
    "b": "b",
    "p": "p",
    "m": "m",
    "f": "f",
    "d": "d",
    "t": "t",
    "n": "n",
    "l": "l",
    "g": "g",
    "k": "k",
    "h": "h",
    "j": "j",
    "q": "q",
    "x": "x",
    "r": "r",
    "z": "z",
    "c": "c",
    "s": "s",
    "y": "y",
    "w": "w",
    "zh": "v",
    "ch": "i",
    "sh": "u",
}

# Finals after an initial (user-specified Xiaohe table).
FINAL_KEYS = {
    "a": "a",
    "o": "o",
    "e": "e",
    "i": "i",
    "u": "u",
    "v": "v",
    "ai": "d",
    "ei": "w",
    "ui": "v",
    "ao": "c",
    "ou": "z",
    "iu": "q",
    "ie": "p",
    "ue": "t",
    "ve": "t",
    "an": "j",
    "en": "f",
    "in": "b",
    "un": "y",
    "vn": "y",
    "ang": "h",
    "eng": "g",
    "ing": "k",
    "ong": "s",
    "iong": "s",
    "ia": "x",
    "ua": "x",
    "iao": "n",
    "ian": "m",
    "iang": "l",
    "uang": "l",
    "uai": "k",
    "uan": "r",
    "uo": "o",
}

# Standalone finals that form a syllable with no initial.
ZERO_INITIAL_SYLLABLES = {
    "a",
    "ai",
    "an",
    "ang",
    "ao",
    "e",
    "ei",
    "en",
    "eng",
    "er",
    "o",
    "ou",
}

CONSONANT_INITIALS = frozenset("bpmfdtnlgkhjqxrzcsyw")

# Complete modern Hanyu Pinyin syllable inventory (tone-less).
# Used for quanpin segmentation and to reject illegal CEDICT readings.
_SYLLABLE_ROWS = """
a ai an ang ao e ei en eng er o ou
ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu
ca cai can cang cao ce cen ceng ci cong cou cu cuan cui cun cuo
cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo
da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
fa fan fang fei fen feng fo fou fu
ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo
ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
ka kai kan kang kao ke ken keng kong kou ku kua kuai kuan kuang kui kun kuo
la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lue lun luo lv lve
ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nuan nue nuo nv nve
pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo
sa sai san sang sao se sen seng si song sou su suan sui sun suo
sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo
ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
wa wai wan wang wei wen weng wo wu
xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
za zai zan zang zao ze zei zen zeng zi zong zou zu zuan zui zun zuo
zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo
"""

VALID_SYLLABLES = frozenset(_SYLLABLE_ROWS.split())

# Longest-first so "zhuang" wins over "zh"+"uang" when scanning.
_SYLLABLES_BY_LEN = sorted(VALID_SYLLABLES, key=len, reverse=True)
_MAX_SYL_LEN = max(len(s) for s in VALID_SYLLABLES)


def normalize_syllable(raw: str) -> str:
    """Lowercase a CEDICT-style pinyin syllable and fold ü spellings."""
    s = raw.strip().lower()
    tones = "12345"
    while s and s[-1] in tones:
        s = s[:-1]
    s = (
        s.replace("u:", "v")
        .replace("ü", "v")
        .replace("ɥ", "v")
        .replace("ê", "e")
    )
    # CEDICT writes lüe/nüe as lue/nue or lve/nve.
    if s in ("lue", "nve", "nue", "lve"):
        s = s[0] + "ve"
    if s in ("lv", "nv"):
        return s
    # After j/q/x/y, ü is already written as u in standard pinyin.
    return s


def split_initial_final(syllable: str) -> Tuple[str, str]:
    s = normalize_syllable(syllable)
    if s.startswith(("zh", "ch", "sh")) and len(s) > 2:
        return s[:2], s[2:]
    if s.startswith(("zh", "ch", "sh")) and s in VALID_SYLLABLES:
        # zhi/chi/shi — final is implied "i" only when 3 letters; zh alone is invalid.
        if len(s) == 3:
            return s[:2], s[2:]
    if s in ZERO_INITIAL_SYLLABLES:
        return "", s
    if s and s[0] in CONSONANT_INITIALS and s[1:]:
        return s[0], s[1:]
    return "", s


def encode_xiaohe_syllable(syllable: str) -> Optional[str]:
    """Return the 2-key Xiaohe code, or None if the syllable is illegal."""
    s = normalize_syllable(syllable)
    if s not in VALID_SYLLABLES:
        return None
    initial, final = split_initial_final(s)
    if not initial:
        if len(final) == 1:
            return final + final  # aa / ee / oo
        if len(final) == 2:
            return final  # keep quanpin: ai, ei, ao, ou, an, en, er
        key = FINAL_KEYS.get(final)
        if key is None:
            return None
        return final[0] + key  # ang=ah, eng=eg
    init_key = INITIAL_KEYS.get(initial)
    fin_key = FINAL_KEYS.get(final)
    if init_key is None or fin_key is None:
        return None
    return init_key + fin_key


def encode_xiaohe(syllables: Sequence[str]) -> Optional[str]:
    parts = []
    for syl in syllables:
        code = encode_xiaohe_syllable(syl)
        if code is None:
            return None
        parts.append(code)
    return "".join(parts)


def quanpin_joined(syllables: Sequence[str]) -> str:
    return "".join(normalize_syllable(s) for s in syllables)


def segment_quanpin(keys: str) -> Optional[List[str]]:
    """Segment a tone-less quanpin string into valid syllables (DP, greedy-long)."""
    s = keys.lower()
    n = len(s)
    if n == 0:
        return []
    prev: List[Optional[int]] = [None] * (n + 1)
    prev[0] = -1
    for i in range(n):
        if prev[i] is None:
            continue
        for length in range(1, min(_MAX_SYL_LEN, n - i) + 1):
            piece = s[i : i + length]
            if piece in VALID_SYLLABLES:
                nxt = i + length
                # Prefer fewer syllables; among equals, keep first found (longer first).
                if prev[nxt] is None:
                    prev[nxt] = i
    if prev[n] is None:
        return None
    out: List[str] = []
    i = n
    while i > 0:
        j = prev[i]
        assert j is not None and j >= 0
        out.append(s[j:i])
        i = j
    out.reverse()
    return out


def segment_quanpin_prefix(keys: str) -> Tuple[List[str], str]:
    """Segment as many leading syllables as possible; return (complete, remainder)."""
    s = keys.lower()
    if not s:
        return [], ""
    full = segment_quanpin(s)
    if full is not None:
        return full, ""
    # Trim the tail until the head segments.
    for cut in range(len(s) - 1, 0, -1):
        head = segment_quanpin(s[:cut])
        if head is not None:
            return head, s[cut:]
    return [], s


def xiaohe_syllables(keys: str) -> Tuple[List[str], str]:
    """Chunk Xiaohe input into 2-key syllables plus an optional leftover key."""
    s = keys.lower()
    complete = [s[i : i + 2] for i in range(0, len(s) - (len(s) % 2), 2)]
    rest = s[len(complete) * 2 :]
    return complete, rest


def format_segmented(parts: Sequence[str], rest: str = "") -> str:
    bits = list(parts)
    if rest:
        bits.append(rest)
    return "'".join(bits)


def shorten_gloss(gloss: str, limit: int = 28) -> str:
    text = gloss.strip()
    if not text:
        return ""
    # CEDICT uses /def1/def2/
    parts = [p.strip() for p in text.split("/") if p.strip()]
    if not parts:
        parts = [text]
    # Drop meta notes.
    cleaned = []
    for p in parts:
        low = p.lower()
        if (
            low.startswith("see ")
            or "variant of" in low
            or low.startswith("erhua")
            or low.startswith("archaic")
        ):
            continue
        # Strip parenthetical taxonomy when the rest is usable.
        cleaned.append(p)
        if len(cleaned) >= 2:
            break
    if not cleaned:
        cleaned = parts[:1]
    joined = "; ".join(cleaned)
    if len(joined) > limit:
        joined = joined[: limit - 1].rstrip() + "…"
    return joined


# --------------------------------------------------------------------------
# Decoder. Ciji/Engine/Lexicon.swift + Decoder.swift mirror this exactly;
# change both together and keep tests/test_engine.py green.
# --------------------------------------------------------------------------

import math
from bisect import bisect_left


@dataclass(frozen=True)
class LexEntry:
    phrase: str
    syllables: Tuple[str, ...]
    xiaohe: str
    quanpin: str
    gloss: str
    freq: int

    @property
    def syllable_count(self) -> int:
        return len(self.syllables)


@dataclass
class Candidate:
    phrase: str
    gloss: str
    consumed: int  # number of typed keys this candidate replaces
    segmented: str
    score: float
    source: str  # "sentence" | "word" | "partial"


# Cap for prefix scans so a one-letter prefix never walks the whole lexicon.
PREFIX_SCAN_LIMIT = 60000
# Completing the last syllable (quanpin "zhonggu" → 中国) costs this much log-prob.
EXTENSION_PENALTY = 2.5


class Lexicon:
    def __init__(self, entries: Sequence[LexEntry]):
        self.entries = list(entries)
        total = sum(max(e.freq, 0) for e in self.entries) or 1
        self.log_total = math.log(total)
        self.by_code: dict[str, dict[str, List[LexEntry]]] = {"xiaohe": {}, "quanpin": {}}
        for e in self.entries:
            self.by_code["xiaohe"].setdefault(e.xiaohe, []).append(e)
            self.by_code["quanpin"].setdefault(e.quanpin, []).append(e)
        self.sorted_codes: dict[str, List[str]] = {}
        for scheme, table in self.by_code.items():
            for lst in table.values():
                lst.sort(key=lambda e: -e.freq)
            self.sorted_codes[scheme] = sorted(table)

    def logp(self, entry: LexEntry) -> float:
        return math.log(entry.freq + 1) - self.log_total

    def exact(self, scheme: str, code: str) -> List[LexEntry]:
        return self.by_code[scheme].get(code, [])

    def completions(
        self, scheme: str, head: Sequence[str], tail: str, limit: int
    ) -> List[LexEntry]:
        """Top entries spelled `head` syllables + one syllable starting with `tail`."""
        prefix = "".join(head) + tail
        syllables = len(head) + 1
        codes = self.sorted_codes[scheme]
        table = self.by_code[scheme]
        found: List[LexEntry] = []
        i = bisect_left(codes, prefix)
        scanned = 0
        while i < len(codes) and codes[i].startswith(prefix) and scanned < PREFIX_SCAN_LIMIT:
            for e in table[codes[i]]:
                if e.syllable_count == syllables and (
                    scheme == "xiaohe" or _quanpin_fits(e, head, tail)
                ):
                    found.append(e)
            i += 1
            scanned += 1
        found.sort(key=lambda e: -e.freq)
        return found[:limit]


def _quanpin_fits(entry: LexEntry, head: Sequence[str], tail: str) -> bool:
    # Joined quanpin codes are ambiguous (xian vs xi'an); check syllable by syllable.
    n = len(head)
    return tuple(entry.syllables[:n]) == tuple(head) and entry.syllables[n].startswith(tail)


@dataclass
class Segmentation:
    units: List[str]  # complete syllable codes (xiaohe pairs or quanpin syllables)
    ends: List[int]  # key offset just after each unit
    rest: str  # trailing incomplete code
    display: str


def segment(scheme: str, keys: str) -> Segmentation:
    keys = keys.lower()
    if scheme == "xiaohe":
        units, rest = xiaohe_syllables(keys)
        ends = [2 * (i + 1) for i in range(len(units))]
        return Segmentation(units, ends, rest, format_segmented(units, rest))
    units: List[str] = []
    ends: List[int] = []
    offset = 0
    chunks = keys.split("'")
    rest = ""
    for idx, chunk in enumerate(chunks):
        head, tail = segment_quanpin_prefix(chunk)
        for syl in head:
            offset += len(syl)
            units.append(syl)
            ends.append(offset)
        if tail:
            # Anything unparsed stops segmentation; it stays as raw rest.
            rest = tail if idx == len(chunks) - 1 else "'".join([tail] + chunks[idx + 1 :])
            break
        offset += 1  # the apostrophe
    return Segmentation(units, ends, rest, format_segmented(units, rest))


def sentence_gloss(words: Sequence[LexEntry]) -> str:
    parts = []
    for e in words:
        g = e.gloss.split(";")[0].strip()
        if g.startswith("≈ "):
            g = g[2:]
        if g:
            parts.append(g)
    return " · ".join(parts)


def decode(lexicon: Lexicon, scheme: str, keys: str) -> List[Candidate]:
    keys = keys.lower()
    if not keys:
        return []
    seg = segment(scheme, keys)
    units, rest = seg.units, seg.rest
    n = len(units)
    total_keys = len(keys)

    def code(i: int, j: int) -> str:
        return "".join(units[i:j])

    def exact(i: int, j: int) -> List[LexEntry]:
        words = lexicon.exact(scheme, code(i, j))
        if scheme == "quanpin":
            want = tuple(units[i:j])
            words = [e for e in words if e.syllables == want]
        return words

    # --- sentence DP over complete units (+ optional partial last word)
    NEG = float("-inf")
    best = [NEG] * (n + 2)
    path: List[List[LexEntry]] = [[] for _ in range(n + 2)]
    best[0] = 0.0
    for end in range(1, n + 1):
        for start in range(end):
            if best[start] == NEG:
                continue
            words = exact(start, end)
            if not words:
                continue
            w = words[0]
            sc = best[start] + lexicon.logp(w)
            if sc > best[end]:
                best[end] = sc
                path[end] = path[start] + [w]
    final = n
    if rest:
        for start in range(n + 1):
            if best[start] == NEG:
                continue
            words = lexicon.completions(scheme, units[start:n], rest, 1)
            if not words:
                continue
            sc = best[start] + lexicon.logp(words[0])
            if sc > best[n + 1]:
                best[n + 1] = sc
                path[n + 1] = path[start] + [words[0]]
        final = n + 1

    out: List[Candidate] = []
    seen: set[str] = set()

    def add(phrase: str, gloss: str, consumed: int, score: float, source: str) -> None:
        if not phrase or phrase in seen:
            return
        seen.add(phrase)
        out.append(Candidate(phrase, gloss, consumed, seg.display, score, source))

    # --- words covering the whole input
    full: List[Tuple[float, LexEntry]] = []
    if n and not rest:
        full += [(lexicon.logp(e), e) for e in exact(0, n)]
        if scheme == "quanpin" and n >= 2:
            for e in lexicon.completions(scheme, units[: n - 1], units[n - 1], 12):
                if e.syllables[-1] != units[n - 1]:
                    full.append((lexicon.logp(e) - EXTENSION_PENALTY, e))
    elif rest:
        full += [(lexicon.logp(e), e) for e in lexicon.completions(scheme, units, rest, 40)]
    full.sort(key=lambda x: -x[0])

    sentence = path[final] if best[final] != NEG else []
    sentence_score = best[final]
    if len(sentence) >= 2:
        phrase = "".join(e.phrase for e in sentence)
        gloss = sentence_gloss(sentence)
        if not full or sentence_score > full[0][0]:
            add(phrase, gloss, total_keys, sentence_score, "sentence")
            sentence = []
    for i, (score, e) in enumerate(full):
        add(e.phrase, e.gloss, total_keys, score, "word")
        if i == 0 and len(sentence) >= 2:
            add(
                "".join(x.phrase for x in sentence),
                sentence_gloss(sentence),
                total_keys,
                sentence_score,
                "sentence",
            )

    # --- words covering a prefix of the input (longest first)
    for k in range(n - 1 if not rest else n, 0, -1):
        words = exact(0, k)
        if k >= 2:
            words = words[:6]
        for e in words:
            add(e.phrase, e.gloss, seg.ends[k - 1], lexicon.logp(e), "partial")

    if n == 0 and rest:
        for e in lexicon.completions(scheme, [], rest, 60):
            add(e.phrase, e.gloss, total_keys, lexicon.logp(e), "word")
    return out


def decode_xiaohe(lexicon: Lexicon, keys: str) -> List[Candidate]:
    return decode(lexicon, "xiaohe", keys)


def decode_quanpin(lexicon: Lexicon, keys: str) -> List[Candidate]:
    return decode(lexicon, "quanpin", keys)
