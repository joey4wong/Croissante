import SwiftUI
#if os(iOS)
import UIKit
import CoreMotion
#endif

#if os(iOS)
struct AppIconPhysicsPicker: UIViewRepresentable {
    let icons: [AppIconManager.AppIcon]
    let currentIconID: String
    let isDarkMode: Bool
    let isApplying: Bool
    let layout: AppIconPickerLayout
    let onTapIcon: (AppIconManager.AppIcon) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> AppIconPhysicsContainerView {
        let view = AppIconPhysicsContainerView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: AppIconPhysicsContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyCurrentState(animated: true)
    }

    final class Coordinator: NSObject, UICollisionBehaviorDelegate {
        var parent: AppIconPhysicsPicker
        weak var container: AppIconPhysicsContainerView?
        private var animator: UIDynamicAnimator?
        private let gravityBehavior = UIGravityBehavior()
        private let collisionBehavior = UICollisionBehavior()
        private let itemBehavior = UIDynamicItemBehavior()
        private let motionManager = CMMotionManager()
        private var tilesByID: [String: AppIconPhysicsTileView] = [:]
        private var orderedIDs: [String] = []
        private var didPlaceInitialDrop = false
        private var lastContainerBoundsSize: CGSize = .zero
        private var lastCollisionSoundTime: CFTimeInterval = 0
        private var initialDropStartTime: CFTimeInterval = 0
        private var entranceDropActivationToken: Int = 0
        private var hasActivatedEntranceDrop = false
        private let collisionVelocityThreshold: CGFloat = 140
        private let collisionSoundCooldown: CFTimeInterval = 0.14
        private let settledGravityMagnitude: CGFloat = 1.25
        private let defaultDropGravity = CGVector(dx: 0, dy: 1)
        private let minimumEntranceGravityY: CGFloat = 0.68
        private let maximumEntranceGravityX: CGFloat = 0.08
        private let entranceAssistDuration: CFTimeInterval = 0.55
        private let entranceActivationDelay: CFTimeInterval = 0.18
        private let initialDropVelocity: CGFloat = 210
        private var filteredGravity: CGVector
        private let gravitySmoothing: CGFloat = 0.16

        init(parent: AppIconPhysicsPicker) {
            self.parent = parent
            self.filteredGravity = defaultDropGravity
        }

        func attach(to container: AppIconPhysicsContainerView) {
            self.container = container
            container.coordinator = self
            container.clipsToBounds = true
            container.backgroundColor = .clear
            applyCurrentState(animated: false)
            kickstartInitialDropIfNeeded()
            startMotionUpdatesIfNeeded()
            FeedbackService.prepareInteractive()
        }

        func applyCurrentState(animated: Bool) {
            guard let container else { return }
            ensureAnimatorAndTileState(in: container)
            restartEntranceIfNeeded(clampActiveTiles: animated)
        }

        func containerDidLayout() {
            guard let container else { return }
            let bounds = container.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            ensureAnimatorAndTileState(in: container)

            let sizeChanged = bounds.size != lastContainerBoundsSize
            lastContainerBoundsSize = bounds.size
            updateCollisionBounds(in: container)
            restartEntranceIfNeeded(clampActiveTiles: sizeChanged)
        }

        func stopMotionUpdates() {
            entranceDropActivationToken += 1
            hasActivatedEntranceDrop = false
            motionManager.stopDeviceMotionUpdates()
        }

        func kickstartInitialDropIfNeeded() {
            guard let container else { return }
            let bounds = container.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            if animator == nil {
                setupAnimatorIfNeeded(referenceView: container)
            }

            ensureAnimatorAndTileState(in: container)

            guard needsEntranceGravityAssist() else { return }

            filteredGravity = defaultDropGravity
            gravityBehavior.gravityDirection = filteredGravity
            didPlaceInitialDrop = placeTilesAtTop()
        }

        private func ensureAnimatorAndTileState(in container: AppIconPhysicsContainerView) {
            if animator == nil, container.bounds.width > 0, container.bounds.height > 0 {
                setupAnimatorIfNeeded(referenceView: container)
            }
            syncTiles(in: container)
            updateTileStates()
        }

        private func restartEntranceIfNeeded(clampActiveTiles: Bool) {
            if !didPlaceInitialDrop || !hasActivatedEntranceDrop {
                didPlaceInitialDrop = placeTilesAtTop()
            } else if clampActiveTiles {
                keepTilesInsideBounds()
            }
        }

        private func setupAnimatorIfNeeded(referenceView: UIView) {
            guard animator == nil else { return }
            let animator = UIDynamicAnimator(referenceView: referenceView)

            gravityBehavior.magnitude = 0
            gravityBehavior.gravityDirection = filteredGravity
            collisionBehavior.collisionDelegate = self
            updateCollisionBounds(in: referenceView)

            itemBehavior.elasticity = 0.83
            itemBehavior.friction = 0.06
            itemBehavior.resistance = 0.08
            itemBehavior.angularResistance = 0.18
            itemBehavior.allowsRotation = true
            itemBehavior.density = 0.78

            animator.addBehavior(gravityBehavior)
            animator.addBehavior(collisionBehavior)
            animator.addBehavior(itemBehavior)
            self.animator = animator
        }

        private func syncTiles(in container: UIView) {
            let newOrderedIDs = parent.icons.map(\.id)
            let newIDSet = Set(newOrderedIDs)

            for (id, tile) in tilesByID where !newIDSet.contains(id) {
                gravityBehavior.removeItem(tile)
                collisionBehavior.removeItem(tile)
                itemBehavior.removeItem(tile)
                tile.removeFromSuperview()
                tilesByID.removeValue(forKey: id)
            }

            for (index, icon) in parent.icons.enumerated() {
                if let tile = tilesByID[icon.id] {
                    tile.updateIcon(icon)
                    continue
                }

                let tile = AppIconPhysicsTileView(icon: icon, tileSize: parent.layout.tileSize)
                if canPlaceInitialGrid(in: container.bounds) {
                    tile.center = initialDropCenter(
                        for: index,
                        in: container.bounds,
                        totalCount: newOrderedIDs.count
                    )
                }
                tile.addTarget(self, action: #selector(handleTileTap(_:)), for: .touchUpInside)
                container.addSubview(tile)
                tilesByID[icon.id] = tile
                gravityBehavior.addItem(tile)
                collisionBehavior.addItem(tile)
                itemBehavior.addItem(tile)
            }

            orderedIDs = newOrderedIDs
        }

        private func updateTileStates() {
            for icon in parent.icons {
                guard let tile = tilesByID[icon.id] else { continue }
                let isSelected = parent.currentIconID == icon.id
                let isLocked = false
                let isDisabled = parent.isApplying || (!isLocked && isSelected)

                tile.applyState(
                    isSelected: isSelected,
                    isLocked: isLocked,
                    isDarkMode: parent.isDarkMode,
                    isDisabled: isDisabled
                )
                tile.isUserInteractionEnabled = !isDisabled
            }
        }

        @discardableResult
        private func placeTilesAtTop() -> Bool {
            guard let container else { return false }
            guard canPlaceInitialGrid(in: container.bounds) else { return false }

            let width = container.bounds.width
            let height = container.bounds.height
            guard width > 0, height > 0 else { return false }

            entranceDropActivationToken += 1
            let activationToken = entranceDropActivationToken
            hasActivatedEntranceDrop = false
            gravityBehavior.magnitude = 0
            filteredGravity = defaultDropGravity
            gravityBehavior.gravityDirection = filteredGravity

            for (index, id) in orderedIDs.enumerated() {
                guard let tile = tilesByID[id] else { continue }
                tile.center = initialDropCenter(
                    for: index,
                    in: container.bounds,
                    totalCount: orderedIDs.count
                )

                let linearVelocity = itemBehavior.linearVelocity(for: tile)
                itemBehavior.addLinearVelocity(
                    CGPoint(x: -linearVelocity.x, y: -linearVelocity.y),
                    for: tile
                )
                let angularVelocity = itemBehavior.angularVelocity(for: tile)
                itemBehavior.addAngularVelocity(-angularVelocity, for: tile)

                animator?.updateItem(usingCurrentState: tile)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + entranceActivationDelay) { [weak self] in
                guard let self else { return }
                guard self.entranceDropActivationToken == activationToken else { return }

                self.hasActivatedEntranceDrop = true
                self.initialDropStartTime = CFAbsoluteTimeGetCurrent()
                self.filteredGravity = self.defaultDropGravity
                self.gravityBehavior.gravityDirection = self.filteredGravity
                self.gravityBehavior.magnitude = self.settledGravityMagnitude

                for id in self.orderedIDs {
                    guard let tile = self.tilesByID[id] else { continue }
                    self.itemBehavior.addLinearVelocity(
                        CGPoint(x: 0, y: self.initialDropVelocity),
                        for: tile
                    )
                    self.animator?.updateItem(usingCurrentState: tile)
                }
            }

            return true
        }

        private func canPlaceInitialGrid(in bounds: CGRect) -> Bool {
            let minimumWidth = parent.layout.tileSize * 3 + parent.layout.initialDropSpacing * 2 + parent.layout.contentInset
            let minimumHeight = parent.layout.tileSize * 3 + parent.layout.initialDropSpacing * 2
            return bounds.width >= minimumWidth && bounds.height >= minimumHeight
        }

        private func initialDropCenter(for index: Int, in bounds: CGRect, totalCount: Int) -> CGPoint {
            let tileSize = parent.layout.tileSize
            let halfSize = tileSize / 2
            let columns = min(3, max(totalCount, 1))
            let preferredSpacing = parent.layout.initialDropSpacing
            let availableRowWidth = bounds.width - parent.layout.contentInset
            let maximumSpacing: CGFloat

            if columns > 1 {
                maximumSpacing = max(
                    (availableRowWidth - CGFloat(columns) * tileSize) / CGFloat(columns - 1),
                    0
                )
            } else {
                maximumSpacing = 0
            }

            let spacing = min(preferredSpacing, maximumSpacing)
            let col = index % columns
            let row = index / columns
            let itemsInRow = min(totalCount - row * columns, columns)
            let rowWidth = CGFloat(itemsInRow) * tileSize + CGFloat(max(itemsInRow - 1, 0)) * spacing
            let startX = (bounds.width - rowWidth) / 2 + halfSize
            let x = startX + CGFloat(col) * (tileSize + spacing)
            let y = halfSize + parent.layout.initialDropTopInset + CGFloat(row) * (tileSize + spacing)

            return CGPoint(x: x, y: y)
        }

        private func updateCollisionBounds(in container: UIView) {
            collisionBehavior.setTranslatesReferenceBoundsIntoBoundary(
                with: .zero
            )
        }

        private func needsEntranceGravityAssist() -> Bool {
            guard !orderedIDs.isEmpty else { return false }
            return orderedIDs.allSatisfy { id in
                guard let tile = tilesByID[id] else { return true }
                return tile.frame.maxY <= 0
            }
        }

        private func shouldApplyEntranceGravityAssist() -> Bool {
            if !hasActivatedEntranceDrop {
                return true
            }
            if needsEntranceGravityAssist() {
                return true
            }
            return CFAbsoluteTimeGetCurrent() - initialDropStartTime < entranceAssistDuration
        }

        private func keepTilesInsideBounds() {
            guard let container else { return }
            let bounds = container.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            let halfSize = parent.layout.tileSize / 2
            for id in orderedIDs {
                guard let tile = tilesByID[id] else { continue }
                var center = tile.center
                center.x = min(max(center.x, halfSize), bounds.width - halfSize)
                center.y = min(max(center.y, halfSize), bounds.height - halfSize)
                if center != tile.center {
                    tile.center = center
                    animator?.updateItem(usingCurrentState: tile)
                }
            }
        }

        private func startMotionUpdatesIfNeeded() {
            guard motionManager.isDeviceMotionAvailable else { return }
            guard !motionManager.isDeviceMotionActive else { return }

            motionManager.deviceMotionUpdateInterval = 1.0 / 45.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                self.updateGravity(with: motion.gravity)
            }
        }

        private func updateGravity(with gravity: CMAcceleration) {
            var dx = gravity.x
            var dy = -gravity.y

            if let orientation = container?.window?.windowScene?.effectiveGeometry.interfaceOrientation {
                switch orientation {
                case .portrait:
                    dx = gravity.x
                    dy = -gravity.y
                case .portraitUpsideDown:
                    dx = -gravity.x
                    dy = gravity.y
                case .landscapeLeft:
                    dx = gravity.y
                    dy = gravity.x
                case .landscapeRight:
                    dx = -gravity.y
                    dy = -gravity.x
                default:
                    break
                }
            }

            let a = gravitySmoothing
            filteredGravity.dx += a * (CGFloat(dx) - filteredGravity.dx)
            filteredGravity.dy += a * (CGFloat(dy) - filteredGravity.dy)

            if shouldApplyEntranceGravityAssist() {
                filteredGravity.dx = max(min(filteredGravity.dx, maximumEntranceGravityX), -maximumEntranceGravityX)
                filteredGravity.dy = max(filteredGravity.dy, minimumEntranceGravityY)
            }

            gravityBehavior.gravityDirection = filteredGravity
        }

        @objc
        private func handleTileTap(_ sender: AppIconPhysicsTileView) {
            parent.onTapIcon(sender.icon)
        }

        func collisionBehavior(
            _ behavior: UICollisionBehavior,
            beganContactFor item1: UIDynamicItem,
            with item2: UIDynamicItem,
            at p: CGPoint
        ) {
            emitCollisionSoundIfNeeded(item1: item1, item2: item2)
        }

        func collisionBehavior(
            _ behavior: UICollisionBehavior,
            beganContactFor item: UIDynamicItem,
            withBoundaryIdentifier identifier: NSCopying?,
            at p: CGPoint
        ) {
            emitCollisionSoundIfNeeded(item1: item, item2: nil)
        }

        private func emitCollisionSoundIfNeeded(item1: UIDynamicItem, item2: UIDynamicItem?) {
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastCollisionSoundTime >= collisionSoundCooldown else { return }

            let v1 = itemBehavior.linearVelocity(for: item1)
            let velocityMagnitude: CGFloat
            if let item2 {
                let v2 = itemBehavior.linearVelocity(for: item2)
                velocityMagnitude = hypot(v1.x - v2.x, v1.y - v2.y)
            } else {
                velocityMagnitude = hypot(v1.x, v1.y)
            }

            guard velocityMagnitude >= collisionVelocityThreshold else { return }

            lastCollisionSoundTime = now
            FeedbackService.gearTick()
        }
    }
}

final class AppIconPhysicsContainerView: UIView {
    weak var coordinator: AppIconPhysicsPicker.Coordinator?

    private func requestStableLayoutPass() {
        setNeedsLayout()
        superview?.setNeedsLayout()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutIfNeeded()
            self.superview?.layoutIfNeeded()
            self.coordinator?.containerDidLayout()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            coordinator?.stopMotionUpdates()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            requestStableLayoutPass()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.requestStableLayoutPass()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        coordinator?.containerDidLayout()
    }
}

final class AppIconPhysicsTileView: UIControl {
    private(set) var icon: AppIconManager.AppIcon
    private let imageView = UIImageView()
    private let lockBadgeView = UIView()
    private let lockImageView = UIImageView()
    private let cornerRadius: CGFloat = 20

    init(icon: AppIconManager.AppIcon, tileSize: CGFloat) {
        self.icon = icon
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: tileSize, height: tileSize)))

        imageView.image = UIImage(named: icon.previewAssetName)
        imageView.contentMode = .scaleAspectFill
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.layer.cornerRadius = cornerRadius
        imageView.layer.masksToBounds = true
        addSubview(imageView)

        layer.cornerRadius = cornerRadius
        layer.borderWidth = 1
        layer.masksToBounds = true

        lockImageView.image = UIImage(systemName: "lock.fill")
        lockImageView.contentMode = .scaleAspectFit
        lockBadgeView.addSubview(lockImageView)
        addSubview(lockBadgeView)

        isExclusiveTouch = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let badgeSize: CGFloat = 22
        let inset: CGFloat = 6
        lockBadgeView.frame = CGRect(
            x: bounds.width - badgeSize - inset,
            y: inset,
            width: badgeSize,
            height: badgeSize
        )
        lockBadgeView.layer.cornerRadius = badgeSize / 2
        lockImageView.frame = lockBadgeView.bounds.insetBy(dx: 5, dy: 5)
    }

    func updateIcon(_ icon: AppIconManager.AppIcon) {
        guard self.icon.id != icon.id || self.icon.previewAssetName != icon.previewAssetName else { return }
        self.icon = icon
        imageView.image = UIImage(named: icon.previewAssetName)
    }

    func applyState(isSelected: Bool, isLocked: Bool, isDarkMode: Bool, isDisabled: Bool) {
        if isSelected {
            layer.borderColor = (isDarkMode ? UIColor.white.withAlphaComponent(0.60) : UIColor.black.withAlphaComponent(0.35)).cgColor
            layer.borderWidth = 1.5
        } else {
            layer.borderColor = (isDarkMode ? UIColor.white.withAlphaComponent(0.16) : UIColor.black.withAlphaComponent(0.10)).cgColor
            layer.borderWidth = 1.0
        }

        alpha = (isDisabled && !isSelected) ? 0.6 : 1.0
        lockBadgeView.isHidden = !isLocked
        lockBadgeView.backgroundColor = isDarkMode ? UIColor.black.withAlphaComponent(0.68) : UIColor.white.withAlphaComponent(0.90)
        lockImageView.tintColor = isDarkMode ? UIColor.white.withAlphaComponent(0.92) : UIColor.black.withAlphaComponent(0.86)
    }
}
#endif
