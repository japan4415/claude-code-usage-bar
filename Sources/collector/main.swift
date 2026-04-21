import Foundation
import ClaudeUsageBarCore

// MARK: - Collector main

/// Read stdin, parse JSON, write session snapshot, output status line.
/// Never fatalError — on any error, write to stderr and exit 0.

func run() {
    // 1. Read stdin
    let inputData = FileHandle.standardInput.readDataToEndOfFile()
    guard !inputData.isEmpty else {
        // Empty input — output nothing useful but don't crash
        print("")
        return
    }

    // 2. Parse JSON
    let input: StatusLineInput
    do {
        input = try JSONDecoder.usageBar.decode(StatusLineInput.self, from: inputData)
    } catch {
        fputs("collector: JSON parse error: \(error.localizedDescription)\n", stderr)
        print("")
        return
    }

    // 3. Build SessionSnapshot
    let now = DateParsing.formatISO8601(Date())
    let snapshot = SessionSnapshot(
        schemaVersion: 1,
        sessionId: input.sessionId,
        updatedAt: now,
        transcriptPath: input.transcriptPath,
        exceeds200kTokens: input.exceeds200kTokens,
        rateLimits: input.rateLimits
    )

    // 4. Write session snapshot (atomic write)
    writeSnapshot(snapshot)

    // 5. Append history entry
    appendHistory(input: input, timestamp: now)

    // 6. Execute upstream statusLine command if configured; relay its output or use default
    let upstreamOutput = executeUpstreamCommand(inputData: inputData)
    let statusLine = buildStatusLine(rateLimits: input.rateLimits)

    if let upstream = upstreamOutput, !upstream.isEmpty {
        // Relay upstream command's output as-is (preserves user's existing statusLine)
        print(upstream)
    } else {
        print(statusLine)
    }
}

// MARK: - File I/O

func writeSnapshot(_ snapshot: SessionSnapshot) {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let sessionsDir = home
        .appendingPathComponent(".claude/claude-usage-bar/sessions", isDirectory: true)

    // Ensure directory exists
    do {
        try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    } catch {
        fputs("collector: mkdir error: \(error.localizedDescription)\n", stderr)
        return
    }

    // Encode
    let data: Data
    do {
        data = try JSONEncoder.usageBar.encode(snapshot)
    } catch {
        fputs("collector: encode error: \(error.localizedDescription)\n", stderr)
        return
    }

    // Atomic write: write to tmp, then rename
    let tmpURL = sessionsDir.appendingPathComponent("session_\(snapshot.sessionId).json.tmp")
    let finalURL = sessionsDir.appendingPathComponent("session_\(snapshot.sessionId).json")

    do {
        try data.write(to: tmpURL)
        _ = try fm.replaceItemAt(finalURL, withItemAt: tmpURL)
    } catch {
        fputs("collector: write error: \(error.localizedDescription)\n", stderr)
        // Clean up tmp if it exists
        try? fm.removeItem(at: tmpURL)
    }
}

func appendHistory(input: StatusLineInput, timestamp: String) {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let historyPath = home.appendingPathComponent(".claude/claude-usage-bar/history.jsonl").path

    let entry = HistoryEntry(
        timestamp: timestamp,
        fiveHourPct: input.rateLimits?.fiveHour?.usedPercentage,
        sevenDayPct: input.rateLimits?.sevenDay?.usedPercentage,
        sessionId: input.sessionId
    )

    do {
        let lineData = try JSONEncoder().encode(entry)
        guard var line = String(data: lineData, encoding: .utf8) else { return }
        line += "\n"
        guard let lineBytes = line.data(using: .utf8) else { return }

        // Use POSIX O_APPEND for atomic append (safe for concurrent writers)
        let fd = open(historyPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else {
            // File might not exist and parent dir might be missing
            let dir = (historyPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let fd2 = open(historyPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            guard fd2 >= 0 else {
                fputs("collector: history open error\n", stderr)
                return
            }
            lineBytes.withUnsafeBytes { ptr in
                _ = write(fd2, ptr.baseAddress!, ptr.count)
            }
            close(fd2)
            return
        }
        lineBytes.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }
        close(fd)
    } catch {
        fputs("collector: history append error: \(error.localizedDescription)\n", stderr)
    }
}

// MARK: - Status Line Output

func buildStatusLine(rateLimits: RateLimits?) -> String {
    guard let limits = rateLimits else {
        return "CC --"
    }

    var parts: [String] = []

    if let fiveHour = limits.fiveHour, let pct = fiveHour.usedPercentage {
        parts.append("5h \(Int(pct))%")
    }

    if let sevenDay = limits.sevenDay, let pct = sevenDay.usedPercentage {
        parts.append("7d \(Int(pct))%")
    }

    if parts.isEmpty {
        return "CC --"
    }

    return "CC " + parts.joined(separator: " / ")
}

// MARK: - Upstream Command

/// Reads the upstream command path from `~/.claude/claude-usage-bar/upstream-command`,
/// executes it with the original stdin data, and returns its stdout output.
func executeUpstreamCommand(inputData: Data) -> String? {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let upstreamFile = home.appendingPathComponent(".claude/claude-usage-bar/upstream-command")

    guard let commandString = try? String(contentsOf: upstreamFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !commandString.isEmpty else {
        return nil
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", commandString]

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        stdinPipe.fileHandleForWriting.write(inputData)
        stdinPipe.fileHandleForWriting.closeFile()

        // Set a timeout of 25ms
        let deadline = Date().addingTimeInterval(0.025)
        process.waitUntilExit()
        if Date() > deadline {
            // Took too long, but process already exited
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else { return nil }
        return output.trimmingCharacters(in: .newlines)
    } catch {
        fputs("collector: upstream command error: \(error.localizedDescription)\n", stderr)
        return nil
    }
}

// MARK: - Entry point

run()
