import AppKit
import SwiftUI

struct SidebarView: View {
  @Bindable var workspace: Workspace
  @State private var projectsExpanded = true
  @Environment(\.l10n) private var l10n

  var body: some View {
    VStack(spacing: 0) {
      projectsHeader

      List(selection: selection) {
        if projectsExpanded {
          ForEach(workspace.displayedProjectFolders) { folder in
            projectRow(folder)
          }
        }

        Section(l10n.tr(.init("sidebar.section.hardwareAndEnv", defaultValue: "Hardware & Tools")))
        {
          Label {
            HStack {
              Text(l10n.tr(.init("sidebar.devices", defaultValue: "Devices")))
              Spacer(minLength: 4)
              if workspace.connectedDeviceCount > 0 {
                Text("\(workspace.connectedDeviceCount)")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          } icon: {
            Image(systemName: "cable.connector")
          }
          .tag(Workspace.SidebarItem.devices)
          .help(l10n.tr(.init("help.showDevices", defaultValue: "Devices (⌘3)")))

          Label {
            HStack {
              Text(l10n.tr(.init("sidebar.tools", defaultValue: "Toolchains")))
              Spacer(minLength: 4)
              if workspace.isManagingTools || workspace.loadingCube {
                MiniActivitySpinner(size: 11, tint: TekmorColor.brand)
              } else if workspace.missingRequiredToolCount > 0 {
                Text(
                  l10n.tr(
                    .init(
                      "sidebar.tools.missingCount",
                      defaultValue: "\(workspace.missingRequiredToolCount) missing"))
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          } icon: {
            Image(systemName: "shippingbox")
          }
          .tag(Workspace.SidebarItem.tools)
          .help(l10n.tr(.init("help.showTools", defaultValue: "Toolchains (⌘4)")))
        }
      }
      .listStyle(.sidebar)
      .contextMenu(forSelectionType: Workspace.SidebarItem.self) { items in
        if case .project(let path) = items.first,
          let folder = workspace.projectFolders.first(where: { $0.path == path })
        {
          projectMenu(folder)
        }
      }
    }
    .onChange(of: workspace.sidebarSelection) {
      if case .project = workspace.sidebarSelection {
        projectsExpanded = true
      }
    }
  }

  private var projectsHeader: some View {
    let title = l10n.tr(.init("sidebar.projects", defaultValue: "Projects"))
    let sortTitle = l10n.tr(.init("sidebar.sort", defaultValue: "Sort Projects"))
    let addTitle = l10n.tr(.init("action.addProjectEllipsis", defaultValue: "Add Project…"))

    return HStack(spacing: 6) {
      Button {
        projectsExpanded.toggle()
      } label: {
        HStack(spacing: 5) {
          Text(title)
            .font(.subheadline.weight(.semibold))
          Image(systemName: projectsExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2.weight(.semibold))
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(
        l10n.tr(
          projectsExpanded
            ? .init("sidebar.projects.expanded", defaultValue: "Expanded")
            : .init("sidebar.projects.collapsed", defaultValue: "Collapsed")))

      Spacer(minLength: 0)

      Group {
        Menu {
          Picker(sortTitle, selection: $workspace.projectSortOrder) {
            ForEach(Workspace.ProjectSortOrder.allCases) { order in
              Text(order.title(using: l10n)).tag(order)
            }
          }
          .pickerStyle(.inline)
        } label: {
          Label(sortTitle, systemImage: "slider.horizontal.3")
            .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .help(sortTitle)

        Button(action: workspace.chooseProject) {
          Label(addTitle, systemImage: "plus")
            .labelStyle(.iconOnly)
        }
        .disabled(!workspace.canStartAction)
        .help(addTitle)
      }
      .buttonStyle(TekmorIconButtonStyle(tint: Color(nsColor: .secondaryLabelColor)))
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 15)
    .padding(.vertical, 6)
  }

  private var selection: Binding<Workspace.SidebarItem?> {
    Binding(
      get: { workspace.sidebarSelection },
      set: { item in
        if let item { workspace.selectSidebarItem(item) }
      }
    )
  }

  private func projectRow(_ folder: Workspace.ProjectFolder) -> some View {
    Label {
      HStack {
        Text(folder.name)
          .lineLimit(1)
        Spacer(minLength: 4)
        if workspace.project?.path == folder.path {
          projectIndicator
        }
      }
    } icon: {
      Image(systemName: "folder")
        .foregroundStyle(folder.tint.color)
    }
    .background {
      ProjectRowSelectionAppearance()
        .allowsHitTesting(false)
    }
    .tag(Workspace.SidebarItem.project(folder.path))
    .selectionDisabled(!workspace.canStartAction && workspace.project?.path != folder.path)
    .help(folder.path)
    .accessibilityValue(folder.tint.title(using: l10n))
  }

  @ViewBuilder
  private var projectIndicator: some View {
    if workspace.running && !workspace.isManagingTools {
      MiniActivitySpinner(size: 11, tint: TekmorColor.brand)
    } else if workspace.output.logIssueCount > 0 {
      Text("\(workspace.output.logIssueCount)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(TekmorColor.warning)
    } else if workspace.serialConnected {
      Circle()
        .fill(TekmorColor.success)
        .frame(width: 6, height: 6)
        .help(
          l10n.tr(
            .init("sidebar.indicator.serialConnected", defaultValue: "Listening to serial output")))
    }
  }

  @ViewBuilder
  private func projectMenu(_ folder: Workspace.ProjectFolder) -> some View {
    ProjectFolderColorMenu(workspace: workspace, folder: folder)
    Button(l10n.tr(.init("action.revealInFinder", defaultValue: "Reveal in Finder"))) {
      workspace.revealProject(folder.url)
    }
    if workspace.project?.path != folder.path || workspace.canStartAction {
      Divider()
      Button(
        l10n.tr(.init("action.removeProjectFromSidebar", defaultValue: "Remove from Sidebar")),
        role: .destructive
      ) {
        workspace.removeProject(folder.path)
      }
    }
  }
}

private struct ProjectRowSelectionAppearance: NSViewRepresentable {
  func makeNSView(context: Context) -> RowAttachment {
    RowAttachment()
  }

  func updateNSView(_ view: RowAttachment, context: Context) {
    view.observeRow()
  }

  final class RowAttachment: NSView {
    private weak var row: NSTableRowView?
    private var observation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      observeRow()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      observeRow()
    }

    func observeRow() {
      var ancestor = window == nil ? nil : superview
      while let view = ancestor, !(view is NSTableRowView) {
        ancestor = view.superview
      }
      let tableRow = ancestor as? NSTableRowView
      guard tableRow !== row else { return }
      observation?.invalidate()
      row = tableRow

      // Keep AppKit's neutral highlight for project rows as list focus changes.
      observation = tableRow?.observe(\.isEmphasized, options: [.initial, .new]) { row, change in
        guard change.newValue == true else { return }
        MainActor.assumeIsolated {
          row.isEmphasized = false
        }
      }
    }
  }
}

struct ProjectFolderColorMenu: View {
  let workspace: Workspace
  let folder: Workspace.ProjectFolder
  @Environment(\.l10n) private var l10n

  var body: some View {
    let title = l10n.tr(.init("sidebar.folderColor", defaultValue: "Folder Color"))
    Menu {
      Picker(
        title,
        selection: Binding(
          get: { folder.tint },
          set: { workspace.setProjectTint($0, for: folder.path) }
        )
      ) {
        ForEach(Workspace.ProjectFolder.Tint.allCases) { tint in
          Label {
            Text(tint.title(using: l10n))
          } icon: {
            Image(nsImage: tint.menuSwatch)
              .renderingMode(.original)
          }
          .tag(tint)
        }
      }
      .pickerStyle(.inline)
    } label: {
      Label(title, systemImage: "paintpalette")
    }
    .menuOrder(.fixed)
  }
}

extension Workspace.ProjectFolder.Tint {
  fileprivate var menuSwatch: NSImage {
    let isDefault = self == .automatic
    let swatchColor = isDefault ? NSColor.secondaryLabelColor : NSColor(color)
    let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
      let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
      swatchColor.set()
      if isDefault {
        circle.lineWidth = 1.25
        circle.stroke()
      } else {
        circle.fill()
      }
      return true
    }
    image.isTemplate = false
    return image
  }

  fileprivate var color: Color {
    switch self {
    case .automatic: .primary
    case .red: .red
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .blue: .blue
    case .purple: .purple
    case .gray: .gray
    }
  }

  fileprivate func title(using l10n: AppL10n) -> String {
    switch self {
    case .automatic: l10n.tr(.init("sidebar.folderColor.default", defaultValue: "Default"))
    case .red: l10n.tr(.init("sidebar.folderColor.red", defaultValue: "Red"))
    case .orange: l10n.tr(.init("sidebar.folderColor.orange", defaultValue: "Orange"))
    case .yellow: l10n.tr(.init("sidebar.folderColor.yellow", defaultValue: "Yellow"))
    case .green: l10n.tr(.init("sidebar.folderColor.green", defaultValue: "Green"))
    case .blue: l10n.tr(.init("sidebar.folderColor.blue", defaultValue: "Blue"))
    case .purple: l10n.tr(.init("sidebar.folderColor.purple", defaultValue: "Purple"))
    case .gray: l10n.tr(.init("sidebar.folderColor.gray", defaultValue: "Gray"))
    }
  }
}
