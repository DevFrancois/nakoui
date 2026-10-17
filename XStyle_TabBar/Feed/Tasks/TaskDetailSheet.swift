import SwiftUI

/// The modal a task's action button opens: a placeholder for the task's own
/// flow, which the user can mark as done or close to come back to later.
struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: ForYouTask
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TaskMetrics.cardSpacing) {
                    Image(systemName: task.symbol)
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(task.tint)
                        .accessibilityHidden(true)

                    Text(task.title)
                        .font(.title2.bold())

                    Text(task.message)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .safeAreaBar(edge: .bottom) {
                Button(action: complete) {
                    Text("Mark as Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.taskSheetBackground))
            .navigationTitle(task.actionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func complete() {
        onComplete()
        dismiss()
    }
}

#Preview {
    TaskDetailSheet(task: ForYouTask.samples[0]) {}
}
