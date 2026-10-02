import SwiftUI
import Combine
import AVFoundation
#if os(iOS)
import UIKit
import CoreMotion
#endif

#if os(iOS)
struct SettingsTabGearAnimationBridge: UIViewRepresentable {
    let settingsIndex: Int
    let spinToken: Int
    let isTabBarHidden: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(settingsIndex: settingsIndex)
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.update(from: uiView, spinToken: spinToken, isTabBarHidden: isTabBarHidden)
    }

    @MainActor
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.refresh(from: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.refresh(from: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private let settingsIndex: Int
        private weak var tabBar: UITabBar?
        private weak var tapRecognizer: UITapGestureRecognizer?
        private var currentSpinToken = 0
        private var lastAppliedSpinToken = 0
        private var currentTabBarHidden = false
        private var lastAppliedTabBarHidden: Bool?

        init(settingsIndex: Int) {
            self.settingsIndex = settingsIndex
        }

        func refresh(from view: UIView) {
            guard tabBar == nil else { return }
            update(from: view, spinToken: currentSpinToken, isTabBarHidden: currentTabBarHidden)
        }

        func update(from view: UIView, spinToken: Int, isTabBarHidden: Bool) {
            currentSpinToken = spinToken
            currentTabBarHidden = isTabBarHidden

            guard let tabBar = locateTabBar(from: view) else {
                detach()
                return
            }

            if self.tabBar !== tabBar {
                detach()
                self.tabBar = tabBar
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTabBarTap(_:)))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                tabBar.addGestureRecognizer(recognizer)
                tapRecognizer = recognizer
            }

            applyTabBarHiddenIfNeeded(hidden: isTabBarHidden, in: tabBar)

            guard spinToken != lastAppliedSpinToken else { return }
            lastAppliedSpinToken = spinToken
            animateSettingsGear()
        }

        @objc private func handleTabBarTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let tabBar,
                  let index = tabIndex(at: recognizer.location(in: tabBar), in: tabBar),
                  index == settingsIndex else {
                return
            }

            animateSettingsGear()
        }

        private func animateSettingsGear() {
            guard let tabBar else { return }

            let imageViews = tabIconImageViews(at: settingsIndex, in: tabBar)
            if !imageViews.isEmpty {
                for (i, iv) in imageViews.enumerated() {
                    animateRotation(on: iv.layer, key: "settingsGearSpin_\(i)")
                }
                return
            }

            if let tabItemView = tabItemView(in: tabBar, index: settingsIndex) {
                if let imageView = findImageView(in: tabItemView) {
                    animateRotation(on: imageView.layer, key: "settingsGearSpin")
                } else {
                    animateRotation(on: tabItemView.layer, key: "settingsGearSpinFallback")
                }
            }
        }

        private func tabIconImageViews(at index: Int, in tabBar: UITabBar) -> [UIImageView] {
            guard let platter = findMainContentPlatter(in: tabBar) else { return [] }
            var result: [UIImageView] = []
            for container in platter.subviews {
                guard !container.isHidden, container.alpha > 0.01 else { continue }
                let name = String(describing: type(of: container))
                guard name == "ContentView" || name == "SelectedContentView" else { continue }
                let buttons = container.subviews.filter {
                    !$0.isHidden && String(describing: type(of: $0)).contains("TabButton")
                }
                guard index >= 0, index < buttons.count else { continue }
                if let iv = firstVisibleSymbolImageView(in: buttons[index]) {
                    result.append(iv)
                }
            }
            return result
        }

        private func findMainContentPlatter(in tabBar: UITabBar) -> UIView? {
            for sub in tabBar.subviews {
                guard !sub.isHidden, sub.alpha > 0.01 else { continue }
                let name = String(describing: type(of: sub))
                guard name.contains("PlatterView") else { continue }
                let childNames = sub.subviews.map { String(describing: type(of: $0)) }
                if childNames.contains("SelectedContentView") && childNames.contains("ContentView") {
                    return sub
                }
            }
            return nil
        }

        private func firstVisibleSymbolImageView(in view: UIView) -> UIImageView? {
            if view.isHidden || view.alpha <= 0.01 { return nil }
            if let iv = view as? UIImageView, iv.image?.isSymbolImage == true {
                return iv
            }
            for sub in view.subviews {
                if let found = firstVisibleSymbolImageView(in: sub) { return found }
            }
            return nil
        }

        private func animateRotation(on layer: CALayer, key: String) {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.byValue = Double.pi * 2
            animation.duration = 0.52
            animation.isAdditive = true
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.removeAnimation(forKey: key)
            layer.add(animation, forKey: key)
        }

        private func detach() {
            if let tapRecognizer {
                tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
            }
            tapRecognizer = nil
            tabBar = nil
            lastAppliedTabBarHidden = nil
        }

        private func applyTabBarHiddenIfNeeded(hidden: Bool, in tabBar: UITabBar) {
            guard let tabBarController = locateTabBarController(from: tabBar) else { return }
            if lastAppliedTabBarHidden == hidden {
                return
            }
            let animate = lastAppliedTabBarHidden != nil
            tabBarController.setTabBarHidden(hidden, animated: animate)
            lastAppliedTabBarHidden = hidden
        }

        private func tabIndex(at point: CGPoint, in tabBar: UITabBar) -> Int? {
            guard let itemCount = tabBar.items?.count,
                  itemCount > 0 else {
                return nil
            }

            let itemWidth = tabBar.bounds.width / CGFloat(itemCount)
            guard itemWidth > 0 else { return nil }

            let rawIndex = Int(point.x / itemWidth)
            return min(max(rawIndex, 0), itemCount - 1)
        }

        private func locateTabBar(from view: UIView) -> UITabBar? {
            if let window = view.window,
               let tabBar = preferredTabBar(in: window) {
                return tabBar
            }

            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }

            for scene in scenes {
                for window in scene.windows.reversed() {
                    if let tabBar = preferredTabBar(in: window) {
                        return tabBar
                    }
                }
            }

            return nil
        }

        private func preferredTabBar(in root: UIView) -> UITabBar? {
            let candidates = findTabBars(in: root)
                .filter { $0.bounds.width > 0 && $0.bounds.height > 0 }

            return candidates.max { lhs, rhs in
                lhs.convert(lhs.bounds, to: nil).maxY < rhs.convert(rhs.bounds, to: nil).maxY
            }
        }

        private func locateTabBarController(from tabBar: UITabBar) -> UITabBarController? {
            var responder: UIResponder? = tabBar
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return nil
        }

        private func findTabBars(in view: UIView) -> [UITabBar] {
            var result: [UITabBar] = []
            if let tabBar = view as? UITabBar {
                result.append(tabBar)
            }

            for subview in view.subviews {
                result.append(contentsOf: findTabBars(in: subview))
            }

            return result
        }

        private func tabItemView(in tabBar: UITabBar, index: Int) -> UIView? {
            guard let itemCount = tabBar.items?.count,
                  itemCount > 0,
                  index >= 0,
                  index < itemCount else {
                return nil
            }

            let targetX = (CGFloat(index) + 0.5) * tabBar.bounds.width / CGFloat(itemCount)
            let targetPoint = CGPoint(x: targetX, y: tabBar.bounds.midY)

            let candidates = tabBar.subviews.filter {
                !$0.isHidden &&
                $0.alpha > 0.01 &&
                $0.bounds.width > 12 &&
                $0.bounds.height > 12 &&
                $0.bounds.width < tabBar.bounds.width * 0.9
            }

            let containing = candidates.filter { $0.frame.contains(targetPoint) }
            if let best = containing.min(by: { area($0.bounds) < area($1.bounds) }) {
                return best
            }

            return candidates.min(by: { abs($0.frame.midX - targetX) < abs($1.frame.midX - targetX) })
        }

        private func area(_ rect: CGRect) -> CGFloat {
            rect.width * rect.height
        }

        private func findImageView(in view: UIView) -> UIImageView? {
            var imageViews: [UIImageView] = []
            collectImageViews(in: view, into: &imageViews)
            return imageViews.max(by: { area($0.bounds) < area($1.bounds) })
        }

        private func collectImageViews(in view: UIView, into imageViews: inout [UIImageView]) {
            if let imageView = view as? UIImageView,
               imageView.bounds.width > 0,
               imageView.bounds.height > 0 {
                imageViews.append(imageView)
            }

            for subview in view.subviews {
                collectImageViews(in: subview, into: &imageViews)
            }
        }

    }
}

extension SettingsTabGearAnimationBridge.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
