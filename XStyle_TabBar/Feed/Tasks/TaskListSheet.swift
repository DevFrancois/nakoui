import SwiftUI

/// A modal listing every remaining task. Each card's button completes its
/// task, and its close button dismisses it.
struct TaskListSheet: View {
    let taskList: ForYouTaskList

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(taskList.remaining) { task in
                        TaskCard(task: task) {
                            dismissTask(task)
                        } content: {
                            TaskSummary(task: task) {
                                Button(task.actionTitle) {
                                    complete(task)
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .padding(.top, 8)
                            }
                            .padding()
                        }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding()
            }
            .overlay {
                if taskList.remaining.isEmpty {
                    ContentUnavailableView(
                        "All Done",
                        systemImage: "checkmark.circle",
                        description: Text("You've finished every task.")
                    )
                }
            }
            .background(Color(.taskSheetBackground))
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                }
            }
            .sensoryFeedback(.success, trigger: taskList.completedCount)
            .sensoryFeedback(.impact(weight: .light), trigger: taskList.dismissedCount)
        }
    }

    private func complete(_ task: ForYouTask) {
        withAnimation(.smooth) {
            taskList.complete(task)
        }
    }

    private func dismissTask(_ task: ForYouTask) {
        withAnimation(.smooth) {
            taskList.dismiss(task)
        }
    }
}

#Preview {
    TaskListSheet(taskList: ForYouTaskList())
}
