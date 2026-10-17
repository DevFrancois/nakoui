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

            let expectedWidth = width >= 584 ? (width - 24) / 2 : min(width, 600)
            try #require(await eventually {
                guard let prompt = record.frames["prompt"], let answers = record.frames["answers"] else { return false }
                return abs(prompt.width - expectedWidth) < 0.5 && abs(answers.width - expectedWidth) < 0.5
                    && record.taskStarts["prompt"] == 1 && record.taskStarts["answers"] == 1
            })

            let prompt = try #require(record.frames["prompt"])
            let answers = try #require(record.frames["answers"])
            if width >= 584 {
                #expect(abs(prompt.minY - answers.minY) < 0.5)
                #expect(abs(answers.minX - prompt.maxX - 24) < 0.5)
            } else {
                #expect(abs(prompt.minX - answers.minX) < 0.5)
                #expect(abs(answers.minY - prompt.maxY - 24) < 0.5)
            }
            #expect(prompt.minX >= -0.5 && answers.maxX <= width + 0.5)
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

        try #require(await eventually {
            guard let prompt = record.frames["prompt"], let answers = record.frames["answers"] else { return false }
            return abs(prompt.width - 600) < 0.5 && answers.minY > prompt.maxY
        })
        let prompt = try #require(record.frames["prompt"])
        let answers = try #require(record.frames["answers"])
        #expect(abs(prompt.midX - 450) < 0.5)
        #expect(abs(answers.midX - 450) < 0.5)
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
            .coordinateSpace(name: "quizRound")
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
                proxy.frame(in: .named("quizRound"))
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
