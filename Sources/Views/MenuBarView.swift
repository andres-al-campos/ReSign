import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(BuildLogStore.self) private var logStore
    let scheduler: Scheduler

    @State private var showSettings = false
    @State private var expandedLogID: UUID?
    @State private var swipedID: UUID?
    @State private var projectListContentHeight: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("ReSign")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()

                if !showSettings {
                    HeaderButton(icon: "arrow.clockwise", help: "Refresh projects") {
                        try? store.refresh()
                    }
                }

                HeaderButton(
                    icon: showSettings ? "arrow.left" : "gear",
                    help: showSettings ? "Back to projects" : "Settings"
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showSettings.toggle()
                        expandedLogID = nil
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if showSettings {
                SettingsPanel()
            } else {
                projectList
            }

            Divider()

            HoverButton("Quit ReSign") {
                NSApplication.shared.terminate(nil)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .onHover { inside in
            // macOS sometimes shows a resize cursor over dividers / scroll
            // edges in a MenuBarExtra window. Force the arrow cursor while
            // hovering anywhere in the popup.
            if inside {
                NSCursor.arrow.set()
            }
        }
    }

    // MARK: - Projects

    @ViewBuilder
    private var projectList: some View {
        if store.projects.isEmpty {
            Text(UserDefaults.standard.string(forKey: "scanPath")?.isEmpty == false
                 ? "No iOS projects found in\n\(UserDefaults.standard.string(forKey: "scanPath")!)"
                 : "No scan path set.\nOpen Settings and choose a folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let allLogs = logStore.logs
            // Measure the content's natural height so the ScrollView can size
            // to fit (showing all cards without scrolling) up to a 320pt cap.
            // macOS 26 collapses a ScrollView that has only a maxHeight to zero
            // height inside MenuBarExtra(.window), so we drive the height from
            // the measured content instead of relying on maxHeight alone.
            let active = store.projects.filter { !$0.isHidden }
            let hidden = store.projects.filter { $0.isHidden }
            ScrollView {
                VStack(spacing: 0) {
                    // Headers only appear once there is something to separate;
                    // a list with nothing hidden reads as a plain list.
                    if !hidden.isEmpty {
                        sectionHeader("Active (\(active.count))")
                    }
                    ForEach(active) { project in
                        card(for: project, log: allLogs[project.id])
                        Divider()
                    }
                    if !hidden.isEmpty {
                        sectionHeader("Hidden (\(hidden.count))")
                        ForEach(hidden) { project in
                            card(for: project, log: allLogs[project.id])
                            Divider()
                        }
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            // Fit the content, capped so about three cards show and the rest
            // scrolls. Never collapse to zero before the first measurement.
            .frame(height: min(max(projectListContentHeight, 44), viewportCap))
            .onPreferenceChange(ContentHeightKey.self) { projectListContentHeight = $0 }
            .onPreferenceChange(CardHeightKey.self) { cardHeight = $0 }
        }
    }

    /// Height cap for the scroll area: three cards plus their dividers, falling
    /// back to the old fixed 320 until the first card measurement lands.
    private var viewportCap: CGFloat {
        guard cardHeight > 0 else { return 320 }
        return cardHeight * 3 + 3
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func card(for project: ManagedProject, log: String?) -> some View {
        ProjectCardRow(
            project: project,
            log: log,
            isExpanded: expandedLogID == project.id,
            isSwiped: swipedID == project.id,
            onRebuild: { scheduler.checkNow(for: project.id) },
            onCancel: { scheduler.cancelBuild(for: project.id) },
            onTap: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedLogID = expandedLogID == project.id ? nil : project.id
                }
            },
            onToggleHidden: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.setHidden(id: project.id, !project.isHidden)
                    // A card that just moved sections shouldn't stay expanded.
                    if expandedLogID == project.id { expandedLogID = nil }
                }
            },
            // Only one card open at a time.
            onSwipeChanged: { open in swipedID = open ? project.id : nil }
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: CardHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

// Card's natural height, used to size the fixed-height swipe row around it.
private struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Measures a single collapsed card so the viewport can be sized to show three
// of them — matching the free-provisioning limit of 3 apps per device.
private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Smallest non-zero: an expanded card carries its log pane and would
        // otherwise inflate the estimate.
        let next = nextValue()
        guard next > 0 else { return }
        value = value == 0 ? next : min(value, next)
    }
}

// Measures the natural height of the project list content so the ScrollView
// can size to fit (up to a cap) instead of collapsing to zero on macOS 26.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Project Card Row

private struct ProjectCardRow: View {
    let project: ManagedProject
    let log: String?
    let isExpanded: Bool
    let isSwiped: Bool
    let onRebuild: () -> Void
    let onCancel: () -> Void
    let onTap: () -> Void
    let onToggleHidden: () -> Void
    let onSwipeChanged: (Bool) -> Void

    @State private var isHovered = false
    @State private var offset: CGFloat = 0
    @State private var rowHeight: CGFloat = 44
    /// Live finger travel during a drag. Plain @State rather than @GestureState:
    /// @GestureState zeroes itself the instant the finger lifts, before the
    /// settle animation on `offset` has started, which shows one frame at the
    /// rest position — the stutter.
    @State private var dragOffset: CGFloat = 0

    /// Width of the revealed action button. Wide enough for icon + label.
    private static let actionWidth: CGFloat = 76

    private var expandedLogText: String {
        var parts: [String] = []
        parts.append(statusSummary)
        if let log, !log.isEmpty {
            parts.append(log)
        }
        return parts.joined(separator: "\n\n")
    }

    private var statusSummary: String {
        if project.isBuilding { return project.buildPhase ?? "Building..." }
        if let error = project.lastError { return error }
        guard let last = project.lastBuiltAt else { return "Never built" }
        let lastStr = DateHelpers.relativeLabel(for: last)
        if let expiry = project.expiryLabel {
            if project.stuckOnOldProfile {
                return "Profile still valid · built \(lastStr) · \(expiry)"
            }
            return "Built \(lastStr) · \(expiry)"
        }
        return "Built \(lastStr)"
    }

    var body: some View {
        VStack(spacing: 0) {
            swipeRow
            expandedLog
        }
    }

    private var swipeRow: some View {
        // The card and its action sit side by side in a row one action-width
        // wider than the viewport, shifted left to reveal the button. Stacking
        // them instead would show both at once: the popover's material
        // background is translucent, so the card can't occlude what's behind it.
        GeometryReader { proxy in
            HStack(spacing: 0) {
                cardContent
                    .frame(width: proxy.size.width)
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(key: RowHeightKey.self, value: inner.size.height)
                        }
                    )

                SwipeActionButton(
                    isHidden: project.isHidden,
                    width: Self.actionWidth,
                    height: rowHeight
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { offset = 0 }
                    onToggleHidden()
                    onSwipeChanged(false)
                }
            }
            .offset(x: offset + dragOffset)
        }
        .frame(height: rowHeight)
        .clipped()
        .onPreferenceChange(RowHeightKey.self) { if $0 > 0 { rowHeight = $0 } }
        .gesture(swipeGesture)
        .onChange(of: isSwiped) { _, swiped in
            // Only react when the parent disagrees with where we already are —
            // e.g. another card opened and this one must close. Without this
            // guard the gesture's own settle animation gets restarted.
            let target: CGFloat = swiped ? -Self.actionWidth : 0
            guard offset != target else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                dragOffset = 0
                offset = target
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Let vertical drags through so the popover still scrolls.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let proposed = offset + value.translation.width
                dragOffset = max(-Self.actionWidth, min(0, proposed)) - offset
            }
            .onEnded { value in
                let proposed = offset + dragOffset
                // Predicted end position, so a quick flick opens without having
                // to travel the full distance.
                let predicted = offset + value.predictedEndTranslation.width
                let shouldOpen = predicted < -Self.actionWidth / 2
                    || proposed < -Self.actionWidth / 2

                // Fold the drag into `offset` and settle in one animated step:
                // zeroing dragOffset separately would flash the rest position.
                withAnimation(.easeOut(duration: 0.18)) {
                    dragOffset = 0
                    offset = shouldOpen ? -Self.actionWidth : 0
                }
                // Tell the parent afterwards, purely so it can close any other
                // open card. `offset` is already correct, so the resulting
                // isSwiped change is a no-op here.
                onSwipeChanged(shouldOpen)
            }
    }

    /// Just the collapsed row — this is what slides. The expanded log pane is
    /// kept out of the clipped, fixed-height swipe area.
    private var cardContent: some View {
        ProjectRowView(project: project, onBuildNow: onRebuild, onCancel: onCancel)
            .opacity(project.isHidden ? 0.45 : 1)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                // A tap while the action is showing dismisses it rather than
                // toggling the log — otherwise there's no way to cancel a swipe.
                if isSwiped || offset != 0 {
                    withAnimation(.easeOut(duration: 0.18)) { offset = 0 }
                    onSwipeChanged(false)
                } else {
                    onTap()
                }
            }
    }

    @ViewBuilder
    private var expandedLog: some View {
        VStack(spacing: 0) {
            if isExpanded {
                let displayText = expandedLogText
                if !displayText.isEmpty {
                    ScrollView {
                        Text(displayText)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 140)
                    .background(.black.opacity(0.05))
                    .overlay(alignment: .topTrailing) {
                        CopyLogButton(log: displayText)
                            .padding(.top, 6)
                            .padding(.trailing, 18)
                    }
                }
            }
        }
    }
}

// MARK: - Swipe Action Button

private struct SwipeActionButton: View {
    let isHidden: Bool
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                // Icon and label state the action, not the current state.
                Image(systemName: isHidden ? "eye" : "eye.slash")
                    .font(.system(size: 13))
                Text(isHidden ? "Show" : "Hide")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .frame(width: width, height: height)
            .background(isHidden ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Copy Log Button

private struct CopyLogButton: View {
    let log: String
    @State private var justCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(log, forType: .string)
            justCopied = true
            Task {
                try? await Task.sleep(for: .milliseconds(1200))
                justCopied = false
            }
        } label: {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(justCopied ? Color.green : Color.primary.opacity(0.7))
                .padding(5)
                .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(justCopied ? "Copied" : "Copy log")
    }
}

// MARK: - Header Button

private struct HeaderButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    init(icon: String, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - Hover Button

private struct HoverButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings Panel

private struct SettingsPanel: View {
    @Environment(ProjectStore.self) private var store
    @AppStorage("scanPath") private var scanPath = ""
    @AppStorage("selectedDeviceID") private var selectedDeviceID = ""
    @State private var devices: [DeviceInfo] = []
    @State private var isLoadingDevices = false
    // Reflect the saved intent (persists across reinstalls), falling back to
    // live OS status so a freshly-registered item still reads as on.
    @State private var launchAtLogin = LoginItemManager.wantsLaunchAtLogin || LoginItemManager.isEnabled
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Launch at login
                HStack {
                    Text("Launch ReSign at login")
                        .controlSize(.small)
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in
                            try? LoginItemManager.setEnabled(newValue)
                            // Reflect saved intent: setEnabled persisted it even
                            // if the OS registration call is briefly out of sync.
                            launchAtLogin = LoginItemManager.wantsLaunchAtLogin
                        }
                }

                Divider()

                // Scan path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan Path")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(scanPath)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Change") { pickFolder() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                }

                Divider()

                // Device picker
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Install Device")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isLoadingDevices {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            HeaderButton(icon: "arrow.clockwise", help: "Refresh devices") {
                                Task { await refreshDevices() }
                            }
                        }
                    }

                    Picker("", selection: $selectedDeviceID) {
                        Text("Automatic")
                            .tag("")

                        ForEach(devices) { device in
                            Text("\(device.name)")
                                .tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        // Same macOS 26 collapse fix as the project list: size to content,
        // clamped into [44, 260], rather than relying on maxHeight alone.
        .frame(height: min(max(contentHeight, 44), 260))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .task { await refreshDevices() }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(filePath: scanPath)
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            scanPath = url.path
            try? store.refresh()
        }
    }

    private func refreshDevices() async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        devices = (try? await DeviceLocator.findAllDevices()) ?? []
    }
}
