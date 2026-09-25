import Foundation

/// `Ciji --selftest`: headless check of the Swift engine against the same
/// expectations as tests/test_engine.py. Run by CI on the built app.
enum SelfTest {
    static func run() -> Int32 {
        let started = Date()
        let lexicon = Lexicon.shared
        let loadMs = Int(Date().timeIntervalSince(started) * 1000)
        print("lexicon: \(lexicon.entries.count) entries, loaded in \(loadMs) ms")
        guard lexicon.entries.count > 50_000 else {
            print("FAIL: lexicon too small")
            return 1
        }
        let noContext: (String) -> Double = { _ in 0 }
        let cases: [(Scheme, String, String)] = [
            (.xiaohe, "wodemkzi", "我的名字"),
            (.xiaohe, "wodemkz", "我的名字"),
            (.xiaohe, "uurufa", "输入法"),
            (.xiaohe, "nihc", "你好"),
            (.xiaohe, "wo", "我"),
            (.xiaohe, "w", "我"),
            (.quanpin, "wodemingzi", "我的名字"),
            (.quanpin, "woshizhongguoren", "我是中国人"),
            (.quanpin, "jintiantianqizhenhao", "今天天气真好"),
            (.quanpin, "nihao", "你好"),
            (.quanpin, "women", "我们"),
            (.quanpin, "shurufa", "输入法"),
            (.quanpin, "zhonggu", "中国"),
            (.quanpin, "xi'an", "西安"),
            (.quanpin, "de", "的"),
            (.quanpin, "shi", "是"),
        ]
        var failures = 0
        for (scheme, keys, want) in cases {
            let t0 = Date()
            let cands = InputDecoder.decode(keys: keys, scheme: scheme, lexicon: lexicon, context: noContext)
            let ms = Date().timeIntervalSince(t0) * 1000
            let got = cands.first?.phrase ?? "(none)"
            let ok = got == want && !(cands.first?.gloss.isEmpty ?? true)
            if !ok { failures += 1 }
            let shown = cands.prefix(5).map { "\($0.phrase)[\($0.consumed)]" }.joined(separator: " ")
            print("\(ok ? "ok  " : "FAIL") \(scheme.rawValue) \(keys) → \(got) (\(cands.first?.gloss ?? "")) \(String(format: "%.1f", ms))ms | \(shown)")
        }
        if let ni = InputDecoder.decode(keys: "nihao", scheme: .quanpin, lexicon: lexicon, context: noContext)
            .first(where: { $0.phrase == "你" }), ni.consumed != 2 {
            print("FAIL: 你 should consume 2 keys, got \(ni.consumed)")
            failures += 1
        }
        if InputDecoder.decode(keys: "di", scheme: .quanpin, lexicon: lexicon, context: noContext).first?.phrase == "的" {
            print("FAIL: 的 leads di")
            failures += 1
        }
        print(failures == 0 ? "selftest passed" : "selftest: \(failures) failure(s)")
        return failures == 0 ? 0 : 1
    }
}
