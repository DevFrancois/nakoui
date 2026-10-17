import SwiftUI
import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct QuizAdaptiveLayoutTests {
    @Test("Quiz columns reflow without replacing their controls or restarting their work")
    func resizingKeepsPromptAndAnswerIdentity() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }

        let record = QuizLayoutRecord()
        let host = UIHostingController(rootView: QuizLayoutFixture(record: record).environment(\.dynamicTypeSize, .large))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)

        for width: CGFloat in [900, 393, 736, 320, 900] {
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 700)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            // The quiz lays out in the space the device's rail leaves free.
            let safeArea = host.view.bounds.inset(by: host.view.safeAreaInsets)
            let spacing = QuizRoundLayout.defaultSpacing
            let roundWidth = min(safeArea.width, QuizMetrics.expandedContentMaxWidth)
            let usesColumns = roundWidth >= QuizRoundLayout.baseMinimumColumnWidth * 2 + spacing
            let expectedWidth = usesColumns
                ? (roundWidth - spacing) / 2
                : min(roundWidth, QuizMetrics.contentMaxWidth)
            try #require(await eventually {
                guard let prompt = record.frames["prompt"], let answers = record.frames["answers"] else { return false }
                return prompt.width == expectedWidth && answers.width == expectedWidth
                    && record.taskStarts["prompt"] == 1 && record.taskStarts["answers"] == 1
            }, "Width \(width), safe area \(safeArea): expected columns \(expectedWidth) wide, got \(record.frames)")

            let prompt = try #require(record.frames["prompt"])
            let answers = try #require(record.frames["answers"])
            if usesColumns {
                #expect(prompt.minY == answers.minY)
                #expect(answers.minX - prompt.maxX == spacing)
            } else {
                #expect(prompt.minX == answers.minX)
                #expect(answers.minY - prompt.maxY == spacing)
            }
            #expect(prompt.minX >= safeArea.minX && answers.maxX <= safeArea.maxX)
            #expect(record.identities["prompt"]?.count == 1)
            #expect(record.identities["answers"]?.count == 1)
            #expect(record.taskStarts["prompt"] == 1)
            #expect(record.taskStarts["answers"] == 1)
        }
    }

    @Test("Accessibility text retains a single readable quiz column in a wide window")
    func accessibilityStacksWideQuiz() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }

        let record = QuizLayoutRecord()
        let host = UIHostingController(rootView: QuizLayoutFixture(record: record).environment(\.dynamicTypeSize, .accessibility3))
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        host.view.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        host.view.layoutIfNeeded()

        // Centered in the space the device's rail leaves free.
        let safeArea = host.view.bounds.inset(by: host.view.safeAreaInsets)
        let expectedWidth = min(safeArea.width, QuizMetrics.contentMaxWidth)
        try #require(await eventually {
            guard let prompt = record.frames["prompt"], let answers = record.frames["answers"] else { return false }
            return prompt.width == expectedWidth && answers.minY > prompt.maxY
        }, "Safe area \(safeArea): expected a column \(expectedWidth) wide, got \(record.frames)")
        let prompt = try #require(record.frames["prompt"])
        let answers = try #require(record.frames["answers"])
        #expect(prompt.midX == safeArea.midX)
        #expect(answers.midX == safeArea.midX)
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor
private final class QuizLayoutRecord {
    var frames: [String: CGRect] = [:]
    var identities: [String: Set<UUID>] = [:]
    var taskStarts: [String: Int] = [:]
}

private struct QuizLayoutFixture: View {
    let record: QuizLayoutRecord

    var body: some View {
        ScrollView {
            QuizRound {
                QuizLayoutProbe(name: "prompt", height: 120, record: record)
            } answers: {
                QuizLayoutProbe(name: "answers", height: 240, record: record)
            }
        }
    }
}

private struct QuizLayoutProbe: View {
    let name: String
    let height: CGFloat
    let record: QuizLayoutRecord
    @State private var identity = UUID()

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onGeometryChange(for: CGRect.self) { proxy in
                // The host fills the window, so these are the host's coordinates.
                proxy.frame(in: .global)
            } action: { frame in
                record.frames[name] = frame
            }
            .onAppear {
                record.identities[name, default: []].insert(identity)
            }
            .task {
                record.taskStarts[name, default: 0] += 1
            }
    }
}
