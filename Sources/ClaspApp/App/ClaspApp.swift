import AppKit
import ClaspCore
import Darwin
import OSLog
import SwiftUI

@MainActor
final class ClaspAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.clasp.app", category: "lifecycle")
    private let repository = FileCaptureStore()
    private let credentialStore = KeychainCredentialStore()
    private let hotKeyManager = GlobalHotKeyManager()
    private let selectionReader = AccessibilitySelectionReader()
    private var instanceLock: SingleInstanceLock?

    private lazy var notionClient = NotionClient(
        transport: URLSessionHTTPTransport()
    )
    private lazy var captureService = CaptureService(
        repository: repository,
        credentialStore: credentialStore,
        notion: notionClient
    )
    private lazy var settingsService = SettingsService(
        repository: repository,
        credentialStore: credentialStore,
        notion: notionClient
    )
    private lazy var libraryService = LibraryService(
        repository: repository,
        credentialStore: credentialStore,
        notion: notionClient
    )
    private lazy var deliveryCoordinator = DeliveryCoordinator(
        repository: repository,
        captureService: captureService
    )
    lazy var appModel = AppModel(
        repository: repository,
        captureService: captureService,
        settingsService: settingsService,
        libraryService: libraryService,
        deliveryCoordinator: deliveryCoordinator,
        hotKeyManager: hotKeyManager
    )
    private lazy var capturePanel = CapturePanelCoordinator(model: appModel)
    private lazy var settingsWindow = SettingsWindowCoordinator(model: appModel)
    private lazy var mainWindow = MainWindowCoordinator(model: appModel)
    private lazy var statusItemController = StatusItemController(
        model: appModel,
        onCapture: { [weak self] in self?.beginCapture() },
        onOpenMain: { [weak self] in self?.openFromStatusItem() },
        onPresentationMode: { [weak self] in self?.applyPresentationMode($0) },
        onSettings: { [weak self] in self?.showSettings() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let lock = SingleInstanceLock.acquire() else {
            logger.notice("Another Clasp instance is already running")
            NSApp.terminate(nil)
            return
        }
        instanceLock = lock
        setActivationPolicy(for: appModel.presentationMode)
        statusItemController.install()
        logger.info("Clasp started")
        hotKeyManager.onPressed = { [weak self] in
            DispatchQueue.main.async {
                self?.beginCapture()
            }
        }
        if !hotKeyManager.register(hotKeyManager.savedShortcut()) {
            appModel.statusMessage = "The saved global shortcut is already in use."
        }
        Task {
            await appModel.load()
            if appModel.destinations == nil {
                showSettings()
            } else if appModel.presentationMode != .mini {
                showMain()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appModel.recheckAccessibilityPermission()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard appModel.presentationMode != .mini else { return true }
        if appModel.destinations == nil {
            showSettings()
        } else {
            showMain()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Clasp stopped")
    }

    func beginCapture() {
        Task {
            let outcome = await selectionReader.readSelection()
            let prepared = CapturePreparation.prepare(from: outcome)
            capturePanel.show(prepared)
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    func showMain() {
        mainWindow.show(mode: appModel.presentationMode == .maximum ? .maximum : .medium)
    }

    func openFromStatusItem() {
        if appModel.destinations == nil {
            showSettings()
        } else {
            showMain()
        }
    }

    func applyPresentationMode(_ mode: ClaspPresentationMode) {
        appModel.setPresentationMode(mode)
        setActivationPolicy(for: mode)
        switch mode {
        case .mini:
            mainWindow.hide()
        case .medium, .maximum:
            mainWindow.show(mode: mode)
        }
    }

    private func setActivationPolicy(for mode: ClaspPresentationMode) {
        NSApp.setActivationPolicy(mode == .mini ? .accessory : .regular)
    }
}

private final class SingleInstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire() -> SingleInstanceLock? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.clasp.app.\(getuid()).lock")
            .path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return nil
        }
        return SingleInstanceLock(descriptor: descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

@main
struct ClaspApplication: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ClaspAppDelegate

    var body: some Scene {
        // The status item is managed by StatusItemController so a left click
        // can open the Clasp window while a right click shows the menu;
        // SwiftUI's MenuBarExtra cannot distinguish the two, so it stays
        // uninserted purely to preserve the scene structure.
        MenuBarExtra("Clasp", isInserted: .constant(false)) {
            EmptyView()
        }

        Window("Recent Captures", id: "recent-captures") {
            RecentCapturesView(model: appDelegate.appModel)
        }
        .defaultSize(width: 680, height: 480)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

