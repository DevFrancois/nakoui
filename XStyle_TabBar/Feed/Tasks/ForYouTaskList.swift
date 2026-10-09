import Observation

/// The For you feed's tasks, shared by the task stack and the task sheet. It
/// has no UI, so it can be unit tested.
@Observable
final class ForYouTaskList {
    /// Every task still to do.
    private(set) var remaining: [ForYouTask]
    /// What the For you stack shows. It holds still while the task sheet is
    /// open and catches up once it closes, so the stack's animation is seen.
    private(set) var stacked: [ForYouTask]
    /// Bumped by each outcome, to trigger its haptic.
    private(set) var completedCount = 0
    private(set) var dismissedCount = 0

    init(tasks: [ForYouTask] = ForYouTask.samples) {
        remaining = tasks
        stacked = tasks
    }

    func complete(_ task: ForYouTask) {
        guard remove(task) else { return }
        completedCount += 1
    }

    func dismiss(_ task: ForYouTask) {
        guard remove(task) else { return }
        dismissedCount += 1
    }

    /// Brings the stack up to date with the remaining tasks.
    func updateStack() {
        stacked = remaining
    }

    #if DEBUG
    /// Brings every task back, for testing the stack again. Compiled into
    /// debug builds only.
    func reset(to tasks: [ForYouTask] = ForYouTask.samples) {
        remaining = tasks
        stacked = tasks
    }
    #endif

    private func remove(_ task: ForYouTask) -> Bool {
        guard let index = remaining.firstIndex(where: { $0.id == task.id }) else { return false }
        remaining.remove(at: index)
        return true
    }
}
