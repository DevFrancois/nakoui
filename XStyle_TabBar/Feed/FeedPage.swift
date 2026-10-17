import SwiftUI

/// One tab's scrolling page: placeholder posts, or the quiz hub for the Quizz
/// tab. It scrolls beneath the top menu, under the pager's soft edge.
struct FeedPage: View {
    let tab: AppTab
    /// Shared with article destinations for their zoom transitions.
    let zoomNamespace: Namespace.ID
    /// The For you tasks. Owned by `ContentView`, so the side menu can reach
    /// them too.
    let taskList: ForYouTaskList

    @State private var presentedDestination: ForYouDestination?
    @State private var isShowingTasks = false

    private static let postCount = 40

    var body: some View {
        // One vertical scroll view per page: the pager reads its offset to
        // collapse the logo row, so the quiz hub nests no scroll views of its own.
        ScrollView(.vertical) {
            Group {
                if tab == .quizz {
                    QuizHub()
                } else {
                    LazyVStack(spacing: 0) {
                        if tab == .bookmarks {
                            // Always present, so the last card lifts away like
                            // the others instead of fading out with the stack.
                            TaskStack(tasks: taskList.stacked, onOpen: showTasks, onDismiss: dismissStackedTask)

                            WhatsNewRow(tint: tab.tint) { presentedDestination = .whatsNew }

                            ForYouTileGrid { destination in
                                presentedDestination = destination
                            }
                        }

                        ForEach(1...Self.postCount, id: \.self) { number in
                            if tab == .articles {
                                ArticleRow(article: .placeholder(number: number, tint: tab.tint), namespace: zoomNamespace)
                            } else {
                                FeedRow(tab: tab, number: number)
                            }
                        }
                    }
                }
            }
            .padding(.top, TopMenuMetrics.contentTopPadding)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $presentedDestination, content: ForYouDetailSheet.init)
        // A tap on a card, not the sheet's dismissal.
        .sensoryFeedback(trigger: presentedDestination) { _, newValue in
            newValue == nil ? nil : .impact(flexibility: .soft)
        }
        .sheet(isPresented: $isShowingTasks, onDismiss: revealTaskChanges) {
            TaskListSheet(taskList: taskList)
        }
        .sensoryFeedback(trigger: isShowingTasks) { _, isShowing in
            isShowing ? .impact(flexibility: .soft) : nil
        }
        .sensoryFeedback(trigger: taskList.stacked.count) { oldCount, newCount in
            newCount < oldCount ? .impact(weight: .light) : nil
        }
    }

    private func showTasks() {
        isShowingTasks = true
    }

    private func dismissStackedTask(_ task: ForYouTask) {
        withAnimation(TaskMetrics.stackAnimation) {
            taskList.dismiss(task)
            taskList.updateStack()
        }
    }

    /// Runs once the sheet has closed, so the stack's update plays in view.
    private func revealTaskChanges() {
        withAnimation(TaskMetrics.stackAnimation) {
            taskList.updateStack()
        }
    }
}
