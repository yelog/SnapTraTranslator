import Foundation
import os.log

final class MemoryMonitor {
    static let shared = MemoryMonitor()

    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "MemoryMonitor")
    private var source: DispatchSourceMemoryPressure?

    private init() {}

    func start() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let footprintMB = Self.physFootprintMB()
            let level: String
            switch source.data {
            case .warning:
                level = "WARNING"
            case .critical:
                level = "CRITICAL"
            default:
                level = "NORMAL"
            }
            self.logger.warning("Memory pressure \(level): ~\(footprintMB) MB phys_footprint")
        }

        source.resume()
        self.source = source

        let footprintMB = Self.physFootprintMB()
        logger.info("Memory monitor started. ~\(footprintMB) MB phys_footprint")
    }

    private static func physFootprintMB() -> Int {
        var info = task_vm_info()
        var size = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
            }
        }
        guard kerr == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / 1_048_576)
    }
}
