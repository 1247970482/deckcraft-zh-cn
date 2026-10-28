import Foundation

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/deckcraft-localizer-tests")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
var passed = 0
var failed = 0

func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw LocalizerError(message) }
}

func test(_ name: String, _ operation: () throws -> Void) {
    do { try operation(); passed += 1; print("PASS \(name)") }
    catch { failed += 1; print("FAIL \(name): \(error.localizedDescription)") }
}

func fakeApp(_ app: URL, version: String = "0.11.1", binary: String = "official", identifier: String = "ai.storyteller.deckcraft") throws {
    try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try fm.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "DeckCraft", "CFBundleShortVersionString": version]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    try Data(binary.utf8).write(to: app.appendingPathComponent("Contents/MacOS/DeckCraft"))
    try Data("original notes and licenses".utf8).write(to: app.appendingPathComponent("Contents/Resources/原始资料.txt"))
}

struct Fixture {
    let base: URL
    let target: URL
    let payload: URL
    let backups: URL
    let pack: LanguagePack

    init(_ name: String) throws {
        base = root.appendingPathComponent(name + "-" + UUID().uuidString)
        target = base.appendingPathComponent("含空格的 应用程序/DeckCraft.app")
        payload = base.appendingPathComponent("Resources/Packs/0.11.1/DeckCraft.app")
        backups = base.appendingPathComponent("完整备份")
        try fakeApp(target)
        try fakeApp(payload, binary: "chinese")
        pack = LanguagePack(version: "0.11.1", sourceCommit: "test", architecture: "arm64",
                            originalExecutableSHA256: [try LocalizerCore.hash(target.appendingPathComponent("Contents/MacOS/DeckCraft"))],
                            chineseExecutableSHA256: try LocalizerCore.hash(payload.appendingPathComponent("Contents/MacOS/DeckCraft")),
                            payloadPath: "Packs/0.11.1/DeckCraft.app", files: try LocalizerCore.inventory(payload))
    }
    func core(running: Bool = false, afterMove: (() throws -> Void)? = nil) throws -> LocalizerCore {
        try LocalizerCore(resources: base.appendingPathComponent("Resources"), backupRoot: backups,
                          catalog: Catalog(schema: 1, packs: [pack]), signatureCheck: { _ in },
                          isRunning: { _ in running }, afterOriginalMoved: afterMove)
    }
}

func rejectWithoutChange(_ fixture: Fixture, core: LocalizerCore) throws {
    let before = try LocalizerCore.inventory(fixture.target)
    var rejected = false
    do { _ = try core.install(fixture.target) } catch { rejected = true }
    try require(rejected, "installation should have been rejected")
    try require(LocalizerCore.inventory(fixture.target) == before, "target changed on rejection")
    try require(!fm.fileExists(atPath: fixture.backups.path), "preflight rejection must not create backups")
}

test("recognize exact supported official build") {
    let f = try Fixture("supported"); let core = try f.core()
    try require(core.inspect(f.target).canInstall, "official build not installable")
}

test("already Chinese is idempotent and does not create backups") {
    let f = try Fixture("idempotent"); try fakeApp(f.target, binary: "chinese")
    let core = try f.core(); let before = try LocalizerCore.inventory(f.target)
    if case .alreadyChinese = try core.install(f.target) {} else { throw LocalizerError("not recognized as Chinese") }
    try require(LocalizerCore.inventory(f.target) == before, "Chinese app changed")
    try require(!fm.fileExists(atPath: f.backups.path), "unnecessary backup created")
}

test("new version is never downgraded") {
    let f = try Fixture("future"); try fakeApp(f.target, version: "0.12.0")
    let core = try f.core()
    if case .unsupported("0.12.0") = core.inspect(f.target) {} else { throw LocalizerError("new version misclassified") }
    try rejectWithoutChange(f, core: core)
}

test("same version with an unknown executable is preserved") {
    let f = try Fixture("unknown"); try fakeApp(f.target, binary: "other build")
    try rejectWithoutChange(f, core: f.core())
}

test("unrelated application is rejected") {
    let f = try Fixture("unrelated"); try fakeApp(f.target, identifier: "ai.storyteller.photocraft")
    try rejectWithoutChange(f, core: f.core())
}

test("running app is rejected before any file changes") {
    let f = try Fixture("running")
    try rejectWithoutChange(f, core: f.core(running: true))
}

test("modified payload resource is rejected before backup") {
    let f = try Fixture("damaged")
    try Data("tampered".utf8).write(to: f.payload.appendingPathComponent("Contents/Resources/原始资料.txt"))
    try rejectWithoutChange(f, core: f.core())
}

test("missing payload file is rejected before backup") {
    let f = try Fixture("missing-resource")
    try fm.removeItem(at: f.payload.appendingPathComponent("Contents/Resources/原始资料.txt"))
    try rejectWithoutChange(f, core: f.core())
}

test("signature verification failure leaves original intact") {
    let f = try Fixture("bad-signature")
    let core = try LocalizerCore(resources: f.base.appendingPathComponent("Resources"), backupRoot: f.backups,
                                catalog: Catalog(schema: 1, packs: [f.pack]), signatureCheck: { _ in throw LocalizerError("simulated signature failure") })
    try rejectWithoutChange(f, core: core)
}

test("install preserves a complete verified backup and does not change settings") {
    let f = try Fixture("install")
    let prefs = f.base.appendingPathComponent("personal-settings.json")
    try Data("keep these settings".utf8).write(to: prefs)
    let before = try LocalizerCore.inventory(f.target)
    guard case .installed(let backup) = try f.core().install(f.target) else { throw LocalizerError("did not install") }
    try require(LocalizerCore.inventory(f.target) == f.pack.files, "installed app differs from payload")
    try require(LocalizerCore.inventory(backup) == before, "backup differs from original")
    try require(String(contentsOf: prefs, encoding: .utf8) == "keep these settings", "personal settings changed")
    let receipt = try JSONDecoder().decode(InstallReceipt.self, from: Data(contentsOf: backup.deletingLastPathComponent().appendingPathComponent("恢复信息.json")))
    try require(receipt.status == "installed", "success receipt missing")
}

test("interrupted replacement rolls back the complete original") {
    let f = try Fixture("rollback")
    let before = try LocalizerCore.inventory(f.target)
    let core = try f.core(afterMove: { throw LocalizerError("simulated replacement interruption") })
    var rejected = false
    do { _ = try core.install(f.target) } catch { rejected = true }
    try require(rejected, "injected failure should fail")
    try require(LocalizerCore.inventory(f.target) == before, "rollback did not restore original")
    let receipts = try fm.contentsOfDirectory(at: f.backups, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }
    try require(receipts.count == 1, "backup not retained")
    try require(LocalizerCore.inventory(receipts[0].appendingPathComponent("DeckCraft-安装前.app")) == before, "original backup changed")
    let receipt = try JSONDecoder().decode(InstallReceipt.self, from: Data(contentsOf: receipts[0].appendingPathComponent("恢复信息.json")))
    try require(receipt.status == "rolled-back", "rollback receipt missing")
}

test("repeated compatible updates retain every previous backup") {
    let f = try Fixture("multiple-backups"); let core = try f.core()
    _ = try core.install(f.target)
    try fakeApp(f.target)
    _ = try core.install(f.target)
    let directories = try fm.contentsOfDirectory(at: f.backups, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }
    try require(directories.count == 2, "backup was overwritten")
}

test("relative traversal in a pack manifest is rejected") {
    let f = try Fixture("traversal")
    let malformed = LanguagePack(version: f.pack.version, sourceCommit: "", architecture: "arm64", originalExecutableSHA256: f.pack.originalExecutableSHA256,
                                 chineseExecutableSHA256: f.pack.chineseExecutableSHA256, payloadPath: "../other.app", files: f.pack.files)
    var rejected = false
    do { _ = try LocalizerCore(resources: f.base, backupRoot: f.backups, catalog: Catalog(schema: 1, packs: [malformed])) } catch { rejected = true }
    try require(rejected, "unsafe path accepted")
}

print("RESULT \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
