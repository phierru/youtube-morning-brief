import SwiftUI

enum SidebarItem: Hashable {
    case dashboard
    case log
    case settings
    case subject(String)
}

struct ContentView: View {
    @EnvironmentObject private var config: ConfigStore
    @State private var selection: SidebarItem? = .dashboard
    @State private var showAddSubject = false
    @State private var newSubjectName = ""

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    Label("Dashboard", systemImage: "gauge.medium")
                        .tag(SidebarItem.dashboard)
                    Label("Log", systemImage: "text.alignleft")
                        .tag(SidebarItem.log)
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                    Section("Subjects") {
                        ForEach(config.subjects) { s in
                            Label(s.name, systemImage: "folder")
                                .tag(SidebarItem.subject(s.id))
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
                .safeAreaInset(edge: .bottom) {
                    Button {
                        showAddSubject = true
                    } label: {
                        Label("Add Subject", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                }
            } detail: {
                switch selection {
                case .subject(let id):
                    SubjectDetailView(subjectID: id)
                case .log:
                    LogView()
                case .settings:
                    SettingsView()
                default:
                    DashboardView()
                }
            }
            Divider()
            HStack {
                Spacer()
                Link("☕ Buy me a coffee: buymeacoffee.com/phierru",
                     destination: URL(string: "https://buymeacoffee.com/phierru")!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .alert("New Subject", isPresented: $showAddSubject) {
            TextField("Subject name", text: $newSubjectName)
            Button("Add") {
                if config.addSubject(named: newSubjectName) {
                    selection = .subject(
                        newSubjectName.trimmingCharacters(in: .whitespaces))
                }
                newSubjectName = ""
            }
            Button("Cancel", role: .cancel) { newSubjectName = "" }
        } message: {
            Text("A daily brief note will be generated for this subject once it has channels.")
        }
        .onChange(of: config.subjects) {
            if case .subject(let id) = selection,
               !config.subjects.contains(where: { $0.id == id }) {
                selection = .dashboard
            }
        }
    }
}
