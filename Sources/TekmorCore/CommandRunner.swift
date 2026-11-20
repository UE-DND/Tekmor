import Darwin
import Foundation
import Synchronization

public typealias ToolLog = @Sendable (String) -> Void

public struct CommandResult: Sendable {
  public let status: Int32
  public let output: String
  public let errorOutput: String

  public var succeeded: Bool { status == 0 }
  var diagnostic: String { output + "\n" + errorOutput }

  public func requireSuccess(_ operation: String) throws {
    guard succeeded else {
      let detail = (errorOutput.isEmpty ? output : errorOutput)
        .split(whereSeparator: \.isNewline).suffix(3).joined(separator: "\n")
      if detail.isEmpty {
        throw TekmorError(
          TekmorLocalization.core(
            .init(
              "core.command.failedNoDetail",
              defaultValue: "\(operation) failed (exit code \(status)).",
              bundle: .atURL(Bundle.module.bundleURL))))
      }
      throw TekmorError(
        TekmorLocalization.core(
          .init(
            "core.command.failedWithDetail",
            defaultValue: "\(operation) failed (exit code \(status))\n\(detail)",
            bundle: .atURL(Bundle.module.bundleURL))))
    }
  }
}

struct CommandTimeout: LocalizedError, Sendable {
  let result: CommandResult?

  var errorDescription: String? {
    TekmorLocalization.core(
      .init(
        "core.command.timeout",
        defaultValue: "Operation timed out. Check the tool and device connection, then try again.",
        bundle: .atURL(Bundle.module.bundleURL)))
  }
}

public struct CommandRunner: Sendable {
  private enum TimedResult {
    case finished(CommandResult)
    case deadlineReached
  }

  public init() {}

  public func run(
    _ executable: URL, _ arguments: [String] = [], directory: URL? = nil,
    environment: [String: String] = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"],
    log: @escaping ToolLog = { _ in }
  ) async throws -> CommandResult {
    let result = try await execute(executable, arguments, directory, environment, log)
    try Task.checkCancellation()
    return result
  }

  private func execute(
    _ executable: URL, _ arguments: [String], _ directory: URL?,
    _ environment: [String: String], _ log: @escaping ToolLog
  ) async throws -> CommandResult {
    let child = ChildProcess()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(
            with: Result {
              try child.call(executable, arguments, directory, environment, log)
            })
        }
      }
    } onCancel: {
      child.cancel()
    }
  }

  public func run(
    _ executable: URL, _ arguments: [String], directory: URL? = nil,
    environment: [String: String] = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"],
    timeout: Duration, log: @escaping ToolLog = { _ in }
  ) async throws -> CommandResult {
    try await withThrowingTaskGroup(of: TimedResult.self) { group in
      group.addTask {
        try await .finished(execute(executable, arguments, directory, environment, log))
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        return .deadlineReached
      }
      defer { group.cancelAll() }
      switch try await group.next() {
      case .finished(let result):
        try Task.checkCancellation()
        return result
      case .deadlineReached:
        group.cancelAll()
        // Wait for termination and pipe drainage before using any partial diagnostics.
        let completion = try? await group.next()
        try Task.checkCancellation()
        if case .finished(let result) = completion { throw CommandTimeout(result: result) }
        throw CommandTimeout(result: nil)
      case nil:
        throw CancellationError()
      }
    }
  }
}

private final class ChildProcess: Sendable {
  private struct State {
    var pid: pid_t?
    var cancelled = false
  }

  private let state = Mutex(State())

  func cancel() {
    state.withLock {
      guard !$0.cancelled else { return }
      $0.cancelled = true
      if let pid = $0.pid { terminateGroup(pid) }
    }
  }

  private func terminateGroup(_ pid: pid_t) {
    kill(-pid, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(1)) { [self] in
      state.withLock {
        if $0.pid == pid { kill(-pid, SIGKILL) }
      }
    }
  }

  func call(
    _ executable: URL, _ arguments: [String], _ directory: URL?,
    _ environment: [String: String], _ log: @escaping ToolLog
  ) throws -> CommandResult {
    let stdout = try makePipe()
    let stderr: [Int32]
    do {
      stderr = try makePipe()
    } catch {
      for descriptor in stdout {
        close(descriptor)
      }
      throw error
    }
    var parentWriters = [stdout[1], stderr[1]]
    defer {
      for descriptor in parentWriters + [stdout[0], stderr[0]] {
        close(descriptor)
      }
    }

    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    try check(posix_spawn_file_actions_init(&actions))
    defer { posix_spawn_file_actions_destroy(&actions) }
    try check(posix_spawnattr_init(&attributes))
    defer { posix_spawnattr_destroy(&attributes) }

    if let directory {
      try setWorkingDirectory(directory, actions: &actions)
    }
    try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
    try check(posix_spawn_file_actions_adddup2(&actions, stdout[1], STDOUT_FILENO))
    try check(posix_spawn_file_actions_adddup2(&actions, stderr[1], STDERR_FILENO))
    try check(
      posix_spawnattr_setflags(
        &attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
    try check(posix_spawnattr_setpgroup(&attributes, 0))

    var argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
    var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
      for argument in argv {
        free(argument)
      }
      for entry in envp {
        free(entry)
      }
    }

    let childPID: pid_t = try state.withLock {
      if $0.cancelled { throw CancellationError() }
      var childPID: pid_t = 0
      try check(posix_spawn(&childPID, executable.path, &actions, &attributes, &argv, &envp))
      $0.pid = childPID
      return childPID
    }
    defer { state.withLock { $0.pid = nil } }
    for descriptor in parentWriters {
      close(descriptor)
    }
    parentWriters.removeAll()

    let readers = DispatchGroup()
    let output = Capture()
    let errors = Capture()
    for (fd, capture) in [(stdout[0], output), (stderr[0], errors)] {
      readers.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        capture.read(from: fd, log: log)
        readers.leave()
      }
    }
    var status: Int32 = 0
    while waitpid(childPID, &status, 0) < 0 {
      if errno == EINTR { continue }
      let failure = errno
      cancel()
      readers.wait()
      try check(failure)
    }
    readers.wait()
    let signal = status & 0x7f
    return CommandResult(
      status: signal == 0 ? (status >> 8) & 0xff : 128 + signal,
      output: output.text, errorOutput: errors.text
    )
  }

  private func setWorkingDirectory(_ directory: URL, actions: inout posix_spawn_file_actions_t?)
    throws
  {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        try check(posix_spawn_file_actions_addchdir(&actions, directory.path))
      } else {
        try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
      }
    #else
      try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
    #endif
  }

  private func makePipe() throws -> [Int32] {
    var fds = [Int32](repeating: -1, count: 2)
    if pipe(&fds) != 0 { try check(errno) }
    for fd in fds {
      if fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 {
        let failure = errno
        for descriptor in fds {
          close(descriptor)
        }
        try check(failure)
      }
    }
    return fds
  }

  private func check(_ result: Int32) throws {
    if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
  }
}

private final class Capture: Sendable {
  private let captured = Mutex("")
  var text: String { captured.withLock { $0 } }

  func read(from fd: Int32, log: ToolLog) {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    var pending = Data()
    let captureLimit = 4 * 1024 * 1024
    while true {
      let count = Darwin.read(fd, &buffer, buffer.count)
      if count < 0 && errno == EINTR { continue }
      if count <= 0 { break }
      data.append(contentsOf: buffer.prefix(count))
      if data.count > captureLimit { data.removeFirst(data.count - captureLimit) }
      pending.append(contentsOf: buffer.prefix(count))
      if let end = pending.lastIndex(where: { $0 == 10 || $0 == 13 }) {
        log(String(decoding: pending[...end], as: UTF8.self))
        pending.removeSubrange(...end)
      } else if pending.count > 16384 {
        log(String(decoding: pending, as: UTF8.self))
        pending.removeAll(keepingCapacity: true)
      }
    }
    if !pending.isEmpty { log(String(decoding: pending, as: UTF8.self)) }
    let text = String(decoding: data, as: UTF8.self)
    captured.withLock { $0 = text }
  }
}
