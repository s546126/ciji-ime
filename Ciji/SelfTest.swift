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
        // English reverse lookup (typing English gives Chinese).
        for (keys, want) in [("hello", "你好"), ("why", "为什么"), ("translate", "翻译"), ("computer", "电脑")] {
            let got = InputDecoder.decode(keys: keys, scheme: .quanpin, lexicon: lexicon, context: noContext).first?.phrase ?? "(none)"
            let ok = got == want
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FAIL") english \(keys) → \(got)")
        }
        if InputDecoder.decode(keys: "hello", scheme: .xiaohe, lexicon: lexicon, context: noContext).first?.phrase != "你好" {
            print("FAIL: xiaohe hello should give 你好")
            failures += 1
        }
        let keysOK = Lexicon.englishKeys("to translate; to interpret (a language)").map(\.0) == ["translate", "interpret"]
        if !keysOK { print("FAIL: englishKeys"); failures += 1 }
        if RelingoSync.headword("to translate; to interpret") != "translate" { print("FAIL: Relingo headword"); failures += 1 }

        // Jev response parsing (System One shape + a bare choice).
        let phrases = ["油箱", "邮箱", "又想"]
        let sample = #"{"answers":{"next":{"probabilities":{"油箱":0.7,"邮箱":0.2,"又想":0.1}}}}"#
        let bare = #"{"decision":{"answer":"又想"}}"#
        let order1 = JevService.parseOrder(Data(sample.utf8), phrases: ["邮箱", "油箱", "又想"])
        let order2 = JevService.parseOrder(Data(bare.utf8), phrases: phrases)
        if order1 != phrases || order2?.first != "又想" {
            print("FAIL: Jev parse \(String(describing: order1)) \(String(describing: order2))")
            failures += 1
        } else {
            print("ok   jev parse")
        }
        let body = JevService.requestBody(context: "汽车", phrases: phrases, model: "typesafe/jev-1.13")
        if let json = try? JSONSerialization.data(withJSONObject: body), let text = String(data: json, encoding: .utf8) {
            print("jev request: \(text)")
        }

        print(failures == 0 ? "selftest passed" : "selftest: \(failures) failure(s)")
        return failures == 0 ? 0 : 1
    }
}
