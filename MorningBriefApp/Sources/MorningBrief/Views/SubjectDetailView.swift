import SwiftUI

struct SubjectDetailView: View {
    @EnvironmentObject private var config: ConfigStore
    let subjectID: String

    @State private var input = ""
    @State private var resolving = false
    @State private var resolved: ResolvedChannel?
    @State private var errorText: String?
    @State private var confirmDelete = false

    private var subject: BriefSubject? {
        config.subjects.first { $0.id == subjectID }
    }

    var body: some View {
        if let subject {
            VStack(alignment: .leading, spacing: 12) {
                List {
                    ForEach(subject.channels) { ch in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ch.name)
                                Text(ch.channelId)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                config.removeChannel(id: ch.channelId,
                                                     fromSubject: subjectID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove channel")
                        }
                        .padding(.vertical, 2)
                    }
                    if subject.channels.isEmpty {
                        Text("No channels yet — add one below.")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Add channel") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("YouTube URL, @handle, or channel ID",
                                      text: $input)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(resolve)
                            Button("Resolve", action: resolve)
                                .disabled(resolving || input.trimmingCharacters(
                                    in: .whitespaces).isEmpty)
                            if resolving { ProgressView().controlSize(.small) }
                        }
                        if let r = resolved {
                            HStack {
                                Label(r.title, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(r.channelId)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Button("Add \"\(r.title)\"") { add(r) }
                                    .buttonStyle(.borderedProminent)
                                Button("Cancel") { resolved = nil }
                            }
                        }
                        if let errorText {
                            Text(errorText).foregroundStyle(.red).font(.caption)
                        }
                    }
                    .padding(4)
                }
            }
            .padding()
            .navigationTitle(subject.name)
            .toolbar {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Subject", systemImage: "trash")
                }
                .help("Delete this subject (your vault notes are not touched)")
            }
            .confirmationDialog(
                "Delete subject “\(subject.name)”?",
                isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    config.removeSubject(id: subjectID)
                }
            } message: {
                Text("Only the configuration is removed — briefs already in your vault stay untouched.")
            }
        } else {
            Text("Select a subject").foregroundStyle(.secondary)
        }
    }

    private func resolve() {
        let query = input
        errorText = nil
        resolved = nil
        resolving = true
        Task {
            defer { resolving = false }
            do {
                resolved = try await ChannelResolver.resolve(query)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func add(_ r: ResolvedChannel) {
        if config.addChannel(BriefChannel(name: r.title, channelId: r.channelId),
                             toSubject: subjectID) {
            resolved = nil
            input = ""
            errorText = nil
        } else {
            errorText = "“\(r.title)” is already in this subject."
        }
    }
}
