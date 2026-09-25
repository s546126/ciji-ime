#!/usr/bin/env python3
"""Offline tests for Xiaohe encoding, segmentation, ranking, and URL joining."""

from __future__ import annotations

import gzip
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from ciji_engine import (  # noqa: E402
    LexEntry,
    Lexicon,
    decode_quanpin,
    decode_xiaohe,
    encode_xiaohe,
    encode_xiaohe_syllable,
    format_segmented,
    segment_quanpin,
    xiaohe_syllables,
)


def load_lexicon() -> Lexicon:
    path = ROOT / "Ciji" / "Resources" / "cedict.tsv.gz"
    if not path.exists():
        raise unittest.SkipTest(f"dictionary not built: {path}")
    entries = []
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        for line in fh:
            if not line.strip() or line.startswith("#"):
                continue
            phrase, syl, xh, qp, gloss, freq = line.rstrip("\n").split("\t")
            entries.append(
                LexEntry(
                    phrase=phrase,
                    syllables=tuple(syl.split()),
                    xiaohe=xh,
                    quanpin=qp,
                    gloss=gloss,
                    freq=int(freq),
                )
            )
    return Lexicon(entries)


class XiaoheEncodingTests(unittest.TestCase):
    def test_retroflex_initials(self) -> None:
        self.assertEqual(encode_xiaohe_syllable("zh"), None)
        self.assertEqual(encode_xiaohe_syllable("zhi"), "vi")
        self.assertEqual(encode_xiaohe_syllable("chi"), "ii")
        self.assertEqual(encode_xiaohe_syllable("shi"), "ui")
        self.assertEqual(encode_xiaohe_syllable("zhang"), "vh")
        self.assertEqual(encode_xiaohe_syllable("chuang"), "il")

    def test_user_final_table(self) -> None:
        self.assertEqual(encode_xiaohe_syllable("ming"), "mk")  # ing=k
        self.assertEqual(encode_xiaohe_syllable("mao"), "mc")  # ao=c
        self.assertEqual(encode_xiaohe_syllable("bai"), "bd")  # ai=d
        self.assertEqual(encode_xiaohe_syllable("bei"), "bw")  # ei=w
        self.assertEqual(encode_xiaohe_syllable("hui"), "hv")  # ui=v
        self.assertEqual(encode_xiaohe_syllable("hou"), "hz")  # ou=z
        self.assertEqual(encode_xiaohe_syllable("liu"), "lq")  # iu=q
        self.assertEqual(encode_xiaohe_syllable("bie"), "bp")  # ie=p
        self.assertEqual(encode_xiaohe_syllable("xue"), "xt")  # ue=t
        self.assertEqual(encode_xiaohe_syllable("ban"), "bj")  # an=j
        self.assertEqual(encode_xiaohe_syllable("ben"), "bf")  # en=f
        self.assertEqual(encode_xiaohe_syllable("bin"), "bb")  # in=b
        self.assertEqual(encode_xiaohe_syllable("lun"), "ly")  # un=y
        self.assertEqual(encode_xiaohe_syllable("bang"), "bh")  # ang=h
        self.assertEqual(encode_xiaohe_syllable("beng"), "bg")  # eng=g
        self.assertEqual(encode_xiaohe_syllable("long"), "ls")  # ong=s
        self.assertEqual(encode_xiaohe_syllable("xiong"), "xs")  # iong=s
        self.assertEqual(encode_xiaohe_syllable("xia"), "xx")  # ia=x
        self.assertEqual(encode_xiaohe_syllable("hua"), "hx")  # ua=x
        self.assertEqual(encode_xiaohe_syllable("biao"), "bn")  # iao=n
        self.assertEqual(encode_xiaohe_syllable("bian"), "bm")  # ian=m
        self.assertEqual(encode_xiaohe_syllable("liang"), "ll")  # iang=l
        self.assertEqual(encode_xiaohe_syllable("guang"), "gl")  # uang=l
        self.assertEqual(encode_xiaohe_syllable("kuai"), "kk")  # uai=k
        self.assertEqual(encode_xiaohe_syllable("huan"), "hr")  # uan=r
        self.assertEqual(encode_xiaohe_syllable("duo"), "do")  # uo=o
        self.assertEqual(encode_xiaohe_syllable("nv"), "nv")
        self.assertEqual(encode_xiaohe_syllable("nve"), "nt")

    def test_zero_initial(self) -> None:
        self.assertEqual(encode_xiaohe_syllable("a"), "aa")
        self.assertEqual(encode_xiaohe_syllable("e"), "ee")
        self.assertEqual(encode_xiaohe_syllable("o"), "oo")
        self.assertEqual(encode_xiaohe_syllable("ai"), "ai")
        self.assertEqual(encode_xiaohe_syllable("en"), "en")
        self.assertEqual(encode_xiaohe_syllable("er"), "er")
        self.assertEqual(encode_xiaohe_syllable("ang"), "ah")
        self.assertEqual(encode_xiaohe_syllable("eng"), "eg")
        self.assertEqual(encode_xiaohe_syllable("ou"), "ou")
        self.assertEqual(encode_xiaohe_syllable("ao"), "ao")

    def test_wodemkzi_is_my_name_not_hat(self) -> None:
        self.assertEqual(encode_xiaohe(("wo", "de", "ming", "zi")), "wodemkzi")
        self.assertEqual(encode_xiaohe(("wo", "de", "mao", "zi")), "wodemczi")
        self.assertNotEqual(
            encode_xiaohe(("wo", "de", "ming", "zi")),
            encode_xiaohe(("wo", "de", "mao", "zi")),
        )

    def test_each_syllable_is_two_keys(self) -> None:
        for syl in ("wo", "de", "ming", "zi", "ang", "a", "zhuang", "nv"):
            code = encode_xiaohe_syllable(syl)
            self.assertIsNotNone(code)
            self.assertEqual(len(code), 2, syl)


class SegmentationTests(unittest.TestCase):
    def test_quanpin_wodemingzi(self) -> None:
        self.assertEqual(segment_quanpin("wodemingzi"), ["wo", "de", "ming", "zi"])

    def test_xiaohe_chunks(self) -> None:
        units, rest = xiaohe_syllables("wodemkzi")
        self.assertEqual(units, ["wo", "de", "mk", "zi"])
        self.assertEqual(rest, "")
        self.assertEqual(format_segmented(units, rest), "wo'de'mk'zi")
        units, rest = xiaohe_syllables("wodemkz")
        self.assertEqual(units, ["wo", "de", "mk"])
        self.assertEqual(rest, "z")


class RankingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.lex = load_lexicon()

    def test_wodemkzi_ranks_my_name(self) -> None:
        cands = decode_xiaohe(self.lex, "wodemkzi")
        self.assertTrue(cands, "expected candidates")
        phrases = [c.phrase for c in cands[:8]]
        self.assertEqual(cands[0].phrase, "我的名字")
        self.assertIn("我的", phrases)
        self.assertNotEqual(cands[0].phrase, "我的帽子")

    def test_wodemczi_is_hat(self) -> None:
        hat = [c.phrase for c in decode_xiaohe(self.lex, "wodemczi")]
        self.assertTrue(any("帽" in p for p in hat[:8]))

    def test_quanpin_my_name(self) -> None:
        cands = decode_quanpin(self.lex, "wodemingzi")
        self.assertTrue(cands)
        self.assertEqual(cands[0].phrase, "我的名字")

    def test_wo_includes_i(self) -> None:
        phrases = [c.phrase for c in decode_xiaohe(self.lex, "wo")]
        self.assertEqual(phrases[0], "我")

    def test_common_single_chars_first(self) -> None:
        for keys, want in (("de", "的"), ("ni", "你"), ("shi", "是"), ("zai", "在"), ("le", "了")):
            self.assertEqual(decode_quanpin(self.lex, keys)[0].phrase, want, keys)
        # 的 is almost never read di: it must not lead "di".
        self.assertNotEqual(decode_quanpin(self.lex, "di")[0].phrase, "的")

    def test_sentences(self) -> None:
        cases = {
            "woshizhongguoren": "我是中国人",
            "jintiantianqizhenhao": "今天天气真好",
            "nihao": "你好",
            "women": "我们",
            "shurufa": "输入法",
        }
        for keys, want in cases.items():
            self.assertEqual(decode_quanpin(self.lex, keys)[0].phrase, want, keys)
        self.assertEqual(decode_xiaohe(self.lex, "uurufa")[0].phrase, "输入法")
        self.assertEqual(decode_xiaohe(self.lex, "nihc")[0].phrase, "你好")

    def test_partial_last_syllable(self) -> None:
        self.assertEqual(decode_xiaohe(self.lex, "wodemkz")[0].phrase, "我的名字")
        self.assertEqual(decode_quanpin(self.lex, "zhonggu")[0].phrase, "中国")
        self.assertEqual(decode_xiaohe(self.lex, "w")[0].phrase, "我")

    def test_apostrophe_forces_split(self) -> None:
        phrases = [c.phrase for c in decode_quanpin(self.lex, "xi'an")]
        self.assertEqual(phrases[0], "西安")
        self.assertNotIn("先", phrases[:3])

    def test_partial_candidates_consume_prefix(self) -> None:
        cands = decode_quanpin(self.lex, "nihao")
        ni = next(c for c in cands if c.phrase == "你")
        self.assertEqual(ni.consumed, 2)
        cands = decode_quanpin(self.lex, "ni'hao")
        ni = next(c for c in cands if c.phrase == "你")
        self.assertEqual(ni.consumed, 2)

    def test_every_candidate_has_english(self) -> None:
        for keys in ("nihao", "woshizhongguoren", "shurufa"):
            top = decode_quanpin(self.lex, keys)[0]
            self.assertTrue(top.gloss, keys)


class URLJoinTests(unittest.TestCase):
    def test_join_chat_completions(self) -> None:
        # Mirrors AppConfig.chatCompletionsURL in Swift.
        def join(base: str) -> str:
            s = base.strip().rstrip("/")
            if s.endswith("/chat/completions"):
                return s
            if s.endswith("/v1"):
                return s + "/chat/completions"
            return s + "/v1/chat/completions"

        self.assertEqual(
            join("http://127.0.0.1:8317"),
            "http://127.0.0.1:8317/v1/chat/completions",
        )
        self.assertEqual(
            join("http://127.0.0.1:8317/v1"),
            "http://127.0.0.1:8317/v1/chat/completions",
        )
        self.assertEqual(
            join("http://127.0.0.1:8317/v1/"),
            "http://127.0.0.1:8317/v1/chat/completions",
        )
        self.assertEqual(
            join("http://127.0.0.1:8317/v1/chat/completions"),
            "http://127.0.0.1:8317/v1/chat/completions",
        )


if __name__ == "__main__":
    unittest.main()
