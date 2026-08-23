import Foundation
import Observation

@Observable
@MainActor
final class ProjectStore {
    private(set) var projects: [ManagedProject] = []

    private var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("ReSign", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects.json")
    }

    init() {
        load()
        // Populate synchronously at init. Under macOS 26 the .task on a
        // MenuBarExtra label view does NOT fire, so we can't defer the initial
        // scan there — it would leave the list permanently empty.
        try? refresh()
    }

    /// Re-scans for projects, merging new ones in and preserving existing state.
    func refresh() throws {
        guard let path = UserDefaults.standard.string(forKey: "scanPath"), !path.isEmpty else {
            projects = []
            save()
            return
        }
        let scanRoot = URL(filePath: path)
        // ReSign manages other projects, not itself.
        let selfPath = scanRoot.appendingPathComponent("ReSign")
        let discovered = try ProjectDiscovery.discoverProjects(in: scanRoot, excludedPaths: [selfPath])

        // An empty scan is ambiguous: it means either "this root genuinely has
        // no projects" or "the root couldn't be read" — an unmounted volume, a
        // revoked sandbox permission. Only the second is a reason to keep what
        // we have, since wiping every project's build history on a transient
        // I/O error can't be undone. So check the root rather than the result.
        if discovered.isEmpty, !projects.isEmpty, !isReadable(scanRoot) { return }

        // Keep existing state for known projects, add new ones. Keyed by path
        // rather than name: recursive scanning makes duplicate names plausible
        // (two repos each with ios/App.xcodeproj), and keying by name would
        // collapse them into one entry and discard a project's build state.
        var updated: [ManagedProject] = []
        var claimed: Set<UUID> = []
        for disc in discovered {
            if let existing = matchExisting(disc, claimed: claimed) {
                claimed.insert(existing.id)
                // Adopt the freshly discovered name/path — an xcodegen rename
                // or a moved repo should update rather than fork the entry.
                var merged = existing
                merged.name = disc.name
                merged.projectPath = disc.projectPath
                updated.append(merged)
            } else {
                updated.append(disc)
            }
        }
        projects = updated
        save()
    }

    /// The persisted entry for a freshly discovered project, if any.
    ///
    /// Path is the identity. The name fallback covers a project that moved on
    /// disk, and only fires when it is unambiguous — one unclaimed entry with
    /// that name — so two same-named projects can never inherit each other's
    /// history.
    private func matchExisting(_ disc: ManagedProject, claimed: Set<UUID>) -> ManagedProject? {
        let discPath = Self.canonical(disc.projectPath)
        if let byPath = projects.first(where: {
            !claimed.contains($0.id) && Self.canonical($0.projectPath) == discPath
        }) {
            return byPath
        }
        let byName = projects.filter { !claimed.contains($0.id) && $0.name == disc.name }
        return byName.count == 1 ? byName[0] : nil
    }

    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Whether the scan root can actually be listed, as opposed to being empty.
    private func isReadable(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Parks or unparks a project. Hidden projects are skipped by the
    /// scheduler's automatic passes but still build via Rebuild.
    func setHidden(id: UUID, _ hidden: Bool) {
        update(id: id) { $0.isHidden = hidden }
        save()
    }

    func markBuildStarted(id: UUID) {
        update(id: id) { $0.isBuilding = true; $0.buildPhase = "Starting..." }
    }

    func markBuildSucceeded(id: UUID, profileExpiresAt: Date? = nil) {
        update(id: id) {
            // "Stuck" means: we got a fresh build, but Apple handed back the same
            // (or an older) provisioning profile, so nothing actually bought us
            // more runtime on-device. Detect by comparing against the previous
            // expiry; tolerate a ~60s clock-skew nudge so trivially-same
            // timestamps don't also count as "advanced".
            if let new = profileExpiresAt, let old = $0.profileExpiresAt {
                $0.stuckOnOldProfile = new <= old.addingTimeInterval(60)
            } else {
                $0.stuckOnOldProfile = false
            }

            $0.isBuilding = false
            $0.lastBuiltAt = .now
            $0.lastError = nil
            $0.buildPhase = nil
            $0.profileExpiresAt = profileExpiresAt
        }
        save()
    }

    func markBuildFailed(id: UUID, error: String) {
        update(id: id) { $0.isBuilding = false; $0.lastError = error; $0.buildPhase = nil }
        save()
    }

    func markBuildCancelled(id: UUID) {
        update(id: id) { $0.isBuilding = false; $0.lastError = nil; $0.buildPhase = nil }
    }

    func updateBuildPhase(id: UUID, phase: String) {
        update(id: id) { $0.buildPhase = phase }
    }

    // MARK: - Private

    private func update(id: UUID, mutation: (inout ManagedProject) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        mutation(&projects[index])
    }

    private func save() {
        let data = try? JSONEncoder().encode(projects)
        try? data?.write(to: storeURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder().decode([ManagedProject].self, from: data) else { return }
        // Decided the same way discovery decides, so a cleaned xcodegen project
        // (no .xcodeproj on disk, project.yml still there) survives on the
        // yml's evidence rather than on isIOSProject's permissive
        // can't-read-the-pbxproj fallback.
        projects = saved.filter {
            ProjectDiscovery.isIOSCandidate(
                dir: $0.projectPath.deletingLastPathComponent(),
                xcodeprojURL: $0.projectPath
            )
        }
    }
}
