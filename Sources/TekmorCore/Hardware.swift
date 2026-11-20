import Darwin
import Foundation
import IOKit
import IOKit.serial
import Synchronization

public struct SerialDevice: Identifiable, Sendable, Equatable {
  public let id: String
  public let label: String
  public let registryID: UInt64

  public func isSamePort(as other: SerialDevice) -> Bool {
    registryID == other.registryID || id == other.id
  }
}

public struct STLinkProbe: Identifiable, Sendable, Equatable {
  public let id: UInt64
  public let label: String
  public let serialNumber: String?
}

public enum DeviceDiscovery {
  public static func serial() -> [SerialDevice] {
    scan(kIOSerialBSDServiceValue) { service in
      guard let path = property(service, kIOCalloutDeviceKey) as? String,
        path.hasPrefix("/dev/cu."),
        !path.hasSuffix("Bluetooth-Incoming-Port"), !path.hasSuffix("debug-console"),
        let id = registryID(service)
      else { return nil }
      let name = URL(filePath: path).lastPathComponent
      return SerialDevice(id: path, label: name, registryID: id)
    }.sorted { $0.id < $1.id }
  }

  public static func probes() -> [STLinkProbe] {
    let products = Set([0x3744, 0x3748, 0x374b, 0x374d, 0x374e, 0x374f, 0x3752, 0x3753, 0x3754])
    return scan("IOUSBHostDevice") { service in
      guard (property(service, "idVendor") as? NSNumber)?.intValue == 0x0483,
        let product = (property(service, "idProduct") as? NSNumber)?.intValue,
        products.contains(product),
        let id = registryID(service)
      else { return nil }
      let name = property(service, "USB Product Name") as? String ?? "ST-LINK"
      let serial = property(service, "USB Serial Number") as? String
      let usableSerial = serial.flatMap {
        $0.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) == nil ? nil : $0
      }
      return STLinkProbe(id: id, label: name, serialNumber: usableSerial)
    }
  }

  private static func scan<T>(_ service: String, map: (io_service_t) -> T?) -> [T] {
    var iterator: io_iterator_t = 0
    guard let query = IOServiceMatching(service),
      IOServiceGetMatchingServices(kIOMainPortDefault, query, &iterator) == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var items: [T] = []
    while true {
      let entry = IOIteratorNext(iterator)
      if entry == 0 { return items }
      if let item = map(entry) { items.append(item) }
      IOObjectRelease(entry)
    }
  }

  private static func property(_ service: io_service_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }

  private static func registryID(_ service: io_service_t) -> UInt64? {
    var id: UInt64 = 0
    return IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS ? id : nil
  }
}

public final class SerialConnection: Sendable {
  private let source: DispatchSourceRead
  private let shutdown = SerialShutdown()
  public let device: SerialDevice

  public init(
    device: SerialDevice, settings: SerialSettings,
    receive: @escaping ToolLog, disconnected: @escaping ToolLog
  ) throws {
    try settings.validate()
    guard DeviceDiscovery.serial().contains(device) else {
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.hardware.serialDisconnected",
            defaultValue: "Serial port disconnected. Reconnect it and select the port again.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    let fd = open(device.id, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw Self.serialError(errno, device: device) }
    do {
      try Self.setup(fd, settings: settings, device: device)
    } catch {
      Darwin.close(fd)
      throw error
    }
    self.device = device
    let queue = DispatchQueue(label: "app.tekmor.serial")
    let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source = readSource
    let decoder = SerialDecoder()
    readSource.setEventHandler { [weak self] in
      guard let self else { return }
      var buffer = [UInt8](repeating: 0, count: 4096)
      repeat {
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count > 0 {
          let text = decoder.append(buffer.prefix(count))
          if !text.isEmpty { receive(text) }
        } else if count < 0 && errno == EINTR {
          continue
        } else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
          return
        } else {
          disconnected(
            TekmorLocalization.core(
              .init(
                "core.hardware.serialPortDisconnected",
                defaultValue: "Serial port \(device.label) disconnected.",
                bundle: .atURL(Bundle.module.bundleURL))))
          self.source.cancel()
          return
        }
      } while !self.source.isCancelled
    }
    readSource.setCancelHandler { [shutdown] in
      Darwin.close(fd)
      shutdown.finish()
    }
    readSource.activate()
  }

  public func close() async {
    source.cancel()
    await shutdown.wait()
  }

  deinit { source.cancel() }

  private static func setup(_ fd: Int32, settings: SerialSettings, device: SerialDevice) throws {
    var options = termios()
    // TIOCEXCL has no data argument. It prevents another monitor from opening the port.
    guard ioctl(fd, 0x2000_740d) == 0, tcgetattr(fd, &options) == 0 else {
      throw serialError(errno, device: device)
    }
    cfmakeraw(&options)
    options.c_cflag &= ~tcflag_t(CSIZE | PARENB | PARODD | CSTOPB | HUPCL | CCTS_OFLOW | CRTS_IFLOW)
    options.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
    if settings.parity != .none {
      options.c_cflag |= tcflag_t(PARENB)
      if settings.parity == .odd { options.c_cflag |= tcflag_t(PARODD) }
    }
    if settings.stopBits == 2 { options.c_cflag |= tcflag_t(CSTOPB) }
    guard cfsetspeed(&options, speed_t(settings.baud)) == 0, tcsetattr(fd, TCSANOW, &options) == 0,
      tcflush(fd, TCIFLUSH) == 0
    else {
      throw serialError(errno, device: device)
    }
  }

  private static func serialError(_ code: Int32, device: SerialDevice) -> TekmorError {
    if code == EBUSY || code == EACCES {
      return TekmorError(
        TekmorLocalization.core(
          .init(
            "core.hardware.serialOpenFailed",
            defaultValue:
              "Cannot open serial port \(device.label). Close any program using it and check access permissions.",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
    return TekmorError(
      TekmorLocalization.core(
        .init(
          "core.hardware.serialConfigFailed",
          defaultValue:
            "Cannot configure serial port \(device.label) (\(String(cString: strerror(code)))). Check the USB connection.",
          bundle: .atURL(Bundle.module.bundleURL))))
  }
}

private final class SerialShutdown: Sendable {
  private enum State {
    case open([CheckedContinuation<Void, Never>])
    case closed
  }

  private let state = Mutex(State.open([]))

  func finish() {
    let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      guard case .open(let waiting) = state else { return [] }
      state = .closed
      return waiting
    }
    for continuation in waiting {
      continuation.resume()
    }
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      let resume = state.withLock { state in
        guard case .open(var waiting) = state else { return true }
        waiting.append(continuation)
        state = .open(waiting)
        return false
      }
      if resume { continuation.resume() }
    }
  }
}

final class SerialDecoder {
  private var bytes: [UInt8] = []

  func append(_ input: ArraySlice<UInt8>) -> String {
    bytes.append(contentsOf: input)
    let end = bytes.endIndex
    var index = end
    while index > max(0, end - 3), bytes[index - 1] & 0xc0 == 0x80 { index -= 1 }
    if index > 0 {
      let lead = bytes[index - 1]
      let width =
        if lead < 0x80 {
          1
        } else if lead & 0xe0 == 0xc0 {
          2
        } else if lead & 0xf0 == 0xe0 {
          3
        } else if lead & 0xf8 == 0xf0 {
          4
        } else {
          1
        }
      if end - (index - 1) < width {
        let text = String(decoding: bytes.prefix(index - 1), as: UTF8.self)
        bytes = Array(bytes.suffix(from: index - 1))
        return text
      }
    }
    let text = String(decoding: bytes, as: UTF8.self)
    bytes.removeAll(keepingCapacity: true)
    return text
  }
}

public enum ChipReadStatus: Equatable, Sendable {
  case reading
  case needsTool(String)
  case failed(String)
  case ready(ChipInformation)

  public var chip: ChipInformation? {
    if case .ready(let chip) = self { return chip }
    return nil
  }

  public var needsTool: Bool {
    if case .needsTool = self { return true }
    return false
  }
}

public struct ChipReadings: Sendable {
  private var entries: [UInt64: ChipReadStatus] = [:]

  public init() {}

  public subscript(id: UInt64) -> ChipReadStatus? {
    get { entries[id] }
    set { entries[id] = newValue }
  }

  public mutating func retainConnections(_ connected: Set<UInt64>) {
    if entries.keys.contains(where: { !connected.contains($0) }) {
      entries = entries.filter { connected.contains($0.key) }
    }
  }

  public func shouldRead(_ id: UInt64, toolsReady: Bool) -> Bool {
    entries[id] == nil || (entries[id]?.needsTool == true && toolsReady)
  }
}
