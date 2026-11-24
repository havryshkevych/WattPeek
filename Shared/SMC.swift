import Foundation
import IOKit

/// Чтение float-датчиков питания из AppleSMC (обновляются ~раз в секунду; root не нужен).
final class SMC {
    private var conn: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(conn) }

    // Раскладка SMCKeyData (80 байт): key@0, dataSize@28, dataType@32, result@40, data8@42, bytes@48
    private func call(_ input: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 80)
        var size = out.count
        let kr = IOConnectCallStructMethod(conn, 2, input, input.count, &out, &size)
        return kr == kIOReturnSuccess && out[40] == 0 ? out : nil
    }

    /// Значение ключа; поддержаны типы, которыми SMC отдаёт питание и батарею.
    func read(_ key: String) -> Double? {
        var req = [UInt8](repeating: 0, count: 80)
        req.replaceSubrange(0..<4, with: key.utf8.reversed())
        req[42] = 9 // информация о ключе
        guard let info = call(req) else { return nil }
        req.replaceSubrange(28..<32, with: info[28..<32])
        req[42] = 5 // чтение значения
        guard let out = call(req) else { return nil }
        return out.withUnsafeBytes { p -> Double? in
            switch String(decoding: info[32..<36].reversed(), as: UTF8.self) {
            case "flt ":
                let v = p.loadUnaligned(fromByteOffset: 48, as: Float.self)
                return v.isFinite ? Double(v) : nil
            case "si16": return Double(p.loadUnaligned(fromByteOffset: 48, as: Int16.self))
            case "ui16": return Double(p.loadUnaligned(fromByteOffset: 48, as: UInt16.self))
            default: return nil
            }
        }
    }
}
