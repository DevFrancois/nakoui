import SwiftUI
import UIKit

/// A noninteractive child of the navigation root. UIKit appearance callbacks
/// gate capture independently from SwiftUI's earlier path/onAppear updates.
struct TabBarRootLifecycleObserver: UIViewControllerRepresentable {
    let source: TabBarReflectionSource
    let pathIsEmpty: Bool

    func makeUIViewController(context: Context) -> Observer {
        source.setPathIsEmpty(pathIsEmpty)
        return Observer(source: source)
    }

    func updateUIViewController(_ controller: Observer, context: Context) {
        source.setPathIsEmpty(pathIsEmpty)
    }

    final class Observer: UIViewController {
        private let source: TabBarReflectionSource
        private var appearanceGeneration: UInt64?

        init(source: TabBarReflectionSource) {
            self.source = source
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let generation = source.rootWillAppear(view)
            appearanceGeneration = generation
            // A cancelled push restores its FROM controller. Only cancellation
            // of a return whose TO controller contains us means "covered".
            let isReturningDestination = transitionCoordinator?.viewController(forKey: .to)
                .map { destination in
                    var controller: UIViewController? = self
                    while let current = controller {
                        if current === destination { return true }
                        controller = current.parent
                    }
                    return false
                } ?? false
            transitionCoordinator?.animate(alongsideTransition: nil) { [weak source] context in
                if context.isCancelled, isReturningDestination {
                    source?.rootReturnCancelled(generation: generation)
                }
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let appearanceGeneration { source.rootDidAppear(generation: appearanceGeneration) }
        }

        override func viewIsAppearing(_ animated: Bool) {
            super.viewIsAppearing(animated)
            source.rootLayoutChanged()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            appearanceGeneration = nil
            source.rootWillDisappear()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            source.rootLayoutChanged()
        }
    }
}
