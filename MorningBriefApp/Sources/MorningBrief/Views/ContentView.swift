import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            DashboardView()
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
    }
}
