import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit
#endif

// MARK: - Helper Functions

func posLabel(_ tag: String) -> String {
    switch tag.uppercased() {
    case "N":
        return "n."
    case "V":
        return "v."
    case "A":
        return "adj."
    case "ADV":
        return "adv."
    case "INTJ":
        return "intj."
    case "PREP":
        return "prep."
    case "CONJ":
        return "conj."
    case "PRON":
        return "pron."
    case "DET":
        return "det."
    case "ART":
        return "art."
    default:
        return tag
    }
}

// MARK: - Word Card View

struct WordCardView: View {
    let word: SimpleWord
    @State private var dragOffset: CGSize = .zero
    @State private var dragRotation: Angle = .zero
    @State private var isDragging = false
    @State private var showForgotLabel = false
    @State private var showMasteredLabel = false
    @State private var showBlurryLabel = false
    @State private var showingOtherMeaning = false
    
    var onMarkForgot: ((String) -> Void)?
    var onMarkMastered: ((String) -> Void)?
    var onMarkBlurry: ((String) -> Void)?
    var onClose: (() -> Void)?
    
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    private let glowLayerIndices = [0, 1, 2]
    
    // 绿色发光效果颜色
    private var greenGlowColor: Color {
        isDark ? Color(red: 0.32, green: 1.0, blue: 0.68) : Color(red: 0.32, green: 0.97, blue: 0.64)
    }
    
    private var cardBackgroundColor: Color {
        isDark ? Color(red: 0.1, green: 0.12, blue: 0.16) : .white
    }
    
    private var cardBorderColor: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }
    
    // 手势标签
    private var forgotLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
            Text(appState.localized("Forgot", "忘记", "भूल गया"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red, lineWidth: 2.5)
        )
    }
    
    private var masteredLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
            Text(appState.localized("Mastered", "已掌握", "सीख लिया"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green, lineWidth: 2.5)
        )
    }
    
    private var blurryLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash")
                .foregroundColor(.orange)
            Text(appState.localized("Blurry", "模糊", "धुंधला"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange, lineWidth: 2.5)
        )
    }
    
    // 发音功能
    private func speakWord() {
        ElevenLabsTTSService.stopPlayback()
        ElevenLabsTTSService.speakText(word.word, language: "fr-FR", contentType: .word)
    }
    
    // 手势处理
    private func handleDragEnd(_ value: DragGesture.Value, availableWidth: CGFloat) {
        let translation = value.translation
        let velocity = value.predictedEndLocation
        
        // 计算拖拽距离和速度
        let dragX = translation.width
        let dragY = translation.height
        let velocityX = velocity.x - value.startLocation.x
        let velocityY = velocity.y - value.startLocation.y
        
        let swipeThreshold: CGFloat = 100
        let velocityThreshold: CGFloat = 800
        
        // 判断手势方向
        if dragY > swipeThreshold || velocityY > velocityThreshold {
            // 下滑 - 模糊
            animateSwipeDown()
            onMarkBlurry?(word.id)
        } else if dragX < -swipeThreshold || velocityX < -velocityThreshold {
            // 左滑 - 忘记
            animateSwipeOut(toRight: false, availableWidth: availableWidth)
            onMarkForgot?(word.id)
        } else if dragX > swipeThreshold || velocityX > velocityThreshold {
            // 右滑 - 已掌握
            animateSwipeOut(toRight: true, availableWidth: availableWidth)
            onMarkMastered?(word.id)
        } else {
            // 回到原位
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = .zero
                dragRotation = .zero
                showForgotLabel = false
                showMasteredLabel = false
                showBlurryLabel = false
            }
        }
    }
    
    private func animateSwipeDown() {
        let targetOffset = CGSize(width: 0, height: 400)
        withAnimation(.easeOut(duration: 0.3)) {
            dragOffset = targetOffset
            showBlurryLabel = true
        }
    }
    
    private func animateSwipeOut(toRight: Bool, availableWidth: CGFloat) {
        let targetOffset = CGSize(width: toRight ? availableWidth * 1.2 : -availableWidth * 1.2, height: 0)
        withAnimation(.easeOut(duration: 0.3)) {
            dragOffset = targetOffset
            showForgotLabel = !toRight
            showMasteredLabel = toRight
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 绿色发光背景效果（黑夜模式特有）
                if isDark {
                    ForEach(glowLayerIndices, id: \.self) { index in
                        Circle()
                            .fill(greenGlowColor.opacity(0.3 - Double(index) * 0.1))
                            .frame(width: geometry.size.width + CGFloat(index * 40),
                                   height: geometry.size.height + CGFloat(index * 40))
                            .blur(radius: CGFloat(20 + index * 10))
                            .offset(y: -20)
                    }
                }
                
                // 卡片主体
                VStack(alignment: .leading, spacing: 0) {
                    // 单词和发音按钮
                    HStack(alignment: .center, spacing: 6) {
                        Text(word.word)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(isDark ? .white : Color(red: 0.07, green: 0.09, blue: 0.15))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        Button(action: speakWord) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 18))
                                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.54))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    
                    Divider()
                        .padding(.bottom, 24)
                    
                    // 词性和翻译
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(posLabel(word.tag))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isDark ? .white.opacity(0.54) : .black.opacity(0.38))
                            .kerning(0.3)
                        
                        Text(appState.translationText(for: word))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(isDark ? .white : .black.opacity(0.87))
                            .lineLimit(nil)
                    }
                    .padding(.bottom, 8)
                    
                    // 法语例句
                    if !word.exampleFr.isEmpty {
                        Text(word.exampleFr)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isDark ? .white : .black.opacity(0.87))
                            .padding(.bottom, 2)
                    }
                    
                    // 译文例句（按当前语言）
                    let translatedExample = appState.translatedExampleText(for: word)
                    if !translatedExample.isEmpty {
                        Text(translatedExample)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.54))
                    }
                    
                    Spacer()
                    
                    // 关闭按钮（如果有）
                    if let onClose = onClose {
                        HStack {
                            Spacer()
                            Button(appState.localized("Close", "关闭", "बंद करें"), action: onClose)
                                .font(.system(size: 15))
                                .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.54))
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                // 多义词层叠按钮
                if appState.isPolysemous(word) && !showingOtherMeaning {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                showingOtherMeaning = true
                            }) {
                                Image(systemName: "layers")
                                    .font(.system(size: 18))
                                    .foregroundColor(isDark ? .white.opacity(0.7) : .black.opacity(0.6))
                                    .padding(12)
                                    .background(
                                        Circle()
                                            .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    )
                            }
                            .offset(x: -16, y: -16)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(cardBackgroundColor)
            .cornerRadius(30)
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
            .shadow(color: isDark ? 
                Color.black.opacity(0.42) : 
                Color(red: 0.11, green: 0.15, blue: 0.21).opacity(0.07),
                radius: 36, x: 0, y: 14
            )
            .rotationEffect(dragRotation)
            .offset(dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                        }
                        
                        dragOffset = value.translation
                        
                        // 计算旋转角度（基于水平拖拽）
                        let availableWidth = max(geometry.size.width, 1)
                        let rotationAmount = value.translation.width / availableWidth * 0.15
                        dragRotation = .radians(Double(rotationAmount))
                        
                        // 显示相应的标签
                        showForgotLabel = value.translation.width < -50
                        showMasteredLabel = value.translation.width > 50
                        showBlurryLabel = value.translation.height > 50
                    }
                    .onEnded { value in
                        handleDragEnd(value, availableWidth: max(geometry.size.width, 1))
                        isDragging = false
                    }
            )
            
            // 手势提示标签
            if showForgotLabel && !isDragging {
                HStack {
                    forgotLabel
                        .rotationEffect(.degrees(-10))
                    Spacer()
                }
                .padding(.leading, 36)
                .padding(.top, 36)
                .transition(.opacity)
            }
            
            if showMasteredLabel && !isDragging {
                HStack {
                    Spacer()
                    masteredLabel
                        .rotationEffect(.degrees(10))
                }
                .padding(.trailing, 36)
                .padding(.top, 36)
                .transition(.opacity)
            }
            
            if showBlurryLabel && !isDragging {
                if dragOffset.height > 0 {
                    // 下滑模糊标签
                    VStack {
                        Spacer()
                        blurryLabel
                            .rotationEffect(.degrees(10))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 36)
                        .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Word Card Sheet

struct WordCardSheetView: View {
    let word: SimpleWord
    var onMarkForgot: ((String) -> Void)?
    var onMarkMastered: ((String) -> Void)?
    var onMarkBlurry: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            WordCardView(
                word: word,
                onMarkForgot: onMarkForgot,
                onMarkMastered: onMarkMastered,
                onMarkBlurry: onMarkBlurry,
                onClose: { dismiss() }
            )
            .frame(width: 560, height: 600)
        }
    }
}

// MARK: - Preview

#Preview {
    WordCardView(
        word: SimpleWord(
            id: "w_bonjour",
            word: "bonjour",
            tag: "INTJ",
            level: "A1",
            translationZh: "你好",
            translationEn: "hello",
            exampleFr: "Bonjour, comment ca va ?",
            exampleZh: "你好，你最近怎么样？"
        )
    )
    .environmentObject(AppState())
    .frame(width: 350, height: 400)
    .preferredColorScheme(.dark)
}
