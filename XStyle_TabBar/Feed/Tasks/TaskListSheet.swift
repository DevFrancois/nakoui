import SwiftUI

/// A modal listing every remaining task. Each card's button opens the task's
/// own modal, and its close button dismisses the task. Once no task is left,
/// the sheet closes itself.
struct TaskListSheet: View {
    let taskList: ForYouTaskList

    /// The cards on show. They follow the task list, except that the last
    /// card stays while the sheet closes, rather than leaving it empty.
    @State private var shownTasks: [ForYouTask]
    /// The task whose own modal is open.
    @State private var openTask: ForYouTask?
    /// Marked as done in its modal; completed once that modal has closed, so
    /// its card is seen leaving.
    @State private var finishedTask: ForYouTask?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(taskList: ForYouTaskList) {
        self.taskList = taskList
        _shownTasks = State(initialValue: taskList.remaining)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TaskMetrics.cardSpacing) {
                    ForEach(shownTasks) { task in
                        TaskCard(task: task, onDismiss: { dismissTask(task) }) {
                            TaskSummary(task: task) {
                                Button(task.actionTitle) {
                                    open(task)
                                }
                                .buttonStyle(TaskActionButtonStyle())
                                // Less than the gap wanted: the button's tap
                                // area adds some above its capsule.
                                .padding(.top, 2)
                            }
                            .padding()
                        }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding()
            }
            .background(Color(.taskSheetBackground))
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                }
            }
            .sheet(item: $openTask, onDismiss: completeFinishedTask) { task in
                TaskDetailSheet(task: task) {
                    finishedTask = task
                }
            }
            .sensoryFeedback(trigger: openTask?.id) { _, newID in
                newID == nil ? nil : .impact(flexibility: .soft)
            }
            .sensoryFeedback(.success, trigger: taskList.completedCount)
            .sensoryFeedback(.impact(weight: .light), trigger: taskList.dismissedCount)
        }
    }

    private func open(_ task: ForYouTask) {
        openTask = task
    }

    private func dismissTask(_ task: ForYouTask) {
        taskList.dismiss(task)
        showRemainingTasks()
    }

    private func completeFinishedTask() {
        guard let finishedTask else { return }
        self.finishedTask = nil
        taskList.complete(finishedTask)
        showRemainingTasks()
    }

    /// Animates the cards to the remaining tasks, or closes the sheet once
    /// none are left, its last card still showing as it slides away.
    private func showRemainingTasks() {
        if taskList.remaining.isEmpty {
            dismiss()
        } else {
            withAnimation(TaskMetrics.stackAnimation) {
                shownTasks = taskList.remaining
            }
        }
    }
}

#Preview {
    TaskListSheet(taskList: ForYouTaskList())
}
