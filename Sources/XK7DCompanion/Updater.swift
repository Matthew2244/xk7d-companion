import AppKit
import Sparkle

/// App updates through Sparkle, the update system most Mac apps outside the App Store use.
///
/// Every update is signed with an EdDSA key that only Matthew's Mac holds; the public half is
/// SUPublicEDKey in Info.plist, so a tampered download is refused. Sparkle never checks or opens
/// a window by itself here (SUEnableAutomaticChecks is NO): the app looks every few hours while
/// it's open and says one sentence when there's something new, once per version, when the app
/// is in front and no dialog is open. Help, Check for Updates opens Sparkle's own window.
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private var timer: Timer?
    private var userAsked = false
    /// Called with the new version when a background look finds one.
    var onFound: ((String) -> Void)?
    /// Called with the new version when the person's own Check for Updates found it, so the
    /// background look doesn't announce it again.
    var onSeenByPerson: ((String) -> Void)?
    /// Test hook: a line for each step of an update (XK7D_UPDATE_TEST).
    var log: ((String) -> Void)?

    /// How often to look while the app stays open, and how soon after launch the first look is.
    static let checkEvery: TimeInterval = 4 * 3600
    static let firstCheckAfter: TimeInterval = 15

    var isRunning: Bool { controller != nil }
    var feedURL: String? { controller?.updater.feedURL?.absoluteString }

    /// Start Sparkle without checking. Returns false (and the app carries on) if it can't start,
    /// for example when run with `swift run` outside an app bundle.
    @discardableResult
    func start() -> Bool {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return false }
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do {
            try c.updater.start()
        } catch {
            log?("UPDATER failed to start: \(error.localizedDescription)")
            return false
        }
        // Sparkle's own schedule stays off: its window would appear in the middle of whatever
        // someone is doing. The app's timer does the looking and tells them in words.
        c.updater.automaticallyChecksForUpdates = false
        controller = c
        return true
    }

    /// Look now and then every few hours, quietly.
    func startLooking() {
        guard controller != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstCheckAfter) { [weak self] in self?.lookQuietly() }
        let t = Timer(timeInterval: Self.checkEvery, repeats: true) { [weak self] _ in self?.lookQuietly() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// A background look: no window, ever. Sparkle answers through the delegate below.
    func lookQuietly() {
        guard let updater = controller?.updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdateInformation()
    }

    /// Help, Check for Updates: Sparkle's window, with what's new and Install.
    func checkWithWindow() -> Bool {
        guard let c = controller else { return false }
        userAsked = true
        c.checkForUpdates(nil)
        return true
    }

    /// For the update rehearsal only (XK7D_UPDATE_TEST): download, verify and stage the update in
    /// the background, to be installed when the app quits. Test builds only allow this; release
    /// builds set SUAllowsAutomaticUpdates to NO, which makes Sparkle ignore it.
    func rehearseSilentInstall() {
        guard let updater = controller?.updater else { log?("UPDATER not running"); return }
        updater.automaticallyDownloadsUpdates = true
        log?("UPDATER checking \(updater.feedURL?.absoluteString ?? "no feed") from version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?")")
        updater.checkForUpdatesInBackground()
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log?("UPDATER found \(item.displayVersionString)")
        if userAsked {
            onSeenByPerson?(item.displayVersionString)
        } else {
            onFound?(item.displayVersionString)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { log?("UPDATER no update") }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if updateCheck == .updates { userAsked = false }
        if let error { log?("UPDATER cycle ended: \(error.localizedDescription)") }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { log?("UPDATER downloaded \(item.displayVersionString)") }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        log?("UPDATER download failed: \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) { log?("UPDATER extracted and verified \(item.displayVersionString)") }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        log?("UPDATER will install \(item.displayVersionString) on quit")
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { log?("UPDATER aborted: \(error.localizedDescription)") }
}
