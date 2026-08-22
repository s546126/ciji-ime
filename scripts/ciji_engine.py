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
    consumed: int
    segmented: str
    score: int
    source: str  # "sentence" | "phrase"


def entry_score(entry: LexEntry, consumed: int, input_len: int) -> int:
    score = int(entry.freq)
    if consumed == input_len and len(entry.xiaohe) == input_len:
        score += 8000
    elif consumed == input_len:
        score += 3500
    score += consumed * 40
    score += min(entry.syllable_count, 4) * 25
    if entry.syllable_count == 1:
        score -= 15
    return score


def dp_weight(entry: LexEntry) -> int:
    """Path cost that prefers real words over stacking single characters."""
    if entry.syllable_count >= 2:
        return 3000 * entry.syllable_count + min(entry.freq, 12000)
    return 400 if entry.freq >= 1000 else 80


class Lexicon:
    def __init__(self, entries: Sequence[LexEntry]):
        self.entries = list(entries)
        self.by_xiaohe: dict[str, List[LexEntry]] = {}
        self.by_quanpin: dict[str, List[LexEntry]] = {}
        self.xiaohe_keys: List[str] = []
        self.quanpin_keys: List[str] = []
        for e in self.entries:
            self.by_xiaohe.setdefault(e.xiaohe, []).append(e)
            self.by_quanpin.setdefault(e.quanpin, []).append(e)
        self.xiaohe_keys = sorted(self.by_xiaohe)
        self.quanpin_keys = sorted(self.by_quanpin)

    def _prefix_keys(self, keys: List[str], prefix: str) -> List[str]:
        if not prefix:
            return []
        # Binary search lower bound.
        lo, hi = 0, len(keys)
        while lo < hi:
            mid = (lo + hi) // 2
            if keys[mid] < prefix:
                lo = mid + 1
            else:
                hi = mid
        out = []
        i = lo
        while i < len(keys) and keys[i].startswith(prefix):
            out.append(keys[i])
            i += 1
            if len(out) >= 64:
                break
        return out

    def lookup_xiaohe(self, code: str, prefix: bool = False) -> List[LexEntry]:
        if prefix:
            found: List[LexEntry] = []
            for key in self._prefix_keys(self.xiaohe_keys, code):
                found.extend(self.by_xiaohe[key])
            return found
        return list(self.by_xiaohe.get(code, []))

    def lookup_quanpin(self, code: str, prefix: bool = False) -> List[LexEntry]:
        if prefix:
            found: List[LexEntry] = []
            for key in self._prefix_keys(self.quanpin_keys, code):
                found.extend(self.by_quanpin[key])
            return found
        return list(self.by_quanpin.get(code, []))


def _decode_units(
    units: Sequence[str],
    rest: str,
    raw_keys: str,
    lookup_exact,
    lookup_prefix,
    encode_units,
) -> List[Candidate]:
    n = len(units)
    # DP over complete syllables.
    best_score = [-10**9] * (n + 1)
    best_path: List[Optional[List[LexEntry]]] = [None] * (n + 1)
    best_score[0] = 0
    best_path[0] = []
    for end in range(1, n + 1):
        for start in range(0, end):
            if best_path[start] is None:
                continue
            code = encode_units(units[start:end])
            if not code:
                continue
            for entry in lookup_exact(code):
                sc = best_score[start] + dp_weight(entry)
                if sc > best_score[end]:
                    best_score[end] = sc
                    best_path[end] = (best_path[start] or []) + [entry]

    candidates: List[Candidate] = []
    seen = set()

    def add(phrase: str, gloss: str, consumed: int, segmented: str, score: int, source: str) -> None:
        if phrase in seen or not phrase:
            return
        seen.add(phrase)
        candidates.append(
            Candidate(
                phrase=phrase,
                gloss=gloss,
                consumed=consumed,
                segmented=segmented,
                score=score,
                source=source,
            )
        )

    segmented = format_segmented(units, rest)
    full_consumed = len(raw_keys) - len(rest)

    if n > 0 and best_path[n]:
        path = best_path[n]
        phrase = "".join(e.phrase for e in path)
        gloss = " / ".join(e.gloss for e in path if e.gloss)
        full_code = encode_units(units)
        for entry in lookup_exact(full_code):
            if entry.phrase == phrase and entry.gloss:
                gloss = entry.gloss
                break
        add(phrase, gloss, full_consumed, segmented, best_score[n] + 5000, "sentence")

    # Phrase matches from the start (exact spans, then prefix on leftover).
    for end in range(n, 0, -1):
        code = encode_units(units[:end])
        if not code:
            continue
        consumed_keys = len("".join(units[:end]))
        for entry in lookup_exact(code):
            add(
                entry.phrase,
                entry.gloss,
                consumed_keys,
                segmented,
                entry_score(entry, consumed_keys, len(raw_keys)) + end * 80,
                "phrase",
            )

    if rest:
        prefix_code = encode_units(units) + rest if units else rest
        if encode_units(units) or rest:
            code = (encode_units(units) or "") + rest
            for entry in lookup_prefix(code):
                add(
                    entry.phrase,
                    entry.gloss,
                    len(raw_keys),
                    segmented,
                    entry_score(entry, len(raw_keys), len(raw_keys)),
                    "phrase",
                )

    # Always include first-syllable alternatives.
    if n >= 1:
        code = encode_units(units[:1])
        if code:
            for entry in lookup_exact(code):
                add(
                    entry.phrase,
                    entry.gloss,
                    len(units[0]),
                    segmented,
                    entry_score(entry, len(units[0]), len(raw_keys)),
                    "phrase",
                )

    # Compose 2-character guesses from single-character readings of the
    # first two syllables (握的 / 握得 / 卧的), scored below real words.
    if n >= 2:
        first_code = encode_units(units[:1])
        second_code = encode_units(units[1:2])
        def usable_char(entry: LexEntry) -> bool:
            if len(entry.phrase) != 1:
                return False
            low = entry.gloss.lower()
            return "variant of" not in low and "archaic" not in low

        first_chars = [e for e in lookup_exact(first_code) if usable_char(e)]
        second_chars = [e for e in lookup_exact(second_code) if usable_char(e)]
        first_chars.sort(key=lambda e: -e.freq)
        second_chars.sort(key=lambda e: -e.freq)
        consumed_two = len(units[0]) + len(units[1])
        for a in first_chars[:8]:
            for b in second_chars[:4]:
                combo = a.phrase + b.phrase
                gloss = a.gloss if a.gloss else b.gloss
                if a.gloss and b.gloss and a.gloss != b.gloss:
                    gloss = f"{a.gloss}; {b.gloss}"
                add(
                    combo,
                    shorten_gloss(gloss),
                    consumed_two,
                    segmented,
                    min(a.freq, b.freq) // 4 + 80,
                    "compose",
                )
    elif rest:
        for entry in lookup_prefix(rest):
            add(
                entry.phrase,
                entry.gloss,
                len(raw_keys),
                segmented,
                entry_score(entry, len(raw_keys), len(raw_keys)),
                "phrase",
            )

    candidates.sort(key=lambda c: (-c.score, len(c.phrase), c.phrase))
    return candidates


def decode_xiaohe(lexicon: Lexicon, keys: str) -> List[Candidate]:
    keys = keys.lower()
    if not keys:
        return []
    units, rest = xiaohe_syllables(keys)
    return _decode_units(
        units,
        rest,
        keys,
        lookup_exact=lambda code: lexicon.lookup_xiaohe(code, prefix=False),
        lookup_prefix=lambda code: lexicon.lookup_xiaohe(code, prefix=True),
        encode_units=lambda parts: "".join(parts),
    )


def decode_quanpin(lexicon: Lexicon, keys: str) -> List[Candidate]:
    keys = keys.lower()
    if not keys:
        return []
    units, rest = segment_quanpin_prefix(keys)
    return _decode_units(
        units,
        rest,
        keys,
        lookup_exact=lambda code: lexicon.lookup_quanpin(code, prefix=False),
        lookup_prefix=lambda code: lexicon.lookup_quanpin(code, prefix=True),
        encode_units=lambda parts: "".join(parts),
    )


# Small high-value frequency overlay. Values are added on top of the base score.
FREQUENCY_BOOST = {
    "的": 9800,
    "了": 9600,
    "是": 9500,
    "我": 9400,
    "不": 9300,
    "在": 9200,
    "他": 9100,
    "有": 9000,
    "这": 8900,
    "个": 8800,
    "人": 8700,
    "们": 8600,
    "中": 8500,
    "来": 8400,
    "上": 8300,
    "大": 8200,
    "为": 8100,
    "和": 8000,
    "国": 7900,
    "地": 7800,
    "到": 7700,
    "以": 7600,
    "说": 7500,
    "时": 7400,
    "要": 7300,
    "就": 7200,
    "出": 7100,
    "会": 7000,
    "可": 6900,
    "也": 6800,
    "你": 6700,
    "对": 6600,
    "生": 6500,
    "能": 6400,
    "而": 6300,
    "子": 6200,
    "那": 6100,
    "得": 6000,
    "于": 5900,
    "着": 5800,
    "下": 5700,
    "自": 5600,
    "之": 5500,
    "年": 5400,
    "过": 5300,
    "发": 5200,
    "后": 5100,
    "作": 5000,
    "里": 4900,
    "用": 4800,
    "道": 4700,
    "行": 4600,
    "所": 4500,
    "然": 4400,
    "家": 4300,
    "种": 4200,
    "事": 4100,
    "成": 4000,
    "方": 3900,
    "多": 3800,
    "经": 3700,
    "么": 3600,
    "去": 3500,
    "法": 3400,
    "学": 3300,
    "如": 3200,
    "都": 3100,
    "同": 3000,
    "现": 2900,
    "当": 2800,
    "没": 2700,
    "动": 2600,
    "面": 2500,
    "起": 2450,
    "看": 2400,
    "定": 2350,
    "天": 2300,
    "分": 2250,
    "还": 2200,
    "进": 2150,
    "好": 2100,
    "小": 2050,
    "部": 2000,
    "其": 1980,
    "些": 1960,
    "主": 1940,
    "样": 1920,
    "理": 1900,
    "心": 1880,
    "她": 1860,
    "本": 1840,
    "前": 1820,
    "开": 1800,
    "但": 1780,
    "因": 1760,
    "只": 1740,
    "从": 1720,
    "想": 1700,
    "实": 1680,
    "日": 1660,
    "军": 1640,
    "者": 1620,
    "意": 1600,
    "无": 1580,
    "力": 1560,
    "它": 1540,
    "与": 1520,
    "长": 1500,
    "把": 1480,
    "机": 1460,
    "十": 1440,
    "民": 1420,
    "第": 1400,
    "公": 1380,
    "此": 1360,
    "已": 1340,
    "工": 1320,
    "使": 1300,
    "情": 1280,
    "明": 1260,
    "性": 1240,
    "知": 1220,
    "全": 1200,
    "三": 1180,
    "又": 1160,
    "关": 1140,
    "点": 1120,
    "正": 1100,
    "业": 1080,
    "外": 1060,
    "将": 1040,
    "两": 1020,
    "高": 1000,
    "间": 980,
    "由": 960,
    "问": 940,
    "很": 920,
    "最": 900,
    "重": 880,
    "并": 860,
    "物": 840,
    "手": 820,
    "应": 800,
    "战": 780,
    "向": 760,
    "头": 740,
    "文": 720,
    "体": 700,
    "政": 680,
    "美": 660,
    "相": 640,
    "见": 620,
    "被": 600,
    "利": 590,
    "什": 580,
    "二": 570,
    "等": 560,
    "产": 550,
    "或": 540,
    "新": 530,
    "己": 520,
    "制": 510,
    "身": 500,
    "果": 490,
    "加": 480,
    "西": 470,
    "斯": 460,
    "月": 450,
    "话": 440,
    "合": 430,
    "回": 420,
    "特": 410,
    "代": 400,
    "内": 390,
    "信": 380,
    "表": 370,
    "化": 360,
    "老": 350,
    "给": 340,
    "世": 330,
    "位": 320,
    "次": 310,
    "度": 300,
    "门": 290,
    "任": 280,
    "常": 270,
    "先": 260,
    "海": 250,
    "通": 240,
    "教": 230,
    "儿": 220,
    "原": 210,
    "东": 200,
    "声": 195,
    "提": 190,
    "立": 185,
    "及": 180,
    "比": 175,
    "员": 170,
    "解": 165,
    "水": 160,
    "名": 155,
    "真": 150,
    "论": 145,
    "处": 140,
    "走": 135,
    "义": 130,
    "各": 125,
    "入": 120,
    "几": 115,
    "口": 110,
    "认": 108,
    "条": 106,
    "平": 104,
    "系": 102,
    "区": 100,
    "我的": 9200,
    "名字": 8800,
    "我的名字": 9900,
    "什么": 8600,
    "我们": 8700,
    "自己": 8500,
    "可以": 8400,
    "这个": 8300,
    "没有": 8200,
    "因为": 8100,
    "但是": 8000,
    "如果": 7900,
    "所以": 7800,
    "一个": 9000,
    "不是": 7700,
    "现在": 7600,
    "他们": 7500,
    "自己的": 7400,
    "中国": 9100,
    "什么的": 2000,
    "你好": 7000,
    "谢谢": 6900,
    "谢谢你": 6800,
    "再见": 6700,
    "对不起": 6600,
    "没关系": 6500,
    "请问": 6400,
    "多少": 6300,
    "怎么": 6200,
    "怎样": 6100,
    "为什么": 6000,
    "时候": 5900,
    "时间": 5800,
    "今天": 5700,
    "明天": 5600,
    "昨天": 5500,
    "朋友": 5400,
    "老师": 5300,
    "学生": 5200,
    "工作": 5100,
    "学习": 5000,
    "生活": 4900,
    "问题": 4800,
    "方法": 4700,
    "世界": 4600,
    "国家": 4500,
    "人民": 4400,
    "历史": 4300,
    "文化": 4200,
    "社会": 4100,
    "经济": 4000,
    "政治": 3900,
    "科学": 3800,
    "技术": 3700,
    "电脑": 3600,
    "手机": 3500,
    "输入": 3400,
    "输入法": 3300,
    "拼音": 3200,
    "汉字": 3100,
    "中文": 3000,
    "英语": 2900,
    "单词": 2800,
    "词汇": 2700,
    "意思": 2600,
    "翻译": 2500,
}


# Extra phrases that users expect even if CEDICT omits them as a whole.
EXTRA_PHRASES: List[Tuple[str, Tuple[str, ...], str, int]] = [
    ("我的", ("wo", "de"), "my; mine", 9200),
    ("我的名字", ("wo", "de", "ming", "zi"), "my name", 9900),
    ("我的帽子", ("wo", "de", "mao", "zi"), "my hat", 2100),
    ("输入法", ("shu", "ru", "fa"), "input method", 3300),
]


def base_freq(phrase: str, syllable_count: int) -> int:
    boost = FREQUENCY_BOOST.get(phrase, 0)
    # Prefer real words over obscure long names: shorter common items rank well.
    length_term = max(10, 220 - syllable_count * 18 - max(0, len(phrase) - 4) * 12)
    return boost + length_term
