import Foundation

public struct FlashProgress: Equatable, Sendable {
  public enum Write: Equatable, Sendable { case notStarted, unknown, verified }
  public enum Reset: Equatable, Sendable { case notAttempted, unconfirmed, confirmed }

  public let write: Write
  public let reset: Reset

  init(write: Write, reset: Reset = .notAttempted) {
    self.write = write
    self.reset = reset
  }
}

public struct FlashFailure: LocalizedError, Sendable {
  public let errorDescription: String?
  public let progress: FlashProgress

  init(_ description: String, progress: FlashProgress) {
    errorDescription = description
    self.progress = progress
  }

  static func timedOut(_ progress: FlashProgress) -> Self {
    let message: String
    switch (progress.write, progress.reset) {
    case (.verified, .confirmed):
      message = TekmorLocalization.core(
        .init(
          "core.flash.timeoutResetConfirmed",
          defaultValue:
            "The tool timed out after confirming firmware verification and reset. See the log for details.",
          bundle: .atURL(Bundle.module.bundleURL)))
    case (.verified, .unconfirmed):
      message = TekmorLocalization.core(
        .init(
          "core.flash.timeoutResetUnconfirmed",
          defaultValue:
            "The tool timed out. The firmware was verified, but reset was not confirmed.",
          bundle: .atURL(Bundle.module.bundleURL)))
    case (.verified, .notAttempted):
      message = TekmorLocalization.core(
        .init(
          "core.flash.timeoutVerified",
          defaultValue:
            "The tool timed out after verifying the firmware. The reset step was not started.",
          bundle: .atURL(Bundle.module.bundleURL)))
    case (.notStarted, _):
      message = TekmorLocalization.core(
        .init(
          "core.flash.timeoutBeforeWrite",
          defaultValue:
            "The tool timed out before writing firmware. Check the target and see the log for details.",
          bundle: .atURL(Bundle.module.bundleURL)))
    case (.unknown, _):
      message = TekmorLocalization.core(
        .init(
          "core.flash.timeoutWriteUnknown",
          defaultValue:
            "Flashing timed out. The firmware write state is unknown. Check the target and see the log for details.",
          bundle: .atURL(Bundle.module.bundleURL)))
    }
    return Self(message, progress: progress)
  }
}

enum FlashDeadline {
  static func programming(_ method: FlashMethod, _ bytes: Int) -> Duration {
    switch method {
    case .uart: .seconds(max(180, 90 + 2 * ((bytes + 4095) / 4096)))
    case .swd: .seconds(180 + (bytes + 65535) / 65536)
    }
  }
}
