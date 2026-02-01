import Cocoa
import Foundation

actor ScreenContextDetector {
    static let shared = ScreenContextDetector()

    private init() {}

    func detectCurrentContext() async -> ScreenContext? {
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = frontApp.localizedName ?? frontApp.bundleIdentifier ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier ?? ""

        // Determine source type based on app
        let sourceType = detectSourceType(bundleId: bundleId, appName: appName)

        // Create base context
        var context = ScreenContext(
            noteId: UUID(), // Will be set when saving
            sourceType: sourceType,
            appName: appName
        )

        // Try to get additional context based on app type
        switch sourceType {
        case .browser:
            if let url = await getBrowserURL(bundleId: bundleId) {
                context.url = url
            }

        case .vscode:
            if let fileInfo = await getVSCodeFileInfo() {
                context.filePath = fileInfo.path
                context.lineStart = fileInfo.lineStart
                context.lineEnd = fileInfo.lineEnd
            }
            if let gitInfo = await getGitInfo() {
                context.gitRepo = gitInfo.repo
                context.gitBranch = gitInfo.branch
            }

        case .terminal:
            if let gitInfo = await getGitInfo() {
                context.gitRepo = gitInfo.repo
                context.gitBranch = gitInfo.branch
            }

        case .other:
            break
        }

        return context
    }

    private func detectSourceType(bundleId: String, appName: String) -> ScreenContextSourceType {
        let browserBundleIds = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "company.thebrowser.Browser" // Arc
        ]

        if browserBundleIds.contains(bundleId) {
            return .browser
        }

        let vscodeBundleIds = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.vscodium",
            "dev.zed.Zed"
        ]

        if vscodeBundleIds.contains(bundleId) {
            return .vscode
        }

        let terminalBundleIds = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "io.alacritty",
            "com.github.wez.wezterm",
            "dev.warp.Warp-Stable"
        ]

        if terminalBundleIds.contains(bundleId) {
            return .terminal
        }

        return .other
    }

    private func getBrowserURL(bundleId: String) async -> String? {
        // Use AppleScript to get the current URL
        // This requires accessibility permissions
        let script: String

        switch bundleId {
        case "com.apple.Safari":
            script = """
            tell application "Safari"
                if (count of windows) > 0 then
                    return URL of current tab of front window
                end if
            end tell
            """
        case "com.google.Chrome":
            script = """
            tell application "Google Chrome"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
        case "org.mozilla.firefox":
            script = """
            tell application "Firefox"
                if (count of windows) > 0 then
                    -- Firefox AppleScript support is limited
                    return ""
                end if
            end tell
            """
        default:
            return nil
        }

        return await runAppleScript(script)
    }

    private func getVSCodeFileInfo() async -> (path: String, lineStart: Int?, lineEnd: Int?)? {
        // VS Code doesn't have great AppleScript support
        // In a production app, we might use the VS Code extension API
        // or read from recently opened files

        // For now, try to get window title which often contains the file path
        let script = """
        tell application "System Events"
            tell process "Code"
                if (count of windows) > 0 then
                    return name of front window
                end if
            end tell
        end tell
        """

        if let windowTitle = await runAppleScript(script) {
            // Parse file path from window title
            // VS Code titles are typically: "filename — folder — Visual Studio Code"
            let parts = windowTitle.components(separatedBy: " — ")
            if let fileName = parts.first, !fileName.isEmpty {
                // This is just the filename, not full path
                // A real implementation would need more sophisticated detection
                return (path: fileName, lineStart: nil, lineEnd: nil)
            }
        }

        return nil
    }

    private func getGitInfo() async -> (repo: String, branch: String)? {
        // Try to get git info from the current working directory
        // This is a simplified version - a real implementation might
        // track the terminal's current directory or VS Code's workspace

        let branchTask = Process()
        branchTask.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        branchTask.arguments = ["branch", "--show-current"]

        let repoTask = Process()
        repoTask.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        repoTask.arguments = ["remote", "get-url", "origin"]

        let branchPipe = Pipe()
        let repoPipe = Pipe()

        branchTask.standardOutput = branchPipe
        branchTask.standardError = FileHandle.nullDevice
        repoTask.standardOutput = repoPipe
        repoTask.standardError = FileHandle.nullDevice

        do {
            try branchTask.run()
            try repoTask.run()

            branchTask.waitUntilExit()
            repoTask.waitUntilExit()

            let branchData = branchPipe.fileHandleForReading.readDataToEndOfFile()
            let repoData = repoPipe.fileHandleForReading.readDataToEndOfFile()

            let branch = String(data: branchData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var repo = String(data: repoData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Clean up repo URL to just the repo name
            if let repoName = extractRepoName(from: repo) {
                repo = repoName
            }

            if !branch.isEmpty && !repo.isEmpty {
                return (repo: repo, branch: branch)
            }
        } catch {
            // Git commands failed - probably not in a git repo
        }

        return nil
    }

    private func extractRepoName(from url: String) -> String? {
        // Extract "org/repo" from git URLs
        // Handles: git@github.com:org/repo.git
        //          https://github.com/org/repo.git
        //          https://github.com/org/repo

        var cleanUrl = url
        cleanUrl = cleanUrl.replacingOccurrences(of: ".git", with: "")

        if cleanUrl.contains("github.com") || cleanUrl.contains("gitlab.com") || cleanUrl.contains("bitbucket.org") {
            if let range = cleanUrl.range(of: "(?:github\\.com|gitlab\\.com|bitbucket\\.org)[:/](.+)", options: .regularExpression) {
                let match = cleanUrl[range]
                let repoPath = match.replacingOccurrences(of: "github.com:", with: "")
                    .replacingOccurrences(of: "github.com/", with: "")
                    .replacingOccurrences(of: "gitlab.com:", with: "")
                    .replacingOccurrences(of: "gitlab.com/", with: "")
                    .replacingOccurrences(of: "bitbucket.org:", with: "")
                    .replacingOccurrences(of: "bitbucket.org/", with: "")
                return String(repoPath)
            }
        }

        return nil
    }

    private func runAppleScript(_ source: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let script = NSAppleScript(source: source) {
                    let result = script.executeAndReturnError(&error)
                    if error == nil, let stringValue = result.stringValue {
                        continuation.resume(returning: stringValue)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }
}
