import Foundation

/// 诊断日志的回归测试：写入、读回、闪退判定、容量上限，全部走临时目录。
@MainActor
enum DiagnosticsTests {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stock-ledger-diagnostics-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(Diagnostics.fileName)
        let outer = Diagnostics.fileURLOverride
        Diagnostics.fileURLOverride = file
        defer {
            Diagnostics.fileURLOverride = outer
            try? FileManager.default.removeItem(at: directory)
        }
        try? FileManager.default.removeItem(at: file)

        NativeTests.check(Diagnostics.fileURL == file, "日志写入注入的临时路径，不碰真实 Documents")
        NativeTests.check(Diagnostics.text().isEmpty, "没有日志时 text() 返回空字符串")

        // 首次启动：没有历史，不应该谎报闪退。
        Diagnostics.start()
        let first = Diagnostics.text()
        NativeTests.check(first.contains("START"), "首次启动写入 START")
        NativeTests.check(!first.contains("UNCLOSED"), "首次启动不报未正常结束")
        NativeTests.check(first.contains("v"), "启动行包含版本信息")

        // 再次启动而上次没有写 EXIT → 记一条可疑闪退。
        Diagnostics.start()
        NativeTests.check(Diagnostics.text().contains("UNCLOSED"), "上次未正常结束时记录 UNCLOSED")

        // 正常结束：写了 EXIT 之后的下一次启动不应再报。
        try? FileManager.default.removeItem(at: file)
        Diagnostics.start()
        Diagnostics.record("EXIT")
        Diagnostics.start()
        let clean = Diagnostics.text()
        NativeTests.check(!clean.contains("UNCLOSED"), "上次正常结束后不再报未正常结束")
        NativeTests.check(clean.components(separatedBy: "START").count - 1 == 2, "两次启动各记一条 START")

        // 任意错误都能被追加并读回。
        let marker = "unique-\(UUID().uuidString)"
        Diagnostics.record("TEST", marker)
        NativeTests.check(Diagnostics.text().contains(marker), "record 追加的内容可以被读回")
        NativeTests.check(Diagnostics.text().contains("TEST"), "record 记录了来源分类")

        // 超过容量上限后裁剪，但仍保留最新写入。
        for index in 0..<400 {
            Diagnostics.record("FILL", String(repeating: "x", count: 100) + "\(index)")
        }
        let trimmed = Diagnostics.text().split(separator: "\n")
        NativeTests.check(trimmed.count <= 200, "超过上限后裁剪到 200 行以内")
        NativeTests.check(trimmed.last?.contains("399") == true, "裁剪保留最后写入的内容")
        NativeTests.check(trimmed.allSatisfy { $0.contains("  ") }, "裁剪后每行仍可读")
    }
}
