#if canImport(AppKit) && canImport(IOKit)
import AppKit
import IOKit.ps
import Synchronization
import UntitledCore
import UntitledEngine

/// Power and thermal state (3.19, V2, V3): Low Power Mode, thermal pressure, and battery.
final class PowerMonitor: PowerMonitoring, Sendable {
    private let onBattery = Mutex(false)
    private let tokens = Mutex<[any NSObjectProtocol]>([])

    init() {
        onBattery.withLock { $0 = Self.readOnBattery() }
    }

    func conditions() -> PowerConditions {
        let thermal: ThermalLevel = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
        return PowerConditions(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: thermal,
                               onBattery: onBattery.withLock { $0 })
    }

    /// Calls `changed` when Low Power Mode, thermal state or the power source changes. The power
    /// source is checked every 5 s, so work resumes well within the 10 s limit.
    func start(changed: @escaping @Sendable () -> Void) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification]
        let observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in changed() }
        }
        tokens.withLock { $0 = observers }
        Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let now = Self.readOnBattery()
                let previous = self.onBattery.withLock { value in
                    defer { value = now }
                    return value
                }
                if previous != now { changed() }
            }
        }
    }

    private static func readOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}
#endif
