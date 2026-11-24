import TekmorCore

struct SerialTransmit {
  var command = SerialCommand()
  private var history: [SerialCommand] = []
  private var draft: SerialCommand?
  private var position: Int?

  mutating func edit(_ command: SerialCommand) {
    self.command = command
    position = nil
    draft = nil
  }

  mutating func recall(previous: Bool) {
    guard !history.isEmpty else { return }
    if previous {
      if position == nil { draft = command }
      let index = max(0, (position ?? history.count) - 1)
      position = index
      command = history[index]
    } else if let index = position {
      if index + 1 < history.count {
        position = index + 1
        command = history[index + 1]
      } else if let draft {
        edit(draft)
      }
    }
  }

  mutating func record(_ sent: SerialCommand) {
    history.append(sent)
    if history.count > 100 { history.removeFirst() }
    if command == sent {
      command.input = ""
    }
    position = nil
    draft = nil
  }
}
