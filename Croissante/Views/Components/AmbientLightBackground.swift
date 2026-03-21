import SwiftUI

private enum BlobColors {
    static func light1() -> Color { Color(red: 1.0, green: 0.16, blue: 0.37) }
    static func light2() -> Color { Color(red: 0.0, green: 0.48, blue: 1.0) }
    static func light3() -> Color { Color(red: 1.0, green: 0.58, blue: 0.0) }
    static func dark1() -> Color { Color(red: 0.56, green: 0.41, blue: 0.66) }
    static func dark2() -> Color { Color(red: 0.34, green: 0.46, blue: 0.86) }
    static func dark3() -> Color { Color(red: 0.84, green: 0.45, blue: 0.32) }

    static func backgroundColor(isDark: Bool) -> Color {
        isDark ? AppColors.nocturneBackgroundBottom : Color(red: 0.90, green: 0.90, blue: 0.92)
    }

    static func blobOpacity(isDark: Bool) -> Double {
        isDark ? 0.22 : 0.7
    }

    static func color1(isDark: Bool) -> Color { isDark ? dark1() : light1() }
    static func color2(isDark: Bool) -> Color { isDark ? dark2() : light2() }
    static func color3(isDark: Bool) -> Color { isDark ? dark3() : light3() }
}

struct AmbientLightBackground: View {
    let isDark: Bool
    let child: AnyView?
    
    init(isDark: Bool, child: AnyView? = nil) {
        self.isDark = isDark
        self.child = child
    }
    
    init<Content: View>(isDark: Bool, @ViewBuilder content: () -> Content) {
        self.isDark = isDark
        self.child = AnyView(content())
    }
    
    @State private var animationProgress: Double = 0
    @State private var blob1Offset: CGSize = .zero
    @State private var blob2Offset: CGSize = .zero
    @State private var blob3Offset: CGSize = .zero
    @State private var blob1Scale: CGFloat = 1.0
    @State private var blob2Scale: CGFloat = 1.0
    @State private var blob3Scale: CGFloat = 1.0
    @State private var blob1Rotation: Angle = .zero
    @State private var blob2Rotation: Angle = .zero
    @State private var blob3Rotation: Angle = .zero
    
    private let animationDuration: Double = 20.0
    private let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BlobColors.backgroundColor(isDark: isDark)
                    .ignoresSafeArea()
                
                blobView(
                    color: BlobColors.color1(isDark: isDark),
                    size: geometry.size.width * 0.5,
                    offset: blob1Offset,
                    scale: blob1Scale,
                    rotation: blob1Rotation,
                    top: -0.1,
                    left: -0.1,
                    geometry: geometry
                )
                
                blobView(
                    color: BlobColors.color2(isDark: isDark),
                    size: geometry.size.width * 0.45,
                    offset: blob2Offset,
                    scale: blob2Scale,
                    rotation: blob2Rotation,
                    top: 0.6,
                    left: 0.8,
                    geometry: geometry
                )
                
                blobView(
                    color: BlobColors.color3(isDark: isDark),
                    size: geometry.size.width * 0.35,
                    offset: blob3Offset,
                    scale: blob3Scale,
                    rotation: blob3Rotation,
                    top: 0.3,
                    left: 0.4,
                    geometry: geometry
                )
                
                if let child = child {
                    child
                }
            }
        }
        .onAppear {
            animationProgress = 0
        }
        .onReceive(timer) { _ in
            updateAnimation()
        }
    }
    
    private func blobView(
        color: Color,
        size: CGFloat,
        offset: CGSize,
        scale: CGFloat,
        rotation: Angle,
        top: Double,
        left: Double,
        geometry: GeometryProxy
    ) -> some View {
        let baseX = left * geometry.size.width
        let baseY = top * geometry.size.height
        
        return Circle()
            .fill(color.opacity(BlobColors.blobOpacity(isDark: isDark)))
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .position(
                x: baseX + offset.width + size / 2,
                y: baseY + offset.height + size / 2
            )
    }
    
    private func updateAnimation() {
        animationProgress += 0.016 / animationDuration
        if animationProgress >= 1.0 {
            animationProgress -= 1.0
        }
        
        let blob1Phase = animationProgress
        blob1Offset.width = sin(blob1Phase * 2 * .pi) * 10
        blob1Offset.height = cos(blob1Phase * 2 * .pi) * 20
        blob1Scale = 1.0 + 0.1 * sin(blob1Phase * .pi)
        blob1Rotation = .radians(sin(blob1Phase * .pi) * 0.1)
        
        let blob2Phase = (animationProgress + 0.33).truncatingRemainder(dividingBy: 1.0)
        blob2Offset.width = sin(blob2Phase * 2 * .pi) * 10
        blob2Offset.height = cos(blob2Phase * 2 * .pi) * 20
        blob2Scale = 1.0 + 0.1 * sin(blob2Phase * .pi)
        blob2Rotation = .radians(sin(blob2Phase * .pi) * 0.1)
        
        let blob3Phase = (animationProgress + 0.66).truncatingRemainder(dividingBy: 1.0)
        blob3Offset.width = sin(blob3Phase * 2 * .pi) * 10
        blob3Offset.height = cos(blob3Phase * 2 * .pi) * 20
        blob3Scale = 1.0 + 0.1 * sin(blob3Phase * .pi)
        blob3Rotation = .radians(sin(blob3Phase * .pi) * 0.1)
    }
}

struct StaticAmbientLightBackground: View {
    let isDark: Bool
    let child: AnyView?
    
    init(isDark: Bool, child: AnyView? = nil) {
        self.isDark = isDark
        self.child = child
    }
    
    init<Content: View>(isDark: Bool, @ViewBuilder content: () -> Content) {
        self.isDark = isDark
        self.child = AnyView(content())
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BlobColors.backgroundColor(isDark: isDark)
                    .ignoresSafeArea()
                
                Circle()
                    .fill(BlobColors.color1(isDark: isDark).opacity(BlobColors.blobOpacity(isDark: isDark)))
                    .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
                    .position(
                        x: -0.1 * geometry.size.width + geometry.size.width * 0.25,
                        y: -0.1 * geometry.size.height + geometry.size.width * 0.25
                    )
                
                Circle()
                    .fill(BlobColors.color2(isDark: isDark).opacity(BlobColors.blobOpacity(isDark: isDark)))
                    .frame(width: geometry.size.width * 0.45, height: geometry.size.width * 0.45)
                    .position(
                        x: 0.8 * geometry.size.width + geometry.size.width * 0.225,
                        y: 0.6 * geometry.size.height + geometry.size.width * 0.225
                    )
                
                Circle()
                    .fill(BlobColors.color3(isDark: isDark).opacity(BlobColors.blobOpacity(isDark: isDark)))
                    .frame(width: geometry.size.width * 0.35, height: geometry.size.width * 0.35)
                    .position(
                        x: 0.4 * geometry.size.width + geometry.size.width * 0.175,
                        y: 0.3 * geometry.size.height + geometry.size.width * 0.175
                    )
                
                if let child = child {
                    child
                }
            }
        }
    }
}

#Preview("Animated Dark") {
    AmbientLightBackground(isDark: true) {
        Text("内容在背景之上")
            .font(.largeTitle)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 400, height: 800)
}

#Preview("Animated Light") {
    AmbientLightBackground(isDark: false) {
        Text("内容在背景之上")
            .font(.largeTitle)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 400, height: 800)
}

#Preview("Static Dark") {
    StaticAmbientLightBackground(isDark: true) {
        Text("静态背景 - 黑夜模式")
            .font(.largeTitle)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 400, height: 800)
}

#Preview("Static Light") {
    StaticAmbientLightBackground(isDark: false) {
        Text("静态背景 - 白天模式")
            .font(.largeTitle)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 400, height: 800)
}
