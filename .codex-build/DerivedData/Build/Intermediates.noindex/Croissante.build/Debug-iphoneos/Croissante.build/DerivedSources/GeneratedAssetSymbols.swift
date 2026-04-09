import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "AppIconPreview-08" asset catalog image resource.
    static let appIconPreview08 = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-08", bundle: resourceBundle)

    /// The "AppIconPreview-09" asset catalog image resource.
    static let appIconPreview09 = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-09", bundle: resourceBundle)

    /// The "AppIconPreview-ClassicDark" asset catalog image resource.
    static let appIconPreviewClassicDark = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-ClassicDark", bundle: resourceBundle)

    /// The "AppIconPreview-ClassicLight" asset catalog image resource.
    static let appIconPreviewClassicLight = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-ClassicLight", bundle: resourceBundle)

    /// The "AppIconPreview-Crystal" asset catalog image resource.
    static let appIconPreviewCrystal = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-Crystal", bundle: resourceBundle)

    /// The "AppIconPreview-Default" asset catalog image resource.
    static let appIconPreviewDefault = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-Default", bundle: resourceBundle)

    /// The "AppIconPreview-Gold" asset catalog image resource.
    static let appIconPreviewGold = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-Gold", bundle: resourceBundle)

    /// The "AppIconPreview-Ivory" asset catalog image resource.
    static let appIconPreviewIvory = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-Ivory", bundle: resourceBundle)

    /// The "AppIconPreview-Landscape" asset catalog image resource.
    static let appIconPreviewLandscape = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-Landscape", bundle: resourceBundle)

    /// The "AppIconPreview-Neon" asset catalog image resource.
    static let appIconPreviewNeon = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-Neon", bundle: resourceBundle)

    /// The "AppIconPreview-Washi" asset catalog image resource.
    static let appIconPreviewWashi = DeveloperToolsSupport.ImageResource(name: "AppIconPreview-Washi", bundle: resourceBundle)

    /// The "HomeWallpaperDefault" asset catalog image resource.
    static let homeWallpaperDefault = DeveloperToolsSupport.ImageResource(name: "HomeWallpaperDefault", bundle: resourceBundle)

    /// The "SettingsFooterBrand" asset catalog image resource.
    static let settingsFooterBrand = DeveloperToolsSupport.ImageResource(name: "SettingsFooterBrand", bundle: resourceBundle)

    /// The "TipCroissantMany" asset catalog image resource.
    static let tipCroissantMany = DeveloperToolsSupport.ImageResource(name: "TipCroissantMany", bundle: resourceBundle)

    /// The "TipCroissantOne" asset catalog image resource.
    static let tipCroissantOne = DeveloperToolsSupport.ImageResource(name: "TipCroissantOne", bundle: resourceBundle)

    /// The "TipCroissantTwo" asset catalog image resource.
    static let tipCroissantTwo = DeveloperToolsSupport.ImageResource(name: "TipCroissantTwo", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "AppIconPreview-08" asset catalog image.
    static var appIconPreview08: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreview08)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-09" asset catalog image.
    static var appIconPreview09: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreview09)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-ClassicDark" asset catalog image.
    static var appIconPreviewClassicDark: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewClassicDark)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-ClassicLight" asset catalog image.
    static var appIconPreviewClassicLight: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewClassicLight)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Crystal" asset catalog image.
    static var appIconPreviewCrystal: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewCrystal)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Default" asset catalog image.
    static var appIconPreviewDefault: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewDefault)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Gold" asset catalog image.
    static var appIconPreviewGold: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewGold)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Ivory" asset catalog image.
    static var appIconPreviewIvory: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewIvory)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Landscape" asset catalog image.
    static var appIconPreviewLandscape: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewLandscape)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Neon" asset catalog image.
    static var appIconPreviewNeon: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewNeon)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Washi" asset catalog image.
    static var appIconPreviewWashi: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .appIconPreviewWashi)
#else
        .init()
#endif
    }

    /// The "HomeWallpaperDefault" asset catalog image.
    static var homeWallpaperDefault: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .homeWallpaperDefault)
#else
        .init()
#endif
    }

    /// The "SettingsFooterBrand" asset catalog image.
    static var settingsFooterBrand: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .settingsFooterBrand)
#else
        .init()
#endif
    }

    /// The "TipCroissantMany" asset catalog image.
    static var tipCroissantMany: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .tipCroissantMany)
#else
        .init()
#endif
    }

    /// The "TipCroissantOne" asset catalog image.
    static var tipCroissantOne: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .tipCroissantOne)
#else
        .init()
#endif
    }

    /// The "TipCroissantTwo" asset catalog image.
    static var tipCroissantTwo: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .tipCroissantTwo)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "AppIconPreview-08" asset catalog image.
    static var appIconPreview08: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreview08)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-09" asset catalog image.
    static var appIconPreview09: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreview09)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-ClassicDark" asset catalog image.
    static var appIconPreviewClassicDark: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewClassicDark)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-ClassicLight" asset catalog image.
    static var appIconPreviewClassicLight: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewClassicLight)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Crystal" asset catalog image.
    static var appIconPreviewCrystal: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewCrystal)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Default" asset catalog image.
    static var appIconPreviewDefault: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewDefault)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Gold" asset catalog image.
    static var appIconPreviewGold: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewGold)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Ivory" asset catalog image.
    static var appIconPreviewIvory: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewIvory)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Landscape" asset catalog image.
    static var appIconPreviewLandscape: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewLandscape)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Neon" asset catalog image.
    static var appIconPreviewNeon: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewNeon)
#else
        .init()
#endif
    }

    /// The "AppIconPreview-Washi" asset catalog image.
    static var appIconPreviewWashi: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .appIconPreviewWashi)
#else
        .init()
#endif
    }

    /// The "HomeWallpaperDefault" asset catalog image.
    static var homeWallpaperDefault: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .homeWallpaperDefault)
#else
        .init()
#endif
    }

    /// The "SettingsFooterBrand" asset catalog image.
    static var settingsFooterBrand: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .settingsFooterBrand)
#else
        .init()
#endif
    }

    /// The "TipCroissantMany" asset catalog image.
    static var tipCroissantMany: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .tipCroissantMany)
#else
        .init()
#endif
    }

    /// The "TipCroissantOne" asset catalog image.
    static var tipCroissantOne: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .tipCroissantOne)
#else
        .init()
#endif
    }

    /// The "TipCroissantTwo" asset catalog image.
    static var tipCroissantTwo: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .tipCroissantTwo)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

