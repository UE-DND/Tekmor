import Foundation
import Observation

@MainActor @Observable
final class ProjectTerminalSessions {
  private var sessions: [URL?: ProjectTerminal] = [:]
  private(set) var focusRequest = 0

  func session(for project: URL?) -> ProjectTerminal? { sessions[project] }

  func open(for project: URL?, directory: URL, restart: Bool) {
    let session = sessions[project] ?? ProjectTerminal(directory: directory)
    if sessions[project] == nil { sessions[project] = session }
    if session.state == .idle || restart { session.prepare() }
    requestFocus()
  }

  func requestFocus() { focusRequest += 1 }

  func releaseFocus(for project: URL?) {
    guard let session = sessions[project], session.hasKeyboardFocus else { return }
    session.terminalView?.window?.makeFirstResponder(nil)
  }

  func remove(_ project: URL) {
    sessions.removeValue(forKey: project)?.stop()
  }

  func stopAll() -> Bool {
    let anyOpen = sessions.values.contains { $0.state.isOpen }
    for session in sessions.values { session.stop(escalationDelay: 0.05) }
    sessions.removeAll()
    return anyOpen
  }
}
