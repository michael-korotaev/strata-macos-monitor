import AppKit
import Darwin
import Foundation
import StrataMonitorKit

// Menu bar app: no windows, just an NSStatusItem and an NSPopover.
// Started from main.swift instead of the SwiftUI app lifecycle, so the behaviour does not depend
// on an LSUIElement app having to activate itself on click.

// Utility mode: print one metrics snapshot to stdout (decoding check, diagnostics).
// The address can be overridden: STRATA_ENDPOINT=http://host:12387 ./StrataMonitor --dump
// The endpoint is found automatically, both Strata installations are supported.
if CommandLine.arguments.contains("--dump") {
    let endpointString = ProcessInfo.processInfo.environment["STRATA_ENDPOINT"]
        ?? MonitorModel.defaultEndpoint
    guard let endpoint = URL(string: endpointString) else {
        FileHandle.standardError.write(Data("Invalid address: \(endpointString)\n".utf8))
        exit(2)
    }
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        defer { semaphore.signal() }
        let client = MetricsClient(endpoint: endpoint, flavor: .automatic)
        do {
            let payload = try await client.fetch()
            print("endpoint:       \(client.activeEndpoint.absoluteString)")
            let installation = client.usesEventStream || payload.isModern
                ? "desktop application"
                : "source build"
            print("installation:   \(installation)")
            print("model:          \(payload.model ?? "-")")
            print("engine:         \(payload.engineVersion ?? "-")")
            print("live state:     \(payload.liveState)  phase: \(payload.livePhase ?? "-")")
            print("live tok/s:     \(payload.liveTPS.map { String(format: "%.1f", $0) } ?? "-")"
                  + "  mean: \(payload.liveTPSMean.map { String(format: "%.1f", $0) } ?? "-")")
            print("hardware tok/s: \(payload.hardwareTPS.map { String(format: "%.1f", $0) } ?? "-")")
            print("gpu:            \(payload.gpuName ?? "-") util \(payload.gpuUtil.map { String(format: "%.0f%%", $0) } ?? "-")"
                  + " vram \(Format.gib(payload.gpuMemUsed))/\(Format.gib(payload.gpuMemTotal)) GiB"
                  + " temp \(payload.gpuTemp.map { String(format: "%.0f°C", $0) } ?? "-")"
                  + " power \(payload.gpuPower.map { String(format: "%.0fW", $0) } ?? "-")")
            print("cpu:            \(payload.cpuName ?? "-") \(payload.cpuUsage.map { String(format: "%.0f%%", $0) } ?? "-")"
                  + "  ram \(Format.gib(payload.ramUsed))/\(Format.gib(payload.ramTotal)) GiB")
            print("totals:         requests \(payload.totalRequests ?? 0)"
                  + " prompt \(Format.tokens(payload.totalPromptTokens))"
                  + " out \(Format.tokens(payload.totalOutputTokens))")
            print("cache:          \(payload.cacheParked ?? 0)/\(payload.cacheSlots ?? 0) slots,"
                  + " reuse \(payload.cacheRequestsReused ?? 0)/\(payload.cacheRequests ?? 0)")
            print("history tok/s:  \(payload.historyTPS.compactMap { $0 }.count) samples,"
                  + " last \(payload.historyTPS.compactMap { $0 }.last.map { String(format: "%.1f", $0) } ?? "-")")
            let rows = payload.requests
            if let info = try? await client.fetchStatic() {
                print("static:         gpu \(info.gpuName ?? "-")"
                      + "  cpu \(info.cpuName ?? "-")"
                      + "  cores \(info.cpuCores ?? 0)/\(info.cpuThreads ?? 0)"
                      + "  backend \(info.backend ?? "-")")
                print("model catalogue: \(info.modelName ?? "-")"
                      + "  quant \(info.modelQuant ?? "-")"
                      + "  ctx \(info.modelContextMax ?? 0)"
                      + "  experts \(info.modelExperts ?? 0)"
                      + "  kv \(info.modelKVModes.joined(separator: "/"))")
            }
            print("requests:       \(rows.count)")
            for row in rows.prefix(3) {
                print("   \(Format.clock(row.time))  \(Format.number(row.durationS, 1))s"
                      + "  \(Format.number(row.decodeTPS, 0)) tok/s"
                      + "  ttft \(Format.number(row.firstTokenS, 2))s"
                      + "  out \(row.outputTokens ?? 0)"
                      + "  draft \(row.draftAcceptance.map { String(format: "%.0f%%", $0 * 100) } ?? "-")")
            }
        } catch {
            print("error: \(MonitorModel.describe(error, language: .english))")
        }
    }
    semaphore.wait()
    exit(0)
}

/// Ровно один экземпляр приложения: агент автозапуска и ручной запуск
/// не должны давать два значка в меню-баре. Блокировка держится на файле,
/// поэтому после падения приложения она снимается сама.
///
/// Файл лежит в Application Support, а не в Caches: систему очистки кэшей
/// нельзя допускать удалять лок-файл, пока приложение запущено, иначе
/// второй экземпляр создал бы новый файл и прошёл бы проверку.
func claimSingleInstance() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("io.github.michael-korotaev.strata-monitor", isDirectory: true)
    try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let lockPath = support.appendingPathComponent("instance.lock").path
    let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o644)
    guard descriptor >= 0 else { return }          // не смогли создать — не блокируем
    if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
        close(descriptor)
        exit(0)                                    // другой экземпляр уже работает
    }
    // дескриптор намеренно не закрываем: блокировка живёт вместе с процессом
}

// Diagnostic mode: manage the "launch at login" registration without the UI.
//   StrataMonitor --login-item on | off | status
if let index = CommandLine.arguments.firstIndex(of: "--login-item") {
    let argument = CommandLine.arguments.count > index + 1
        ? CommandLine.arguments[index + 1].lowercased()
        : "status"
    do {
        switch argument {
        case "on", "enable":
            try LoginItem.setEnabled(true)
        case "off", "disable":
            try LoginItem.setEnabled(false)
        case "status":
            break
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(argument)\n".utf8))
            exit(2)
        }
        print("login item: \(LoginItem.isEnabled ? "enabled" : "disabled")"
              + (LoginItem.requiresApproval ? " (requires approval in System Settings)" : ""))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

claimSingleInstance()

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
AppDelegate.shared = delegate
application.delegate = delegate
application.setActivationPolicy(.accessory)
MainMenu.install()
application.run()
