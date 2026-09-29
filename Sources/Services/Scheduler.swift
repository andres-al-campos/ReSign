import Foundation
import AppKit
import Network

@MainActor
final class Scheduler {
    private var timer: Timer?
    private var signInPollTimer: Timer?
    private var phonePollTimer: Timer?
    private var phoneBrowser: NWBrowser?
    /// Projects whose build failed because the phone wasn't reachable. Rebuilt
    /// as soon as it answers again.
    private var waitingOnPhone: Set<UUID> = []
    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private weak var store: ProjectStore?
    private weak var notifications: NotificationManager?
    private weak var logStore: BuildLogStore?

    /// Projects that were skipped because Xcode is signed out. Rebuilt as soon
    /// as signing recovers.
    private var pendingRetry: Set<UUID> = []
    private var lastKnownSigningState: SigningStatus.State = .unknown(reason: "Not yet checked")

    func start(store: ProjectStore, notifications: NotificationManager, logStore: BuildLogStore) {
        self.store = store
        self.notifications = notifications
        self.logStore = logStore

        // Check once at launch
        Task { await checkDueProjects() }

        // Check after Mac wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkDueProjects() }
        }

        // Wire up notification retry
        notifications.onRetry = { [weak self] id in
            guard let self else { return }
            Task { await self.buildProject(id: id) }
        }

        notifications.onCleanRetry = { [weak self] id in
            guard let self else { return }
            Task { await self.buildProject(id: id, clean: true) }
        }

        notifications.onOpenXcode = {
            XcodeAccounts.open()
        }

        notifications.onOpenProject = { [weak self] id in
            guard let self,
                  let project = self.store?.projects.first(where: { $0.id == id }) else { return }
            // Opens the .xcodeproj/.xcworkspace in Xcode — lands the user in the
            // right project. macOS can't deep-link to the Signing tab.
            //
            // For an xcodegen project the .xcodeproj is generated and may not
            // exist yet (after `build.sh clean`). NSWorkspace.open would fail
            // silently on that path, so fall back to the containing directory —
            // the user lands next to project.yml and build.sh instead of
            // nothing happening.
            if FileManager.default.fileExists(atPath: project.projectPath.path) {
                NSWorkspace.shared.open(project.projectPath)
            } else {
                NSWorkspace.shared.open(project.projectPath.deletingLastPathComponent())
            }
        }

        // Poll signing state every 60s. When the user signs back in, we
        // automatically rebuild anything that was skipped.
        signInPollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.reactToSigningStateChange() }
        }

        // A phone joining Wi-Fi announces itself over Bonjour; check it the
        // moment it does. A phone that walks out of range can't say goodbye,
        // so it may come back without a fresh announcement — the 2-minute
        // poll below catches that case.
        let browser = NWBrowser(for: .bonjour(type: "_remotepairing._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] _, changes in
            guard changes.contains(where: { if case .added = $0 { return true } else { return false } }) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // The announcement can land a few seconds before the phone
                // accepts connections, so try once more if the first probe misses.
                if await self.checkPhoneReturned() { return }
                try? await Task.sleep(for: .seconds(10))
                await self.checkPhoneReturned()
            }
        }
        browser.start(queue: .main)
        phoneBrowser = browser

        // Poll the phone every 2 minutes while a build waits on it, and rebuild
        // as soon as it answers instead of at the next timed check.
        phonePollTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkPhoneReturned() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        signInPollTimer?.invalidate()
        signInPollTimer = nil
        phonePollTimer?.invalidate()
        phonePollTimer = nil
        phoneBrowser?.cancel()
        phoneBrowser = nil
    }

    func checkNow(for id: UUID? = nil) {
        Task {
            if let id {
                await buildProject(id: id)
            } else {
                await checkDueProjects()
            }
        }
    }

    func cancelBuild(for id: UUID) {
        guard let task = inFlight.removeValue(forKey: id) else { return }
        task.cancel()
        store?.markBuildCancelled(id: id)
    }

    // MARK: - Private

    private func checkDueProjects() async {
        guard let store else { return }
        let due = store.projects.filter { $0.isDue && !$0.isBuilding && !$0.isHidden }
        for project in due {
            await buildProject(id: project.id)
        }
        scheduleNextCheck()
    }

    /// Wake when the next watched project comes due, so none sits due and
    /// unbuilt. A due project without an error is one Apple handed the old
    /// profile back to, so retry it every 15 minutes; failed projects keep the
    /// 2-hour cadence so a missing phone doesn't notify every 15 minutes.
    private func scheduleNextCheck() {
        timer?.invalidate()
        let next = store?.projects
            .filter { !$0.isHidden && $0.lastError == nil }
            .compactMap(\.nextDueAt)
            .min()
        let delay = min(max(next?.timeIntervalSinceNow ?? .infinity, 15 * 60), 2 * 3600)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkDueProjects() }
        }
    }

    private func buildProject(id: UUID, clean: Bool = false) async {
        guard let store, let notifications else { return }
        guard inFlight[id] == nil else { return }
        guard let project = store.projects.first(where: { $0.id == id }) else { return }

        // Clean & Retry: drop ReSign's stale DerivedData cache before rebuilding.
        if clean {
            BuildRunner.purgeDerivedData(for: project)
        }

        // Fast pre-flight: is Xcode signed in? Saves ~30s of xcodebuild
        // churn when the answer is "No Accounts".
        let signingState = SigningStatus.current()
        lastKnownSigningState = signingState
        if case .signedOut = signingState {
            pendingRetry.insert(id)
            store.markBuildFailed(
                id: id,
                error: "Not signed in to Xcode. Open Xcode → Settings → Accounts and sign in — I'll retry automatically."
            )
            // Only one notification, no matter how many projects are due.
            notifications.sendSignedOutNotification()
            return
        }

        store.markBuildStarted(id: id)
        logStore?.clearLog(for: id, name: project.name)

        let task = Task { [weak self] in
            let preferredDeviceID = UserDefaults.standard.string(forKey: "selectedDeviceID")
            let projectName = project.name
            let projectID = project.id

            let (result, log) = await BuildRunner.build(
                project: project,
                preferredDeviceID: preferredDeviceID,
                onOutput: { [weak self] text in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.logStore?.appendLog(text, for: projectID, name: projectName)
                        // Parse phase from output
                        if let phase = Self.parsePhase(from: text) {
                            self.store?.updateBuildPhase(id: projectID, phase: phase)
                        }
                    }
                }
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.removeValue(forKey: projectID)
                self.pendingRetry.remove(projectID)
                self.waitingOnPhone.remove(projectID)

                switch result {
                case .success(_, let profileExpiresAt):
                    let displayLog = BuildOutputFilter.extractSuccess(from: log)
                    self.logStore?.save(log: displayLog, for: projectID, name: projectName)
                    store.markBuildSucceeded(id: projectID, profileExpiresAt: profileExpiresAt)
                    notifications.sendSuccessNotification(project: project)
                case .failure(let phase, let message, let kind):
                    if phase == .deviceNotFound { self.waitingOnPhone.insert(projectID) }
                    let displayLog = BuildOutputFilter.extractErrors(from: log)
                    self.logStore?.save(log: displayLog, for: projectID, name: projectName)
                    store.markBuildFailed(id: projectID, error: "\(phase.rawValue): \(message)")
                    // Match the notification's action to how the failure is fixed.
                    switch kind {
                    case .signedOut:
                        // Global fix in Xcode → "Open Xcode". Queue it so the
                        // sign-in poll rebuilds it once the account is back.
                        self.pendingRetry.insert(projectID)
                        self.lastKnownSigningState = .signedOut
                        notifications.sendSignedOutNotification()
                    case .projectSigning:
                        // Fixed in this project's signing settings → "Open Project in Xcode".
                        notifications.sendProjectSigningNotification(project: project, message: message)
                    case .staleCache:
                        // Fixable automatically → "Clean & Retry".
                        notifications.sendStaleCacheNotification(project: project, message: message)
                    case .generic:
                        notifications.sendFailureNotification(project: project, message: message)
                    }
                case .cancelled:
                    self.logStore?.save(log: log, for: projectID, name: projectName)
                    store.markBuildCancelled(id: projectID)
                }
            }
        }

        inFlight[id] = task
    }

    /// Called on a Bonjour announcement and every 2 minutes. Probes only while
    /// a build waits on the phone and nothing is building (a running build is
    /// already using it). Returns false only when the probe found no phone.
    @discardableResult
    private func checkPhoneReturned() async -> Bool {
        guard !waitingOnPhone.isEmpty, inFlight.isEmpty else { return true }
        let preferredID = UserDefaults.standard.string(forKey: "selectedDeviceID")
        guard let device = try? await DeviceLocator.findDevice(preferredID: preferredID),
              await DeviceLocator.isReachable(device.id) else { return false }
        // Same rule as the sign-in retry: an ignored project doesn't wake up.
        let toRetry = waitingOnPhone
        waitingOnPhone.removeAll()
        for id in toRetry where store?.projects.first(where: { $0.id == id })?.isHidden != true {
            await buildProject(id: id)
        }
        return true
    }

    /// Called every 60s. If the signing state flips from signed-out to signed-in,
    /// clear the notification and rebuild anything we had queued.
    private func reactToSigningStateChange() {
        let current = SigningStatus.current()
        let wasSignedOut: Bool = {
            if case .signedOut = lastKnownSigningState { return true }
            return false
        }()
        let isSignedIn: Bool = {
            if case .signedIn = current { return true }
            return false
        }()
        lastKnownSigningState = current

        guard wasSignedOut, isSignedIn else { return }

        notifications?.clearSignedOutNotification()

        // Drain the pending-retry set by kicking off builds for each.
        // Skip anything ignored after it was queued — this is an automatic
        // trigger, so an ignored project shouldn't wake up and build.
        let toRetry = pendingRetry
        pendingRetry.removeAll()
        for id in toRetry {
            guard store?.projects.first(where: { $0.id == id })?.isHidden != true else { continue }
            Task { await self.buildProject(id: id) }
        }
    }

    private static func parsePhase(from text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.contains("=== Device Discovery ===") { return "Finding device..." }
        if line.contains("=== xcodebuild ===") { return "Building..." }
        if line.contains("=== Install ===") { return "Installing..." }
        // A project's build.sh does its own build and install; follow its step headers.
        if line.contains("=== build.sh ===") { return "Building..." }
        if line.contains("→ Installing") { return "Installing..." }
        if line.contains("Compiling") { return "Compiling..." }
        if line.contains("Linking") { return "Linking..." }
        if line.contains("Signing") || line.contains("CodeSign") { return "Signing..." }
        return nil
    }
}
