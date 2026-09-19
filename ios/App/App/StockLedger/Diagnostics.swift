import Foundation

/// 诊断日志：把用户遇到的错误与「上次运行是否正常结束」写成一个可以直接转发的文本文件。
///
/// 设计取舍：
/// - **不安装信号处理器/Swift 运行时钩子**：Swift 的 trap 与内存错误无法在进程内安全拦截。
///   改为在启动/进入后台时各写一个标记，下次启动时若上次没有「正常结束」标记，就记一条
///   可疑闪退——覆盖用户实际会反馈的「前台用着用着闪退」，且不引入崩溃时可执行代码的风险。
/// - **只在状态变化时记录行情失败**：否则每次自动刷新都会刷屏。
/// - **不记录金额、股数、API Key**：错误文案本身不含这些，这里也不主动拼接。
///
/// 已知边界：被 iOS 在后台回收的进程会留下「正常结束」标记，看起来是干净退出——
/// 那不是用户会看到的闪退，可接受。日志上限 32 KB，超出后只保留最后 200 行。
@MainActor
enum Diagnostics {
    static let fileName = "diagnostics.log"
    private static let maximumBytes = 32 * 1024
    private static let keepLines = 200

    /// 仅测试使用：把日志重定向到临时目录，避免测试写到真实的 Documents。
    static var fileURLOverride: URL?

    static var fileURL: URL {
        if let fileURLOverride { return fileURLOverride }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// 应用启动时调用一次：先判断上次是否正常结束，再写下本次的运行环境。
    static func start() {
        if let previous = lastLine(), !previous.hasSuffix(marker("EXIT")) {
            record("UNCLOSED", L10n.tr("上次运行没有正常结束（闪退或被强制退出）。"))
        }
        record("START", "\(version) · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(L10n.current.rawValue)")
    }

    /// 记一条日志。`message` 为空时只写标记（例如进入后台的 `EXIT`）。
    static func record(_ kind: String, _ message: String = "") {
        append("\(timestamp())  \(kind)\(message.isEmpty ? "" : "  \(message)")")
    }

    /// 供界面导出/分享。
    static func text() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    // MARK: - 内部

    private static func marker(_ kind: String) -> String { "  \(kind)" }

    private static func version() -> String {
        let info = Bundle.main
        let short = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(short)(\(build))"
    }

    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func timestamp() -> String { stamp.string(from: Date()) }

    private static func lastLine() -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").last.map(String.init)
    }

    private static func append(_ line: String) {
        var text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        text += line + "\n"
        if text.utf8.count > maximumBytes {
            text = text.split(separator: "\n").suffix(keepLines).joined(separator: "\n") + "\n"
        }
        try? Data(text.utf8).write(to: fileURL, options: .atomic)
    }
}
