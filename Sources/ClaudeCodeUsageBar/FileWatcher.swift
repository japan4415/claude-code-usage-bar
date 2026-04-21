import Foundation

/// Watches the sessions directory for file changes using DispatchSource (FSEvents).
/// Falls back to a 30-second Timer if DispatchSource cannot be created.
final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var fileDescriptor: Int32 = -1
    private let onChange: () -> Void
    private let debounceInterval: TimeInterval
    private var isStopped = false

    private var debounceWorkItem: DispatchWorkItem?

    /// - Parameters:
    ///   - directory: The directory URL to watch.
    ///   - debounceInterval: Debounce interval in seconds (default 0.2).
    ///   - onChange: Callback invoked on the main queue when changes are detected.
    init(directory: URL, debounceInterval: TimeInterval = 0.2, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounceInterval = debounceInterval
        ensureDirectoryExists(directory)
        startWatching(directory: directory)
    }

    deinit {
        stop()
    }

    // MARK: - Public

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let source {
            source.cancel()
            self.source = nil
        } else {
            // Close fd only if source didn't take ownership via cancelHandler
            if fileDescriptor >= 0 {
                close(fileDescriptor)
                fileDescriptor = -1
            }
        }

        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    // MARK: - Private

    private func ensureDirectoryExists(_ directory: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func startWatching(directory: URL) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            // Cannot open directory — use fallback timer
            startFallbackTimer()
            return
        }
        self.fileDescriptor = fd

        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        dispatchSource.setEventHandler { [weak self] in
            self?.scheduleDebounce()
        }

        dispatchSource.setCancelHandler { [weak self] in
            if let self, self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        dispatchSource.resume()
        self.source = dispatchSource
        // No fallback timer needed when DispatchSource is active
    }

    private func startFallbackTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fallbackTimer?.invalidate()
            self.fallbackTimer = Timer.scheduledTimer(
                withTimeInterval: 30.0,
                repeats: true
            ) { [weak self] _ in
                self?.onChange()
            }
        }
    }

    private func scheduleDebounce() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
