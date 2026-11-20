import AppKit
import SwiftUI
import TekmorCore
import UniformTypeIdentifiers

extension ConsolePane {
  func title(using l10n: AppL10n) -> String {
    switch self {
    case .buildLog: l10n.tr(.init("pane.buildLog", defaultValue: "Build Log"))
    case .serial: l10n.tr(.init("pane.serial", defaultValue: "Serial Monitor"))
    case .terminal: l10n.tr(.init("pane.terminal", defaultValue: "Terminal"))
    }
  }

  fileprivate var dragType: UTType {
    UTType(exportedAs: "com.tekmor.workbench." + rawValue.lowercased(), conformingTo: .data)
  }

  fileprivate func dragProvider() -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(
      forTypeIdentifier: dragType.identifier, visibility: .ownProcess
    ) { completion in
      completion(Data(rawValue.utf8), nil)
      return nil
    }
    return provider
  }
}

extension WorkbenchLayout.Edge {
  func title(using l10n: AppL10n) -> String {
    switch self {
    case .left: l10n.tr(.init("workbench.splitLeft", defaultValue: "Split Left"))
    case .right: l10n.tr(.init("workbench.splitRight", defaultValue: "Split Right"))
    case .top: l10n.tr(.init("workbench.splitUp", defaultValue: "Split Up"))
    case .bottom: l10n.tr(.init("workbench.splitDown", defaultValue: "Split Down"))
    }
  }
}

struct WorkbenchView<HeaderAccessory: View, Content: View>: View {
  let workspace: Workspace
  let node: WorkbenchLayout.Node
  var resizeTarget: WorkbenchResizeTarget?
  var showsHeaderSeparator: (ConsolePane) -> Bool = { _ in true }
  @ViewBuilder var headerAccessory: (ConsolePane) -> HeaderAccessory
  @ViewBuilder var content: (ConsolePane) -> Content

  var body: some View {
    switch node {
    case .group(let group):
      WorkbenchGroupView(
        workspace: workspace,
        group: group,
        resizeTarget: resizeTarget,
        showsHeaderSeparator: showsHeaderSeparator(group.selected),
        headerAccessory: {
          headerAccessory(group.selected)
            .id(group.selected)
        },
        content: {
          content(group.selected)
            .id(group.selected)
        })
    case .split(let split):
      NativeWorkbenchSplit(
        split: split, workspace: workspace,
        first: WorkbenchView(
          workspace: workspace,
          node: split.first,
          resizeTarget: WorkbenchResizeTarget(split: split, isFirst: true),
          showsHeaderSeparator: showsHeaderSeparator,
          headerAccessory: headerAccessory,
          content: content
        ).id(split.first.id),
        second: WorkbenchView(
          workspace: workspace,
          node: split.second,
          resizeTarget: WorkbenchResizeTarget(split: split, isFirst: false),
          showsHeaderSeparator: showsHeaderSeparator,
          headerAccessory: headerAccessory,
          content: content
        ).id(split.second.id)
      )
      .id(split.id)
    }
  }
}

struct WorkbenchResizeTarget {
  let split: WorkbenchLayout.Split
  let isFirst: Bool
}

private struct WorkbenchGroupView<HeaderAccessory: View, Content: View>: View {
  let workspace: Workspace
  let group: WorkbenchLayout.Group
  let resizeTarget: WorkbenchResizeTarget?
  let showsHeaderSeparator: Bool
  @ViewBuilder var headerAccessory: () -> HeaderAccessory
  @ViewBuilder var content: () -> Content
  @Environment(\.l10n) private var l10n
  @Environment(\.workbenchTextScale) private var textScale
  @State private var tabFrames: [ConsolePane: CGRect] = [:]
  @State private var preview: WorkbenchDrop.Target?

  private var tabHeight: CGFloat { max(32, 17 * textScale + 10) }

  var body: some View {
    GeometryReader { geometry in
      NativeWorkbenchDrop(
        drop: WorkbenchDrop(
          workspace: workspace, group: group, size: geometry.size,
          tabFrames: tabFrames, tabHeight: tabHeight, preview: $preview)
      ) {
        VStack(spacing: 0) {
          HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 2) {
                ForEach(group.tabs) { pane in tab(pane) }
              }
              .fixedSize(horizontal: true, vertical: false)
              tabPicker
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
              headerAccessory()
              if showsHeaderSeparator {
                VerticalHairline(height: 12)
              }
              layoutMenu
                .layoutPriority(1)
            }
          }
          .padding(.leading, 8)
          .padding(.trailing, 6)
          .frame(height: tabHeight)
          .background(TekmorColor.workspaceBackground)
          .overlay(alignment: .bottom) { HairlineDivider(subtle: true) }

          content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .coordinateSpace(.named(group.id))
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) {
          if let preview {
            let rect = preview.rect(in: geometry.size, tabHeight: tabHeight)
            Rectangle()
              .fill(TekmorColor.brand.opacity(preview.isTab ? 1 : 0.19))
              .overlay { Rectangle().strokeBorder(TekmorColor.brand, lineWidth: 1) }
              .frame(width: rect.width, height: rect.height)
              .offset(x: rect.minX, y: rect.minY)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
      }
    }
  }

  private func tab(_ pane: ConsolePane) -> some View {
    let groupID = group.id
    let selected = group.selected == pane
    let isFocusedPane = workspace.activePane == pane
    let title = pane.title(using: l10n)
    return WorkbenchTabButton(
      title: title,
      selected: selected,
      isFocusedPane: isFocusedPane,
      showsListeningDot: pane == .serial && workspace.serialConnected,
      issueCount: pane == .buildLog && !selected ? workspace.output.logIssueCount : 0,
      tabHeight: tabHeight,
      action: { workspace.selectConsolePane(pane) }
    )
    .onDrag {
      pane.dragProvider()
    } preview: {
      Text(title)
        .font(.system(size: 12 * textScale, weight: .semibold))
        .padding(.horizontal, 10)
        .frame(height: tabHeight)
        .background(TekmorColor.workspaceBackground, in: RoundedRectangle(cornerRadius: 5))
    }
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("workbench.tab." + pane.rawValue)
    .help(title)
    .onGeometryChange(for: CGRect.self) {
      $0.frame(in: .named(groupID))
    } action: { frame in
      tabFrames[pane] = frame
    }
    .onDisappear { tabFrames[pane] = nil }
    .contextMenu { layoutActions(for: pane) }
  }

  private var tabPicker: some View {
    let title = l10n.tr(.init("workbench.tabs", defaultValue: "Console Tabs"))
    return Menu {
      Picker(title, selection: Binding(get: { group.selected }, set: workspace.selectConsolePane)) {
        ForEach(group.tabs) { pane in
          Text(pane.title(using: l10n)).tag(pane)
        }
      }
      .pickerStyle(.inline)
    } label: {
      Text(group.selected.title(using: l10n))
        .font(.system(size: 12 * textScale, weight: .semibold))
        .lineLimit(1)
    }
    .accessibilityLabel(title)
    .accessibilityValue(group.selected.title(using: l10n))
  }

  private var layoutMenu: some View {
    Menu {
      layoutActions(for: group.selected)
    } label: {
      Label(
        l10n.tr(.init("workbench.layout", defaultValue: "Pane Layout")),
        systemImage: workspace.isSplitConsole ? "rectangle.split.1x2.fill" : "rectangle.split.1x2"
      )
      .labelStyle(.iconOnly)
      .frame(width: 24, height: 24)
      .foregroundStyle(TekmorColor.textSecondary)
    }
    .menuIndicator(.hidden)
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityLabel(l10n.tr(.init("workbench.layout", defaultValue: "Pane Layout")))
    .help(l10n.tr(.init("workbench.layout", defaultValue: "Pane Layout")))
  }

  @ViewBuilder
  private func layoutActions(for pane: ConsolePane) -> some View {
    let target =
      group.tabs.count > 1 ? group : workspace.workbench.root.groups.first { $0.id != group.id }
    if let target {
      ForEach(WorkbenchLayout.Edge.allCases, id: \.self) { edge in
        Button(edge.title(using: l10n)) {
          workspace.moveConsolePane(pane, to: .split(target.id, edge: edge))
        }
      }
    }
    let otherGroups = workspace.workbench.root.groups.filter { $0.id != group.id }
    if group.tabs.count > 1 || !otherGroups.isEmpty {
      Menu(l10n.tr(.init("workbench.moveTab", defaultValue: "Move Tab"))) {
        moveActions(for: pane, to: otherGroups)
      }
    }
    if let resizeTarget {
      Menu(l10n.tr(.init("workbench.resizeSplit", defaultValue: "Resize Split"))) {
        Button(l10n.tr(.init("workbench.enlargePane", defaultValue: "Make This Pane Larger"))) {
          resize(resizeTarget, by: 0.1)
        }
        Button(l10n.tr(.init("workbench.shrinkPane", defaultValue: "Make This Pane Smaller"))) {
          resize(resizeTarget, by: -0.1)
        }
        Button(l10n.tr(.init("workbench.equalPanes", defaultValue: "Make Panes Equal"))) {
          workspace.resizeConsoleSplit(resizeTarget.split.id, fraction: 0.5)
        }
      }
    }
    if workspace.isSplitConsole {
      Divider()
      Button(l10n.tr(.init("workbench.merge", defaultValue: "Merge All Panes"))) {
        workspace.mergeConsolePanes()
      }
    }
  }

  @ViewBuilder
  private func moveActions(for pane: ConsolePane, to otherGroups: [WorkbenchLayout.Group])
    -> some View
  {
    if let index = group.tabs.firstIndex(of: pane) {
      if index > 0 {
        Button(l10n.tr(.init("workbench.moveEarlier", defaultValue: "Move Earlier"))) {
          workspace.moveConsolePane(pane, to: .tabs(group.id, before: group.tabs[index - 1]))
        }
      }
      if index + 1 < group.tabs.count {
        Button(l10n.tr(.init("workbench.moveLater", defaultValue: "Move Later"))) {
          let before = index + 2 < group.tabs.count ? group.tabs[index + 2] : nil
          workspace.moveConsolePane(pane, to: .tabs(group.id, before: before))
        }
      }
    }
    ForEach(otherGroups) { target in
      let title = target.selected.title(using: l10n)
      Menu(l10n.tr(.init("workbench.moveToGroup", defaultValue: "Move to \(title) Group"))) {
        ForEach(target.tabs) { tab in
          let title = tab.title(using: l10n)
          Button(l10n.tr(.init("workbench.insertBefore", defaultValue: "Insert Before \(title)"))) {
            workspace.moveConsolePane(pane, to: .tabs(target.id, before: tab))
          }
        }
        Button(l10n.tr(.init("workbench.moveToEnd", defaultValue: "Move to End"))) {
          workspace.moveConsolePane(pane, to: .tabs(target.id, before: nil))
        }
      }
    }
  }

  private func resize(_ target: WorkbenchResizeTarget, by step: Double) {
    let fraction = target.split.fraction + (target.isFirst ? step : -step)
    workspace.resizeConsoleSplit(target.split.id, fraction: fraction)
  }
}

private struct WorkbenchTabButton: View {
  let title: String
  let selected: Bool
  let isFocusedPane: Bool
  let showsListeningDot: Bool
  let issueCount: Int
  let tabHeight: CGFloat
  let action: () -> Void
  @State private var hovered = false
  @Environment(\.l10n) private var l10n
  @Environment(\.workbenchTextScale) private var textScale

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Text(title)
          .font(.system(size: 12 * textScale, weight: selected ? .semibold : .medium))
          .lineLimit(1)
          .foregroundStyle(foregroundColor)
        if showsListeningDot {
          Circle()
            .fill(TekmorColor.success)
            .frame(width: 5, height: 5)
            .accessibilityLabel(
              l10n.tr(.init("accessibility.connected", defaultValue: "Listening")))
        }
        if issueCount > 0 {
          Text(issueCount.formatted())
            .font(.system(size: 10 * textScale, weight: .semibold, design: .monospaced))
            .foregroundStyle(TekmorColor.warning)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        backgroundColor,
        in: RoundedRectangle(cornerRadius: TekmorRadius.control, style: .continuous)
      )
      .frame(height: tabHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovered = $0 }
  }

  private var foregroundColor: Color {
    if selected {
      return isFocusedPane ? TekmorColor.textInk : TekmorColor.textPrimary
    }
    return hovered ? TekmorColor.textPrimary : TekmorColor.textSecondary
  }

  private var backgroundColor: Color {
    if selected {
      return isFocusedPane ? TekmorColor.brandTintSubtle : TekmorColor.hoverFill
    }
    return hovered ? TekmorColor.hoverFill : .clear
  }
}

@MainActor
private struct WorkbenchDrop {
  enum Target {
    case tab(before: ConsolePane?, insertionX: CGFloat)
    case edge(WorkbenchLayout.Edge)

    var isTab: Bool {
      if case .tab = self { return true }
      return false
    }

    func destination(in group: UUID) -> WorkbenchLayout.Destination {
      switch self {
      case .tab(let before, _): .tabs(group, before: before)
      case .edge(let edge): .split(group, edge: edge)
      }
    }

    func rect(in size: CGSize, tabHeight: CGFloat) -> CGRect {
      switch self {
      case .tab(_, let x):
        return CGRect(x: x, y: 5, width: 2, height: tabHeight - 10)
      case .edge(let edge):
        let height = max(0, size.height - tabHeight)
        switch edge {
        case .left:
          return CGRect(x: 0, y: tabHeight, width: size.width / 2, height: height)
        case .right:
          return CGRect(
            x: size.width / 2, y: tabHeight, width: size.width / 2, height: height)
        case .top:
          return CGRect(x: 0, y: tabHeight, width: size.width, height: height / 2)
        case .bottom:
          return CGRect(
            x: 0, y: tabHeight + height / 2, width: size.width, height: height / 2)
        }
      }
    }
  }

  let workspace: Workspace
  let group: WorkbenchLayout.Group
  let size: CGSize
  let tabFrames: [ConsolePane: CGRect]
  let tabHeight: CGFloat
  @Binding var preview: Target?

  func update(pane: ConsolePane?, at point: CGPoint) -> NSDragOperation {
    preview = pane.flatMap { drop($0, at: point)?.target }
    return preview == nil ? [] : .move
  }

  func exit() { preview = nil }

  func perform(pane: ConsolePane?, at point: CGPoint) -> Bool {
    defer { preview = nil }
    guard let pane, let drop = drop(pane, at: point) else { return false }
    workspace.moveConsolePane(drop.pane, to: drop.target.destination(in: group.id))
    return true
  }

  private func drop(_ pane: ConsolePane, at point: CGPoint) -> (pane: ConsolePane, target: Target)?
  {
    guard CGRect(origin: .zero, size: size).contains(point),
      let target = target(at: point, dragging: pane),
      workspace.workbench.canMove(pane, to: target.destination(in: group.id))
    else { return nil }
    return (pane, target)
  }

  private func target(at point: CGPoint, dragging pane: ConsolePane) -> Target? {
    if point.y < tabHeight {
      let next = group.tabs.first {
        $0 != pane && point.x < (tabFrames[$0]?.midX ?? 0)
      }
      let x =
        next.flatMap { tabFrames[$0]?.minX }
        ?? group.tabs.last.flatMap { tabFrames[$0]?.maxX } ?? 4
      return .tab(before: next, insertionX: x)
    }
    let distances: [(WorkbenchLayout.Edge, CGFloat)] = [
      (.left, point.x / max(size.width, 1)),
      (.right, (size.width - point.x) / max(size.width, 1)),
      (.top, (point.y - tabHeight) / max(size.height - tabHeight, 1)),
      (.bottom, (size.height - point.y) / max(size.height - tabHeight, 1)),
    ]
    guard let (edge, distance) = distances.min(by: { $0.1 < $1.1 }), distance < 0.25 else {
      return nil
    }
    return .edge(edge)
  }
}

private struct NativeWorkbenchDrop<Content: View>: NSViewRepresentable {
  let drop: WorkbenchDrop
  @ViewBuilder var content: () -> Content
  @Environment(\.l10n) private var l10n
  @Environment(\.locale) private var locale
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.workbenchTextScale) private var textScale

  func makeNSView(context: Context) -> WorkbenchDropHost {
    let host = WorkbenchDropHost(rootView: hostedContent)
    host.sizingOptions = []
    host.registerForDraggedTypes(
      ConsolePane.allCases.map { NSPasteboard.PasteboardType($0.dragType.identifier) })
    host.drop = drop
    return host
  }

  func updateNSView(_ host: WorkbenchDropHost, context: Context) {
    host.rootView = hostedContent
    host.drop = drop
  }

  private var hostedContent: AnyView {
    AnyView(
      content()
        .environment(\.l10n, l10n)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, layoutDirection)
        .environment(\.workbenchTextScale, textScale)
        .tint(TekmorColor.brand))
  }
}

private final class WorkbenchDropHost: NSHostingView<AnyView> {
  var drop: WorkbenchDrop?

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard drop?.update(pane: pane(from: sender), at: location(of: sender)) == .move else {
      return []
    }
    // SwiftUI's onDrag source advertises copy. The layout operation moves the unique pane.
    return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
  }

  override func wantsPeriodicDraggingUpdates() -> Bool { false }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    drop?.exit()
  }

  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    draggingUpdated(sender) != []
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    drop?.perform(pane: pane(from: sender), at: location(of: sender)) ?? false
  }

  override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
    drop?.exit()
  }

  override func draggingEnded(_ sender: any NSDraggingInfo) {
    drop?.exit()
  }

  private func location(of sender: any NSDraggingInfo) -> CGPoint {
    let point = convert(sender.draggingLocation, from: nil)
    return CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
  }

  private func pane(from sender: any NSDraggingInfo) -> ConsolePane? {
    guard sender.draggingSource != nil,
      !sender.draggingSourceOperationMask.intersection([.move, .copy]).isEmpty
    else {
      return nil
    }
    return ConsolePane.allCases.first {
      sender.draggingPasteboard.availableType(from: [
        NSPasteboard.PasteboardType($0.dragType.identifier)
      ]) != nil
    }
  }
}

private struct NativeWorkbenchSplit<First: View, Second: View>: NSViewControllerRepresentable {
  let split: WorkbenchLayout.Split
  let workspace: Workspace
  let first: First
  let second: Second
  @Environment(\.l10n) private var l10n
  @Environment(\.locale) private var locale
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.workbenchTextScale) private var textScale

  func makeNSViewController(context: Context) -> WorkbenchSplitController {
    let controller = WorkbenchSplitController()
    let divider = WorkbenchSplitView()
    divider.isVertical = split.axis == .horizontal
    divider.dividerStyle = .thin
    controller.splitView = divider
    divider.onSizeChange = { [weak controller] size in
      controller?.updateMinimumThickness(for: size)
    }

    let firstHost = NSHostingController(rootView: hostedFirst)
    let secondHost = NSHostingController(rootView: hostedSecond)
    firstHost.sizingOptions = []
    secondHost.sizingOptions = []
    for host in [firstHost as NSViewController, secondHost as NSViewController] {
      let item = NSSplitViewItem(viewController: host)
      item.canCollapse = false
      controller.addSplitViewItem(item)
    }
    controller.setLayout(split)
    return controller
  }

  func updateNSViewController(_ controller: WorkbenchSplitController, context: Context) {
    (controller.splitViewItems[0].viewController as? NSHostingController<Hosted<First>>)?.rootView =
      hostedFirst
    (controller.splitViewItems[1].viewController as? NSHostingController<Hosted<Second>>)?
      .rootView = hostedSecond
    (controller.splitView as? WorkbenchSplitView)?.onResize = {
      [weak workspace, id = split.id] fraction in
      workspace?.resizeConsoleSplit(id, fraction: fraction)
    }
    controller.setLayout(split)
  }

  private struct Hosted<Content: View>: View {
    let content: Content
    let l10n: AppL10n
    let locale: Locale
    let layoutDirection: LayoutDirection
    let textScale: CGFloat

    var body: some View {
      content
        .environment(\.l10n, l10n)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, layoutDirection)
        .environment(\.workbenchTextScale, textScale)
        .tint(TekmorColor.brand)
    }
  }

  private var hostedFirst: Hosted<First> {
    Hosted(
      content: first, l10n: l10n, locale: locale, layoutDirection: layoutDirection,
      textScale: textScale)
  }

  private var hostedSecond: Hosted<Second> {
    Hosted(
      content: second, l10n: l10n, locale: locale, layoutDirection: layoutDirection,
      textScale: textScale)
  }
}

private final class WorkbenchSplitController: NSSplitViewController {
  private var fraction: Double = 0.5
  private var minimumSizes: [CGSize] = []
  private var appliedExtent: CGFloat?

  func setLayout(_ split: WorkbenchLayout.Split) {
    let sizes = [split.first, split.second].map {
      $0.minimumSize(dividerThickness: splitView.dividerThickness)
    }
    guard fraction != split.fraction || minimumSizes != sizes else { return }
    fraction = split.fraction
    minimumSizes = sizes
    appliedExtent = nil
    if isViewLoaded { view.needsLayout = true }
  }

  override func viewWillLayout() {
    updateMinimumThickness()
    super.viewWillLayout()
  }

  override func splitView(
    _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
    forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int
  ) -> NSRect {
    _ = super.splitView(
      splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect,
      ofDividerAt: dividerIndex)
    if splitView.isVertical {
      return NSRect(x: drawnRect.midX - 3.5, y: drawnRect.minY, width: 7, height: drawnRect.height)
    }
    return NSRect(x: drawnRect.minX, y: drawnRect.midY - 3.5, width: drawnRect.width, height: 7)
  }

  func updateMinimumThickness(for size: CGSize? = nil) {
    guard let split = splitView as? WorkbenchSplitView, minimumSizes.count == 2 else { return }
    let size = size ?? split.bounds.size
    let extent = (split.isVertical ? size.width : size.height) - split.dividerThickness
    let thicknesses = minimumSizes.map { split.isVertical ? $0.width : $0.height }
    let scale = min(1, max(0, extent) / thicknesses.reduce(0, +))
    for (item, thickness) in zip(splitViewItems, thicknesses) {
      let minimum = thickness * scale
      if item.minimumThickness != minimum { item.minimumThickness = minimum }
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    guard let split = splitView as? WorkbenchSplitView, !split.trackingDivider,
      split.arrangedSubviews.count == 2, split.extent > 0, split.extent != appliedExtent
    else { return }
    appliedExtent = split.extent
    let position = min(
      max(fraction * split.extent, split.minPossiblePositionOfDivider(at: 0)),
      split.maxPossiblePositionOfDivider(at: 0))
    split.setPosition(position, ofDividerAt: 0)
  }
}

private final class WorkbenchSplitView: NSSplitView {
  var onResize: ((Double) -> Void)?
  var onSizeChange: ((CGSize) -> Void)?
  private(set) var trackingDivider = false
  private var initialPosition: CGFloat?
  private var mouseMonitor: Any?

  var extent: CGFloat { (isVertical ? bounds.width : bounds.height) - dividerThickness }

  override func setFrameSize(_ newSize: NSSize) {
    onSizeChange?(newSize)
    super.setFrameSize(newSize)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    mouseMonitor = nil
    guard window != nil else { return }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
      [weak self] event in
      MainActor.assumeIsolated {
        self?.observeMouse(event)
      }
      return event
    }
  }

  private func observeMouse(_ event: NSEvent) {
    guard event.window === window else { return }
    if event.type == .leftMouseDown {
      let point = convert(event.locationInWindow, from: nil)
      guard dividerHitRect.contains(point) else { return }
      initialPosition = dividerPosition
      trackingDivider = true
    } else if trackingDivider {
      // AppKit's divider gesture processes mouse-up before the saved layout is updated.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        trackingDivider = false
        if let initialPosition, let current = dividerPosition,
          initialPosition != current, extent > 0
        {
          onResize?(current / extent)
        }
        initialPosition = nil
      }
    }
  }

  private var dividerHitRect: CGRect {
    guard let first = arrangedSubviews.first else { return .zero }
    if isVertical {
      return CGRect(
        x: first.frame.maxX + dividerThickness / 2 - 3.5, y: bounds.minY,
        width: 7, height: bounds.height)
    }
    return CGRect(
      x: bounds.minX, y: first.frame.maxY + dividerThickness / 2 - 3.5,
      width: bounds.width, height: 7)
  }

  private var dividerPosition: CGFloat? {
    arrangedSubviews.first.map { isVertical ? $0.frame.width : $0.frame.height }
  }
}
