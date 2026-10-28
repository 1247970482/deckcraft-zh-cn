import Foundation
import CryptoKit
import Darwin

struct LocalizerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct LanguagePack: Codable {
    let version: String
    let sourceCommit: String
    let architecture: String
    let originalExecutableSHA256: [String]
    let chineseExecutableSHA256: String
    let payloadPath: String
    let files: [String: String]
}

struct Catalog: Codable { let schema: Int; let packs: [LanguagePack] }

enum AppState {
    case missing
    case ready(LanguagePack)
    case chinese(LanguagePack)
    case unsupported(String)
    case unknownBuild(String)
    case invalid(String)

    var canInstall: Bool { if case .ready = self { return true }; return false }
    var isChinese: Bool { if case .chinese = self { return true }; return false }
}

struct AppInfo {
    let version: String
    let executableSHA256: String
}

struct InstallReceipt: Codable {
    let schema: Int
    let date: String
    let targetPath: String
    let version: String
    let originalExecutableSHA256: String
    let chineseExecutableSHA256: String
    let originalFiles: [String: String]
    let backupPath: String
    var status: String
}

enum InstallResult { case alreadyChinese; case installed(URL) }

final class LocalizerCore {
    let resources: URL
    let backupRoot: URL
    let catalog: Catalog
    private let fm = FileManager.default
    private let signatureCheck: (URL) throws -> Void
    private let isRunning: (URL) -> Bool
    // A narrow test seam exercises rollback after the original has moved, before replacement.
    private let afterOriginalMoved: (() throws -> Void)?

    init(resources: URL, backupRoot: URL, catalog: Catalog,
         signatureCheck: @escaping (URL) throws -> Void = LocalizerCore.verifySignature,
         isRunning: @escaping (URL) -> Bool = { _ in false },
         afterOriginalMoved: (() throws -> Void)? = nil) throws {
        guard catalog.schema == 1, !catalog.packs.isEmpty else {
            throw LocalizerError("汉化包清单无法识别，请重新获取完整的汉化器。")
        }
        for pack in catalog.packs {
            guard !pack.version.isEmpty, Self.safeRelative(pack.payloadPath),
                  !pack.files.isEmpty, pack.files.keys.allSatisfy(Self.safeRelative),
                  Self.isSHA256(pack.chineseExecutableSHA256),
                  !pack.originalExecutableSHA256.isEmpty,
                  pack.originalExecutableSHA256.allSatisfy(Self.isSHA256),
                  pack.files.values.allSatisfy(Self.isSHA256) else {
                throw LocalizerError("汉化包清单不完整，请重新获取汉化器。")
            }
        }
        self.resources = resources.standardizedFileURL.resolvingSymlinksInPath()
        self.backupRoot = backupRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.catalog = catalog
        self.signatureCheck = signatureCheck
        self.isRunning = isRunning
        self.afterOriginalMoved = afterOriginalMoved
    }

    static func load(resources: URL, backupRoot: URL, isRunning: @escaping (URL) -> Bool) throws -> LocalizerCore {
        let data = try Data(contentsOf: resources.appendingPathComponent("catalog.json"))
        return try LocalizerCore(resources: resources, backupRoot: backupRoot,
                                 catalog: JSONDecoder().decode(Catalog.self, from: data), isRunning: isRunning)
    }

    private static func safeRelative(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private static func isSHA256(_ text: String) -> Bool {
        text.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func inventory(_ root: URL) throws -> [String: String] {
        let fm = FileManager.default
        let prefix = root.standardizedFileURL.path + "/"
        var enumerationError: Error?
        guard let enumeration = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else {
            throw LocalizerError("无法读取应用文件：\(root.lastPathComponent)")
        }
        var files: [String: String] = [:]
        for case let url as URL in enumeration {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LocalizerError("应用包含符号链接，当前汉化包暂不支持此构建。") }
            if values.isRegularFile == true {
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(prefix) else { throw LocalizerError("应用文件路径异常。") }
                files[String(path.dropFirst(prefix.count))] = try hash(url)
            }
        }
        if let error = enumerationError { throw error }
        return files
    }

    func appInfo(_ target: URL) throws -> AppInfo {
        let plist = target.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plist)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "ai.storyteller.deckcraft",
              info["CFBundleExecutable"] as? String == "DeckCraft",
              let version = info["CFBundleShortVersionString"] as? String, !version.isEmpty else {
            throw LocalizerError("所选应用不是可识别的 DeckCraft。请选择 DeckCraft.app。")
        }
        return AppInfo(version: version, executableSHA256: try Self.hash(target.appendingPathComponent("Contents/MacOS/DeckCraft")))
    }

    func inspect(_ target: URL) -> AppState {
        guard fm.fileExists(atPath: target.path) else { return .missing }
        do {
            let info = try appInfo(target)
            let matches = catalog.packs.filter { $0.version == info.version }
            guard !matches.isEmpty else { return .unsupported(info.version) }
            for pack in matches {
                if info.executableSHA256 == pack.chineseExecutableSHA256 { return .chinese(pack) }
                if pack.originalExecutableSHA256.contains(info.executableSHA256) { return .ready(pack) }
            }
            return .unknownBuild(info.version)
        } catch { return .invalid(error.localizedDescription) }
    }

    private func payload(_ pack: LanguagePack) throws -> URL {
        let url = resources.appendingPathComponent(pack.payloadPath).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(resources.path + "/") else { throw LocalizerError("汉化包路径异常。") }
        return url
    }

    func verifyPayload(_ pack: LanguagePack, at location: URL? = nil) throws {
        let url = try location ?? payload(pack)
        guard try Self.inventory(url) == pack.files else {
            throw LocalizerError("内置中文程序的文件校验失败。安装尚未开始，请重新获取完整汉化器。")
        }
        guard try Self.hash(url.appendingPathComponent("Contents/MacOS/DeckCraft")) == pack.chineseExecutableSHA256 else {
            throw LocalizerError("中文程序与此版本的汉化包不匹配。")
        }
        try signatureCheck(url)
    }

    @discardableResult
    func install(_ selectedTarget: URL, progress: (String) -> Void = { _ in }) throws -> InstallResult {
        let target = selectedTarget.standardizedFileURL.resolvingSymlinksInPath()
        let pack: LanguagePack
        switch inspect(target) {
        case .chinese: return .alreadyChinese
        case .ready(let available): pack = available
        case .missing: throw LocalizerError("没有找到 DeckCraft，请先选择已安装的应用。")
        case .unsupported(let version): throw LocalizerError("当前 DeckCraft \(version) 尚未适配。原应用未改动，请等待此版本的汉化包。")
        case .unknownBuild(let version): throw LocalizerError("此 DeckCraft \(version) 构建尚未适配。原应用未改动。")
        case .invalid(let message): throw LocalizerError(message)
        }
        guard !isRunning(target) else { throw LocalizerError("请先保存演示文稿并退出 DeckCraft，再点击“安装简体中文”。") }
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else { throw LocalizerError("当前用户无法替换此位置的应用。请将 DeckCraft 放到你可写的应用目录后重新选择。") }
        progress("正在校验内置汉化包…")
        try verifyPayload(pack)
        let originalInfo = try appInfo(target)
        let originalFiles = try Self.inventory(target)
        guard originalInfo.version == pack.version, pack.originalExecutableSHA256.contains(originalInfo.executableSHA256) else {
            throw LocalizerError("DeckCraft 在检测后发生了变化，请重新检测。")
        }
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let lockURL = backupRoot.appendingPathComponent(".install.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LocalizerError("无法写入备份目录。原应用未改动。") }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw LocalizerError("另一个汉化任务正在运行，请稍后重新检测。") }
        defer { flock(descriptor, LOCK_UN) }
        let token = UUID().uuidString
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let backup = backupRoot.appendingPathComponent("\(formatter.string(from: Date()))-\(pack.version)-\(token.prefix(8))", isDirectory: true)
        let originalBackup = backup.appendingPathComponent("DeckCraft-安装前.app", isDirectory: true)
        let stage = parent.appendingPathComponent(".DeckCraft-中文安装-\(token).app", isDirectory: true)
        let previous = parent.appendingPathComponent(".DeckCraft-安装前-\(token).app", isDirectory: true)
        defer { if fm.fileExists(atPath: stage.path) { try? fm.removeItem(at: stage) } }
        try fm.createDirectory(at: backup, withIntermediateDirectories: false)
        var receipt = InstallReceipt(schema: 1, date: ISO8601DateFormatter().string(from: Date()), targetPath: target.path,
                                     version: pack.version, originalExecutableSHA256: originalInfo.executableSHA256,
                                     chineseExecutableSHA256: pack.chineseExecutableSHA256, originalFiles: originalFiles,
                                     backupPath: originalBackup.path, status: "preparing")
        let receiptURL = backup.appendingPathComponent("恢复信息.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        func saveReceipt() throws { try encoder.encode(receipt).write(to: receiptURL, options: .atomic) }
        try saveReceipt()
        progress("正在完整备份原应用…")
        try Self.run("/usr/bin/ditto", [target.path, originalBackup.path])
        guard try Self.inventory(originalBackup) == originalFiles else { throw LocalizerError("原应用备份校验失败。原应用未改动，请检查剩余磁盘空间。") }
        progress("正在准备中文程序…")
        try Self.run("/usr/bin/ditto", [try payload(pack).path, stage.path])
        try verifyPayload(pack, at: stage)
        guard !isRunning(target), try Self.inventory(target) == originalFiles else {
            throw LocalizerError("DeckCraft 在备份期间被打开或发生变化，已停止替换。原应用未改动。")
        }
        receipt.status = "backed-up"; try saveReceipt()
        progress("正在安装简体中文…")
        try fm.moveItem(at: target, to: previous)
        do {
            try afterOriginalMoved?()
            try fm.moveItem(at: stage, to: target)
            try verifyPayload(pack, at: target)
            receipt.status = "installed"; try saveReceipt()
        } catch {
            if fm.fileExists(atPath: target.path) {
                try? fm.moveItem(at: target, to: backup.appendingPathComponent("未完成的中文安装.app"))
            }
            do {
                try fm.moveItem(at: previous, to: target)
                receipt.status = "rolled-back"; try? saveReceipt()
            } catch {
                throw LocalizerError("安装中断，原应用仍保存在 \(previous.path)；完整备份位于 \(originalBackup.path)。请从其中恢复。")
            }
            throw LocalizerError("安装没有完成，已恢复安装前的应用。备份位于 \(originalBackup.path)。")
        }
        // The exact pre-install bundle is verified in the permanent backup before this
        // redundant, same-volume transaction copy is removed. Backups are never deleted.
        try? fm.removeItem(at: previous)
        progress("简体中文安装完成")
        return .installed(originalBackup)
    }

    static func run(_ command: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: command); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: output.prefix(4000), encoding: .utf8) ?? ""
            throw LocalizerError("文件操作失败：\(detail.isEmpty ? command : detail)")
        }
    }

    static func verifySignature(_ app: URL) throws {
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }
}
