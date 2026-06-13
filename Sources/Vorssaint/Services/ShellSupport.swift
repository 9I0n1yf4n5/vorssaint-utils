import AppKit

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Runs a command with administrator privileges (system password prompt).
enum AdminShell {
    static func runSync(_ command: String, prompt: String) -> Bool {
        let source = "do shell script \"\(command)\" with administrator privileges with prompt \"\(prompt)\""
        return Shell.run("/usr/bin/osascript", ["-e", source]).status == 0
    }

    static func run(_ command: String, prompt: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            completion(runSync(command, prompt: prompt))
        }
    }
}

/// NOPASSWD rule restricted to `pmset disablesleep 0/1`, so closed-lid mode can
/// toggle without asking for the administrator password every time.
/// The password is asked once, when installing (or removing) the rule.
enum Sudoers {
    static let rulePath = "/etc/sudoers.d/vorssaint-clamshell"
    // Rule files written under earlier names; removed whenever the rule is
    // (re)installed or removed, so the closed-lid permission migrates without an
    // extra password prompt.
    private static let legacyRulePaths = [
        "/etc/sudoers.d/vorssaint-utils-clamshell",
        "/etc/sudoers.d/vorss-clamshell",
    ]

    private static var safeUser: String? {
        let user = NSUserName()
        let valid = user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        return valid ? user : nil
    }

    /// `sudo -n -l <cmd>` exits 0 only when the command can run without a password.
    static func isConfigured() -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "disablesleep", "1"]).status == 0
    }

    static func install(completion: @escaping (Bool) -> Void) {
        guard let user = safeUser else {
            completion(false)
            return
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        // Clear any earlier-named rule first, then write and validate the new one
        // (a failed check rolls back). Same password prompt either way.
        let legacy = legacyRulePaths.joined(separator: " ")
        let command = "rm -f \(legacy); echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"
        AdminShell.run(command, prompt: L10n.shared.s.adminPromptSudoersInstall) { ok in
            completion(ok && isConfigured())
        }
    }

    static func remove(completion: @escaping (Bool) -> Void) {
        // Also removes the rules left behind by earlier app names.
        let all = ([rulePath] + legacyRulePaths).joined(separator: " ")
        AdminShell.run("rm -f \(all)",
                       prompt: L10n.shared.s.adminPromptSudoersRemove) { ok in
            completion(ok)
        }
    }

    /// Toggles sleep through the password-free path. Fails silently
    /// (returns false) when the rule is not installed.
    @discardableResult
    static func pmsetDisableSleep(_ on: Bool) -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]).status == 0
    }
}
