import CoreGraphics
import Foundation
import TekmorWorkbench
import Testing

@Suite("Workbench layout")
struct WorkbenchLayoutTests {
  @Test(arguments: WorkbenchLayout.Edge.allCases)
  func splitsAtEveryEdge(_ edge: WorkbenchLayout.Edge) {
    var layout = WorkbenchLayout()
    let original = layout.root.id

    #expect(layout.move(.serial, to: .split(original, edge: edge)) == true)
    guard case .split(let split) = layout.root else {
      Issue.record("Expected a split")
      return
    }

    let horizontal = edge == .left || edge == .right
    let serialFirst = edge == .left || edge == .top
    #expect(split.axis == (horizontal ? .horizontal : .vertical))
    #expect(split.first.visiblePanes == [serialFirst ? .serial : .buildLog])
    #expect(split.second.visiblePanes == [serialFirst ? .buildLog : .serial])
    #expect(layout.activePane == .serial)
    #expect(layout.isValid)
  }

  @Test func calculatesNestedMinimumSizes() throws {
    var layout = WorkbenchLayout()
    let original = layout.root.id
    #expect(layout.root.minimumSize() == CGSize(width: 110, height: 96))
    layout.move(.serial, to: .split(original, edge: .right))
    #expect(layout.root.minimumSize() == CGSize(width: 221, height: 96))
    layout.move(.terminal, to: .split(original, edge: .bottom))
    #expect(layout.root.minimumSize() == CGSize(width: 221, height: 193))
    let serialGroup = try #require(layout.group(containing: .serial)?.id)
    layout.move(.terminal, to: .split(serialGroup, edge: .right))
    #expect(layout.root.minimumSize() == CGSize(width: 332, height: 96))
    #expect(layout.root.minimumSize(dividerThickness: 2) == CGSize(width: 334, height: 96))
  }

  @Test func movesTabsBetweenGroupsAndCollapsesEmptyBranches() throws {
    var layout = WorkbenchLayout()
    let logGroup = layout.root.id
    #expect(layout.move(.terminal, to: .tabs(logGroup, before: .buildLog)) == true)
    #expect(layout.root.groups.first?.tabs == [.terminal, .buildLog, .serial])

    #expect(layout.move(.serial, to: .split(logGroup, edge: .right)) == true)
    #expect(layout.move(.terminal, to: .split(logGroup, edge: .bottom)) == true)
    #expect(layout.root.visiblePanes == [.buildLog, .terminal, .serial])
    #expect(layout.isValid)

    let serialGroup = try #require(layout.group(containing: .serial)?.id)
    #expect(layout.move(.terminal, to: .tabs(serialGroup, before: .serial)) == true)
    #expect(layout.root.groups.map(\.tabs) == [[.buildLog], [.terminal, .serial]])
    #expect(layout.root.visiblePanes == [.buildLog, .terminal])
    #expect(layout.isValid)

    #expect(layout.move(.buildLog, to: .tabs(serialGroup, before: nil)) == true)
    #expect(!layout.isSplit)
    #expect(layout.root.id == serialGroup)
    #expect(layout.root.groups.first?.tabs == [.terminal, .serial, .buildLog])
    #expect(layout.activePane == .buildLog)
    #expect(layout.isValid)
  }

  @Test(arguments: WorkbenchLayout.Edge.allCases, WorkbenchLayout.Edge.allCases)
  func supportsEveryThreePaneCombination(
    _ firstEdge: WorkbenchLayout.Edge, _ secondEdge: WorkbenchLayout.Edge
  ) throws {
    var layout = WorkbenchLayout()
    let logGroup = layout.root.id
    #expect(layout.move(.serial, to: .split(logGroup, edge: firstEdge)) == true)
    #expect(layout.move(.terminal, to: .split(logGroup, edge: secondEdge)) == true)
    #expect(layout.root.groups.count == 3)
    #expect(Set(layout.root.visiblePanes) == Set(ConsolePane.allCases))
    #expect(layout.activePane == .terminal)
    #expect(layout.isValid)

    let serialGroup = try #require(layout.group(containing: .serial)?.id)
    #expect(layout.move(.terminal, to: .split(serialGroup, edge: secondEdge)) == true)
    #expect(layout.root.groups.count == 3)
    #expect(Set(layout.root.visiblePanes) == Set(ConsolePane.allCases))
    #expect(layout.isValid)

    #expect(layout.move(.terminal, to: .tabs(serialGroup, before: .serial)) == true)
    #expect(layout.root.groups.count == 2)
    #expect(layout.group(containing: .terminal)?.tabs == [.terminal, .serial])
    #expect(layout.root.visiblePanes.contains(.terminal))
    #expect(layout.isValid)

    #expect(layout.move(.serial, to: .tabs(serialGroup, before: .terminal)) == true)
    #expect(layout.group(containing: .serial)?.tabs == [.serial, .terminal])
    #expect(layout.activePane == .serial)
    #expect(layout.isValid)
  }

  @Test func rejectsInvalidMoves() throws {
    var layout = WorkbenchLayout()
    let logGroup = layout.root.id
    #expect(layout.move(.serial, to: .split(logGroup, edge: .right)) == true)
    let serialGroup = try #require(layout.group(containing: .serial)?.id)
    let original = layout

    #expect(layout.move(.serial, to: .split(serialGroup, edge: .bottom)) == false)
    #expect(layout.move(.serial, to: .tabs(logGroup, before: .serial)) == false)
    #expect(layout.move(.serial, to: .tabs(UUID(), before: nil)) == false)
    #expect(layout.move(.serial, to: .split(UUID(), edge: .left)) == false)
    #expect(layout.move(.buildLog, to: .tabs(logGroup, before: .buildLog)) == false)
    #expect(layout == original)
  }

  @Test func mergesAndRestoresTabOrder() throws {
    var layout = WorkbenchLayout()
    let logGroup = layout.root.id
    #expect(layout.move(.serial, to: .split(logGroup, edge: .right)) == true)
    let serialGroup = try #require(layout.group(containing: .serial)?.id)
    #expect(layout.move(.terminal, to: .tabs(serialGroup, before: .serial)) == true)
    let expectedOrder = layout.root.groups.flatMap(\.tabs)

    let splitData = try JSONEncoder().encode(layout)
    let restoredSplit = try JSONDecoder().decode(WorkbenchLayout.self, from: splitData)
    #expect(restoredSplit == layout)
    #expect(restoredSplit.group(containing: .terminal)?.tabs == [.terminal, .serial])

    layout.merge()
    #expect(!layout.isSplit)
    #expect(layout.root.id == serialGroup)
    #expect(layout.root.groups.first?.tabs == expectedOrder)
    #expect(layout.root.visiblePanes == [.terminal])
    #expect(layout.activePane == .terminal)
    #expect(layout.isValid)

    let mergedData = try JSONEncoder().encode(layout)
    let restoredMerge = try JSONDecoder().decode(WorkbenchLayout.self, from: mergedData)
    #expect(restoredMerge == layout)
    let merged = layout
    layout.merge()
    #expect(layout == merged)
  }

  @Test func preservesRatiosSelectionsAndOrderOnRestore() throws {
    var layout = WorkbenchLayout()
    let logGroup = layout.root.id
    #expect(layout.move(.terminal, to: .split(logGroup, edge: .left)) == true)
    let outer = layout.root.id
    #expect(layout.move(.serial, to: .split(logGroup, edge: .top)) == true)
    guard case .split(let split) = layout.root else {
      Issue.record("Expected a split")
      return
    }

    layout.resize(outer, fraction: 0.31)
    layout.resize(split.second.id, fraction: 0.62)
    layout.resize(outer, fraction: .infinity)
    layout.select(.terminal)
    layout.select(.buildLog, activate: false)
    #expect(layout.activePane == .terminal)

    let data = try JSONEncoder().encode(layout)
    let restored = try JSONDecoder().decode(WorkbenchLayout.self, from: data)
    #expect(restored.isValid)
    #expect(restored == layout)
    guard case .split(let restoredOuter) = restored.root,
      case .split(let restoredInner) = restoredOuter.second
    else {
      Issue.record("Expected nested splits")
      return
    }
    #expect(restoredOuter.fraction == 0.31)
    #expect(restoredInner.fraction == 0.62)

    var invalid = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    invalid["version"] = 2
    let unknownVersion = try JSONSerialization.data(withJSONObject: invalid)
    #expect(try !JSONDecoder().decode(WorkbenchLayout.self, from: unknownVersion).isValid)
  }

  @Test func rejectsInvalidRestoredGroups() throws {
    let data = try JSONEncoder().encode(WorkbenchLayout())
    let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let root = try #require(original["root"] as? [String: Any])
    let payload = try #require(root["group"] as? [String: Any])
    let group = try #require(payload["_0"] as? [String: Any])
    let invalidFields: [(String, Any)] = [
      ("tabs", [] as [String]),
      ("tabs", ["buildLog", "serial"]),
      ("tabs", ["buildLog", "serial", "serial"]),
    ]

    for (field, value) in invalidFields {
      var invalidGroup = group
      invalidGroup[field] = value
      var invalid = original
      invalid["root"] = ["group": ["_0": invalidGroup]]
      let invalidData = try JSONSerialization.data(withJSONObject: invalid)
      #expect(try !JSONDecoder().decode(WorkbenchLayout.self, from: invalidData).isValid)
    }

    var hiddenActivePane = original
    hiddenActivePane["activePane"] = "terminal"
    let hiddenData = try JSONSerialization.data(withJSONObject: hiddenActivePane)
    #expect(try !JSONDecoder().decode(WorkbenchLayout.self, from: hiddenData).isValid)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(WorkbenchLayout.self, from: Data("{}".utf8))
    }
  }

  @Test func rejectsInvalidRestoredBranches() throws {
    var layout = WorkbenchLayout()
    #expect(layout.move(.serial, to: .split(layout.root.id, edge: .right)) == true)
    let data = try JSONEncoder().encode(layout)
    let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let root = try #require(original["root"] as? [String: Any])
    let payload = try #require(root["split"] as? [String: Any])
    let branch = try #require(payload["_0"] as? [String: Any])
    let first = try #require(branch["first"] as? [String: Any])
    let firstPayload = try #require(first["group"] as? [String: Any])
    var firstGroup = try #require(firstPayload["_0"] as? [String: Any])
    firstGroup["selected"] = "serial"
    let invalidFields: [(String, Any)] = [
      ("fraction", -0.01),
      ("fraction", 1.01),
      ("id", try #require(layout.group(containing: .serial)?.id.uuidString)),
      ("second", try #require(branch["first"])),
      ("first", ["group": ["_0": firstGroup]]),
    ]

    for (field, value) in invalidFields {
      var invalidBranch = branch
      invalidBranch[field] = value
      var invalid = original
      invalid["root"] = ["split": ["_0": invalidBranch]]
      let invalidData = try JSONSerialization.data(withJSONObject: invalid)
      #expect(try !JSONDecoder().decode(WorkbenchLayout.self, from: invalidData).isValid)
    }
  }

  @Test func togglesDefaultSplitAndKeepsActiveVisible() {
    var layout = WorkbenchLayout()
    layout.select(.terminal)
    layout.select(.buildLog, activate: false)
    #expect(layout.activePane == .buildLog)
    layout.toggleSplit()
    #expect(layout.root.visiblePanes == [.buildLog, .serial])
    #expect(layout.isValid)
    layout.select(.serial)
    layout.toggleSplit()
    #expect(layout.root.visiblePanes == [.serial])
    #expect(layout.isValid)
  }
}
