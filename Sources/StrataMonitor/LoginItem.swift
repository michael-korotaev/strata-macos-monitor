import Foundation
import ServiceManagement

/// Автозапуск приложения при входе в систему.
///
/// Регистрация идёт через штатный API ServiceManagement: система запускает
/// бандл приложения через LaunchServices, поэтому в Launchpad остаётся
/// ровно один значок. Самодельный LaunchAgent (как в прошлых версиях) запускал
/// бинарник напрямую, и macOS регистрировала его как второе приложение —
/// отсюда были два значка и в меню-баре, и в Launchpad.
enum LoginItem {
    /// Тумблер включён — приложение стартует при входе в систему.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true`, если macOS ждёт подтверждения пользователя в «Системных настройках».
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        removeLegacyAgent()
        if enabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    // MARK: - Миграция со старого LaunchAgent

    static let legacyLabel = "io.github.michael-korotaev.strata-monitor"
    static let legacyPlistName = "io.github.michael-korotaev.strata-monitor.plist"

    static var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(legacyPlistName)
    }

    /// Убирает агента, написанного прошлыми версиями приложения. Файл
    /// удаляется всегда, а выгрузка из launchd — только если текущий процесс
    /// не принадлежит этому агенту (иначе выгрузка убила бы само приложение).
    static func removeLegacyAgent(currentPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        let url = legacyAgentURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
        guard legacyAgentPID() != currentPID else { return }
        try? runLaunchctl(["bootout", "gui/\(getuid())/\(legacyLabel)"])
    }

    /// PID процесса, запущенного старым агентом (nil — агент не загружен).
    static func legacyAgentPID() -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(legacyLabel)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let line = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .first(where: { $0.contains("pid =") })
        else { return nil }
        return Int32(line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
    }

    private static func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "StrataMonitor", code: Int(process.terminationStatus))
        }
    }
}
