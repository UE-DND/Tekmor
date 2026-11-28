import Foundation

public enum ConsolePane: String, Codable, CaseIterable, Identifiable, Sendable {
  case buildLog
  case serial
  case terminal

  public var id: Self { self }
}

public struct WorkbenchLayout: Codable, Equatable {
  public enum Axis: String, Codable {
    case horizontal, vertical
  }

  public enum Edge: String, CaseIterable, Sendable {
    case left, right, top, bottom

    var axis: Axis {
      switch self {
      case .left, .right: .horizontal
      case .top, .bottom: .vertical
      }
    }

    var insertsFirst: Bool { self == .left || self == .top }
  }

  public enum Destination {
    case tabs(UUID, before: ConsolePane?)
    case split(UUID, edge: Edge)

    var groupID: UUID {
      switch self {
      case .tabs(let id, _), .split(let id, _): id
      }
    }
  }

  public struct Group: Codable, Equatable, Identifiable {
    public fileprivate(set) var id = UUID()
    public fileprivate(set) var tabs: [ConsolePane]
    public fileprivate(set) var selected: ConsolePane
  }

  public struct Split: Codable, Equatable, Identifiable {
    public fileprivate(set) var id = UUID()
    public fileprivate(set) var axis: Axis
    public fileprivate(set) var fraction: Double = 0.5
    public fileprivate(set) var first: Node
    public fileprivate(set) var second: Node
  }

  public indirect enum Node: Codable, Equatable, Identifiable {
    case group(Group)
    case split(Split)

    public var id: UUID {
      switch self {
      case .group(let group): group.id
      case .split(let split): split.id
      }
    }

    public var groups: [Group] {
      switch self {
      case .group(let group): [group]
      case .split(let split): split.first.groups + split.second.groups
      }
    }

    public var visiblePanes: [ConsolePane] { groups.map(\.selected) }

    public func minimumSize(dividerThickness: CGFloat = 1) -> CGSize {
      switch self {
      case .group:
        return CGSize(width: 110, height: 96)
      case .split(let split):
        let first = split.first.minimumSize(dividerThickness: dividerThickness)
        let second = split.second.minimumSize(dividerThickness: dividerThickness)
        switch split.axis {
        case .horizontal:
          return CGSize(
            width: first.width + dividerThickness + second.width,
            height: max(first.height, second.height))
        case .vertical:
          return CGSize(
            width: max(first.width, second.width),
            height: first.height + dividerThickness + second.height)
        }
      }
    }

    func replacingGroup(_ id: UUID, with replacement: (Group) -> Node) -> Node {
      switch self {
      case .group(let group):
        return group.id == id ? replacement(group) : self
      case .split(var split):
        split.first = split.first.replacingGroup(id, with: replacement)
        split.second = split.second.replacingGroup(id, with: replacement)
        return .split(split)
      }
    }

    func removing(_ pane: ConsolePane) -> Node? {
      switch self {
      case .group(var group):
        guard let index = group.tabs.firstIndex(of: pane) else { return self }
        group.tabs.remove(at: index)
        guard !group.tabs.isEmpty else { return nil }
        if group.selected == pane {
          group.selected = group.tabs[min(index, group.tabs.count - 1)]
        }
        return .group(group)
      case .split(var split):
        guard let first = split.first.removing(pane) else { return split.second }
        guard let second = split.second.removing(pane) else { return first }
        split.first = first
        split.second = second
        return .split(split)
      }
    }

    func settingFraction(_ fraction: Double, for id: UUID) -> Node {
      guard case .split(var split) = self else { return self }
      if split.id == id {
        split.fraction = fraction
      } else {
        split.first = split.first.settingFraction(fraction, for: id)
        split.second = split.second.settingFraction(fraction, for: id)
      }
      return .split(split)
    }

    func collectIDs(into ids: inout Set<UUID>) -> Bool {
      guard ids.insert(id).inserted else { return false }
      switch self {
      case .group(let group):
        return group.tabs.contains(group.selected)
      case .split(let split):
        return (0.0...1.0).contains(split.fraction)
          && split.first.collectIDs(into: &ids)
          && split.second.collectIDs(into: &ids)
      }
    }
  }

  private(set) var version = 1
  public private(set) var root: Node = .group(
    Group(tabs: ConsolePane.allCases, selected: .buildLog))
  public private(set) var activePane: ConsolePane = .buildLog

  public init() {}

  public var isSplit: Bool {
    if case .split = root { return true }
    return false
  }

  public var isValid: Bool {
    let tabs = root.groups.flatMap(\.tabs)
    var ids: Set<UUID> = []
    return version == 1
      && tabs.count == ConsolePane.allCases.count
      && Set(tabs) == Set(ConsolePane.allCases)
      && root.visiblePanes.contains(activePane)
      && root.collectIDs(into: &ids)
  }

  public mutating func select(_ pane: ConsolePane, activate: Bool = true) {
    guard let group = group(containing: pane) else { return }
    if group.selected != pane {
      root = root.replacingGroup(group.id) { group in
        var group = group
        group.selected = pane
        return .group(group)
      }
    }
    if activate || !root.visiblePanes.contains(activePane) { activePane = pane }
  }

  public func group(containing pane: ConsolePane) -> Group? {
    root.groups.first { $0.tabs.contains(pane) }
  }

  public func canMove(_ pane: ConsolePane, to destination: Destination) -> Bool {
    guard let source = group(containing: pane),
      let target = root.groups.first(where: { $0.id == destination.groupID })
    else { return false }
    switch destination {
    case .split:
      return source.id != target.id || source.tabs.count > 1
    case .tabs(_, let before):
      return before.map { $0 != pane && target.tabs.contains($0) } ?? true
    }
  }

  @discardableResult
  public mutating func move(_ pane: ConsolePane, to destination: Destination) -> Bool {
    guard canMove(pane, to: destination) else { return false }

    if case .tabs(let id, let before) = destination, group(containing: pane)?.id == id {
      root = root.replacingGroup(id) { group in
        var group = group
        group.tabs.removeAll { $0 == pane }
        group.tabs.insert(
          pane, at: before.flatMap { group.tabs.firstIndex(of: $0) } ?? group.tabs.endIndex)
        group.selected = pane
        return .group(group)
      }
    } else {
      guard let remaining = root.removing(pane) else { return false }
      root = remaining.replacingGroup(destination.groupID) { group in
        switch destination {
        case .tabs(_, let before):
          var group = group
          group.tabs.insert(
            pane, at: before.flatMap { group.tabs.firstIndex(of: $0) } ?? group.tabs.endIndex)
          group.selected = pane
          return .group(group)
        case .split(_, let edge):
          let newGroup = Node.group(Group(tabs: [pane], selected: pane))
          return .split(
            Split(
              axis: edge.axis,
              first: edge.insertsFirst ? newGroup : .group(group),
              second: edge.insertsFirst ? .group(group) : newGroup
            ))
        }
      }
    }
    activePane = pane
    return true
  }

  public mutating func toggleSplit() {
    if isSplit {
      merge()
    } else if let serialGroup = group(containing: .serial) {
      let pane = activePane
      move(.serial, to: .split(serialGroup.id, edge: .bottom))
      select(.buildLog, activate: false)
      activePane = pane == .terminal ? .buildLog : pane
    }
  }

  public mutating func merge() {
    guard isSplit, let group = group(containing: activePane) else { return }
    root = .group(Group(id: group.id, tabs: root.groups.flatMap(\.tabs), selected: activePane))
  }

  public mutating func resize(_ splitID: UUID, fraction: Double) {
    guard fraction.isFinite else { return }
    root = root.settingFraction(min(max(fraction, 0), 1), for: splitID)
  }
}
