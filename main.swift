import AppKit
import Foundation

func defaultBackupRoot() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("DeckCraft 汉化器/Backups", isDirectory: true)
}

func runningAt(_ target: URL) -> Bool {
    let path = target.standardizedFileURL.resolvingSymlinksInPath().path
    return NSWorkspace.shared.runningApplications.contains {
        $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
    }
}

final class LocalizerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var core: LocalizerCore?
    private var target = URL(fileURLWithPath: "/Applications/DeckCraft.app", isDirectory: true)
    private var state: AppState = .missing
    private var busy = false
    private var lastBackup: URL?
    private let versionField = NSTextField(labelWithString: "正在检测…")
    private let supportField = NSTextField(labelWithString: "")
    private let pathField = NSTextField(wrappingLabelWithString: "")
    private let statusTitle = NSTextField(labelWithString: "正在检测 DeckCraft")
    private let statusDetail = NSTextField(wrappingLabelWithString: "")
    private let statusIcon = NSImageView()
    private let spinner = NSProgressIndicator()
    private var installButton: NSButton!
    private var openButton: NSButton!
    private var refreshButton: NSButton!
    private var chooseButton: NSButton!
    private var backupButton: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if LOCALIZER_UI_TEST
        if let path = Bundle.main.object(forInfoDictionaryKey: "LocalizerTestTargetPath") as? String {
            target = URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        buildMenu()
        buildWindow()
        do {
            guard let resources = Bundle.main.resourceURL else { throw LocalizerError("没有找到内置汉化包。") }
            var backups = defaultBackupRoot()
            #if LOCALIZER_UI_TEST
            if let path = Bundle.main.object(forInfoDictionaryKey: "LocalizerTestBackupPath") as? String { backups = URL(fileURLWithPath: path) }
            #endif
            core = try LocalizerCore.load(resources: resources, backupRoot: backups, isRunning: runningAt)
            supportField.stringValue = "内置支持：DeckCraft " + (core?.catalog.packs.map { $0.version }.joined(separator: "、") ?? "") + " · Apple Silicon"
            refresh()
        } catch {
            statusTitle.stringValue = "汉化器不完整"
            statusDetail.stringValue = error.localizedDescription
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "汉化包错误")
            statusIcon.contentTintColor = .systemOrange
            installButton.isEnabled = false
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { busy ? .terminateCancel : .terminateNow }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }

    private func buildMenu() {
        let bar = NSMenu()
        let item = NSMenuItem(); let menu = NSMenu(title: "DeckCraft 汉化器")
        menu.addItem(withTitle: "关于 DeckCraft 汉化器", action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DeckCraft 汉化器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu; bar.addItem(item); NSApp.mainMenu = bar
    }

    private func label(_ text: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let result = NSTextField(wrappingLabelWithString: text)
        result.font = .systemFont(ofSize: size)
        result.textColor = secondary ? .secondaryLabelColor : .labelColor
        return result
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 668, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DeckCraft 汉化器"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        guard let content = window.contentView else { return }
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 19
        root.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 25),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 64), icon.heightAnchor.constraint(equalToConstant: 64)])
        let title = label("DeckCraft 汉化器", size: 25); title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = label("让 DeckCraft 使用简体中文", size: 14, secondary: true)
        let headerText = NSStackView(views: [title, subtitle]); headerText.orientation = .vertical; headerText.alignment = .leading; headerText.spacing = 5
        let header = NSStackView(views: [icon, headerText]); header.orientation = .horizontal; header.spacing = 16
        root.addArrangedSubview(header)

        let separator = NSBox(); separator.boxType = .separator; root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        pathField.font = .systemFont(ofSize: 12); pathField.textColor = .secondaryLabelColor
        pathField.isSelectable = true; pathField.maximumNumberOfLines = 2; pathField.lineBreakMode = .byTruncatingMiddle
        versionField.font = .systemFont(ofSize: 14, weight: .medium)
        chooseButton = NSButton(title: "选择应用…", target: self, action: #selector(choose))
        chooseButton.bezelStyle = .rounded
        let spacer = NSView()
        let targetRow = NSStackView(views: [label("当前应用", secondary: true), spacer, chooseButton]); targetRow.orientation = .horizontal
        root.addArrangedSubview(targetRow); targetRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let details = NSStackView(views: [versionField, pathField]); details.orientation = .vertical; details.alignment = .leading; details.spacing = 6
        root.addArrangedSubview(details); details.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        supportField.font = .systemFont(ofSize: 12); supportField.textColor = .secondaryLabelColor; root.addArrangedSubview(supportField)

        let statusBox = NSBox(); statusBox.boxType = .custom; statusBox.borderWidth = 0
        statusBox.fillColor = .controlBackgroundColor; statusBox.cornerRadius = 12
        let statusStack = NSStackView(); statusStack.orientation = .horizontal; statusStack.alignment = .top; statusStack.spacing = 12
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusBox.addSubview(statusStack)
        statusIcon.imageScaling = .scaleProportionallyUpOrDown
        statusIcon.widthAnchor.constraint(equalToConstant: 25).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 25).isActive = true
        statusTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        statusDetail.font = .systemFont(ofSize: 13); statusDetail.textColor = .secondaryLabelColor; statusDetail.maximumNumberOfLines = 4
        let statusText = NSStackView(views: [statusTitle, statusDetail]); statusText.orientation = .vertical; statusText.alignment = .leading; statusText.spacing = 7
        statusStack.addArrangedSubview(statusIcon); statusStack.addArrangedSubview(statusText)
        root.addArrangedSubview(statusBox)
        NSLayoutConstraint.activate([
            statusBox.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 106),
            statusStack.topAnchor.constraint(equalTo: statusBox.topAnchor, constant: 16),
            statusStack.leadingAnchor.constraint(equalTo: statusBox.leadingAnchor, constant: 17),
            statusStack.trailingAnchor.constraint(equalTo: statusBox.trailingAnchor, constant: -17),
            statusStack.bottomAnchor.constraint(lessThanOrEqualTo: statusBox.bottomAnchor, constant: -14)
        ])
        let note = label("安装前自动保留完整备份，演示文稿与个人设置保持原样。\n更新到新版本后，请先用本工具检测是否已有对应汉化包。", size: 12, secondary: true)
        root.addArrangedSubview(note); note.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        backupButton = NSButton(title: "查看备份", target: self, action: #selector(showBackups)); backupButton.bezelStyle = .rounded
        refreshButton = NSButton(title: "重新检测", target: self, action: #selector(refresh)); refreshButton.bezelStyle = .rounded
        openButton = NSButton(title: "打开 DeckCraft", target: self, action: #selector(openApp)); openButton.bezelStyle = .rounded
        installButton = NSButton(title: "安装简体中文", target: self, action: #selector(install)); installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let actions = NSStackView(views: [backupButton, refreshButton, NSView(), spinner, openButton, installButton]); actions.orientation = .horizontal; actions.spacing = 9
        root.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }

    private func setBusy(_ value: Bool) {
        busy = value
        chooseButton.isEnabled = !value; refreshButton.isEnabled = !value
        installButton.isEnabled = !value && state.canInstall
        openButton.isEnabled = !value && FileManager.default.fileExists(atPath: target.path)
        backupButton.isEnabled = !value && core.map { FileManager.default.fileExists(atPath: $0.backupRoot.path) } == true
        if value { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    @objc private func refresh() {
        guard !busy, let core else { return }
        pathField.stringValue = target.path
        versionField.stringValue = "正在检测…"; statusTitle.stringValue = "正在检测 DeckCraft"; statusDetail.stringValue = "正在读取已安装版本，请稍候。"
        setBusy(true)
        let appURL = target
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = core.inspect(appURL)
            DispatchQueue.main.async { self?.state = result; self?.render(result); self?.setBusy(false) }
        }
    }

    private func render(_ result: AppState) {
        var symbol = "info.circle.fill"; var color = NSColor.systemBlue
        switch result {
        case .missing:
            versionField.stringValue = "未找到 DeckCraft"
            statusTitle.stringValue = "请选择已安装的 DeckCraft"
            statusDetail.stringValue = "默认检查“应用程序”文件夹。也可以点击“选择应用…”指定其他位置。"
        case .ready(let pack):
            versionField.stringValue = "DeckCraft \(pack.version)"
            statusTitle.stringValue = "此版本可以安装简体中文"
            statusDetail.stringValue = "请先保存演示文稿并退出 DeckCraft，然后点击“安装简体中文”。安装前会自动完整备份原应用。"
        case .chinese(let pack):
            versionField.stringValue = "DeckCraft \(pack.version)"
            statusTitle.stringValue = "当前已是简体中文"
            statusDetail.stringValue = "无需重复安装。今后更新 DeckCraft 后，可再次打开本工具检测。"
            symbol = "checkmark.circle.fill"; color = .systemGreen
        case .unsupported(let version):
            versionField.stringValue = "DeckCraft \(version)"
            statusTitle.stringValue = "此版本尚未适配"
            statusDetail.stringValue = "请等待包含 \(version) 汉化包的新版汉化器。当前应用会保持原样，不会安装旧版或降级。"
            symbol = "exclamationmark.circle.fill"; color = .systemOrange
        case .unknownBuild(let version):
            versionField.stringValue = "DeckCraft \(version)"
            statusTitle.stringValue = "此构建尚未适配"
            statusDetail.stringValue = "版本号相同，但程序与已验证的构建不同。当前应用会保持原样，请使用匹配此构建的汉化包。"
            symbol = "exclamationmark.circle.fill"; color = .systemOrange
        case .invalid(let message):
            versionField.stringValue = "无法识别所选应用"
            statusTitle.stringValue = "无法检测此应用"
            statusDetail.stringValue = message
            symbol = "exclamationmark.triangle.fill"; color = .systemOrange
        }
        statusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusTitle.stringValue)
        statusIcon.contentTintColor = color
        installButton.title = result.isChinese ? "已是简体中文" : "安装简体中文"
        openButton.keyEquivalent = result.isChinese ? "\r" : ""
        installButton.keyEquivalent = result.isChinese ? "" : "\r"
    }

    @objc private func choose() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "选择 DeckCraft 应用"; panel.prompt = "选择"
        panel.allowedFileTypes = ["app"]; panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.target = url; self?.refresh()
        }
    }

    @objc private func install() {
        guard !busy, state.canInstall, let core else { return }
        setBusy(true)
        let appURL = target
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try core.install(appURL) { text in
                    DispatchQueue.main.async { self?.statusTitle.stringValue = text; self?.statusDetail.stringValue = "请保持汉化器打开，安装结束后即可使用。" }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .installed(let backup) = result { self.lastBackup = backup }
                    self.state = core.inspect(appURL); self.render(self.state); self.setBusy(false)
                    if case .installed = result {
                        self.statusTitle.stringValue = "简体中文安装完成"
                        self.statusDetail.stringValue = "现在可以打开 DeckCraft。原应用已完整备份，点击“查看备份”可找到。"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setBusy(false)
                    let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "未完成安装"
                    alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "知道了")
                    alert.beginSheetModal(for: self.window)
                }
            }
        }
    }

    @objc private func openApp() {
        guard !busy else { return }
        NSWorkspace.shared.openApplication(at: target, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { DispatchQueue.main.async { [weak self] in self?.statusDetail.stringValue = "打开失败：\(error.localizedDescription)" } }
        }
    }

    @objc private func showBackups() {
        guard let core, FileManager.default.fileExists(atPath: core.backupRoot.path) else { return }
        if let backup = lastBackup { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
        else { NSWorkspace.shared.open(core.backupRoot) }
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "DeckCraft 汉化器", .applicationVersion: "1.0.0", .version: "简体中文 · 本地离线工具"])
    }
}

if CommandLine.arguments.contains("--verify-payload") {
    do {
        guard let resources = Bundle.main.resourceURL else { throw LocalizerError("没有找到资源目录。") }
        let core = try LocalizerCore.load(resources: resources, backupRoot: defaultBackupRoot(), isRunning: { _ in false })
        for pack in core.catalog.packs { try core.verifyPayload(pack); print("Verified DeckCraft \(pack.version) payload") }
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

let app = NSApplication.shared
let delegate = LocalizerApp()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
