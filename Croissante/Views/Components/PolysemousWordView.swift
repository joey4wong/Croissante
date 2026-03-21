import SwiftUI

/// 多义词显示组件，支持同形异义词的层叠显示和切换
struct PolysemousWordView: View {
    let word: SimpleWord
    let siblings: [SimpleWord]
    let language: String
    let onSiblingTapped: (SimpleWord) -> Void
    
    @State private var expanded: Bool = false
    @State private var selectedIndex: Int = 0
    
    init(word: SimpleWord, 
         siblings: [SimpleWord],
         language: String = "en",
         onSiblingTapped: @escaping (SimpleWord) -> Void) {
        self.word = word
        self.siblings = siblings
        self.language = language
        self.onSiblingTapped = onSiblingTapped
        // 如果当前单词不在siblings中，将其作为第一个元素
        _selectedIndex = State(initialValue: siblings.firstIndex(where: { $0.id == word.id }) ?? 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部信息栏（始终显示）
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.word)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("多义词 • 第 \(selectedIndex + 1) / \(siblings.count) 个释义")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 展开/收起按钮
                Button(action: { withAnimation(.spring(response: 0.3)) { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                
                // 多义词指示器
                Circle()
                    .fill(Color.orange.opacity(0.8))
                    .frame(width: 8, height: 8)
                    .shadow(color: .orange.opacity(0.3), radius: 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // 当前单词卡片
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(siblings[selectedIndex].tag)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Text(siblings[selectedIndex].level)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    
                    // 翻译
                    VStack(alignment: .leading, spacing: 4) {
                        if language == "zh" || language == "en" {
                            Text(language == "zh" ? 
                                siblings[selectedIndex].translationZh : 
                                siblings[selectedIndex].translationEn)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        } else {
                            // 显示两种语言
                            Text(siblings[selectedIndex].translationEn)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text(siblings[selectedIndex].translationZh)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 示例句子
                    if !siblings[selectedIndex].exampleFr.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("示例")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text(siblings[selectedIndex].exampleFr)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .italic()
                            
                            if !siblings[selectedIndex].exampleZh.isEmpty {
                                Text(siblings[selectedIndex].exampleZh)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .padding(.horizontal, 16)
            
            // 展开后的多义词列表
            if expanded && siblings.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.vertical, 12)
                    
                    Text("其他释义")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(siblings.enumerated()), id: \.element.id) { index, sibling in
                                SiblingCardView(
                                    sibling: sibling,
                                    isSelected: index == selectedIndex,
                                    language: language,
                                    index: index
                                )
                                .frame(width: 180)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedIndex = index
                                    }
                                    onSiblingTapped(sibling)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // 底部切换按钮（仅当有多个释义时显示）
            if siblings.count > 1 {
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            selectedIndex = max(0, selectedIndex - 1)
                        }
                        onSiblingTapped(siblings[selectedIndex])
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(selectedIndex > 0 ? .primary : .gray)
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(22)
                    }
                    .disabled(selectedIndex == 0)
                    
                    Spacer()
                    
                    // 指示器圆点
                    HStack(spacing: 6) {
                        ForEach(0..<siblings.count, id: \.self) { index in
                            Circle()
                                .fill(index == selectedIndex ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .scaleEffect(index == selectedIndex ? 1.2 : 1.0)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            selectedIndex = min(siblings.count - 1, selectedIndex + 1)
                        }
                        onSiblingTapped(siblings[selectedIndex])
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(selectedIndex < siblings.count - 1 ? .primary : .gray)
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(22)
                    }
                    .disabled(selectedIndex == siblings.count - 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.03), Color.orange.opacity(0.01)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: expanded)
    }
}

/// 多义词卡片组件
private struct SiblingCardView: View {
    let sibling: SimpleWord
    let isSelected: Bool
    let language: String
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
                
                Spacer()
                
                Text(sibling.tag)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            Text(language == "zh" ? sibling.translationZh : sibling.translationEn)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            if !sibling.exampleFr.isEmpty {
                Text(sibling.exampleFr)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .italic()
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.05) : Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

/// 卡片层叠视图（用于单词卡片）
struct CascadingWordCardsView: View {
    let words: [SimpleWord]
    let language: String
    let onCardTapped: (SimpleWord) -> Void
    
    @State private var expandedIndices: Set<Int> = []
    @State private var offsets: [CGFloat] = []
    
    init(words: [SimpleWord], language: String = "en", onCardTapped: @escaping (SimpleWord) -> Void) {
        self.words = words
        self.language = language
        self.onCardTapped = onCardTapped
        _offsets = State(initialValue: Array(repeating: 0, count: words.count))
    }
    
    var body: some View {
        ZStack {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                if index == words.count - 1 || expandedIndices.contains(index) {
                    CascadingWordCardView(
                        word: word,
                        language: language,
                        isExpanded: expandedIndices.contains(index),
                        onExpandToggle: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if expandedIndices.contains(index) {
                                    expandedIndices.remove(index)
                                } else {
                                    expandedIndices.insert(index)
                                }
                            }
                        },
                        onCardTapped: {
                            onCardTapped(word)
                        }
                    )
                    .offset(y: offsets[index])
                    .zIndex(Double(index))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // 设置初始偏移，创建层叠效果
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                offsets = (0..<words.count).map { index in
                    CGFloat(index * 8) // 每个卡片偏移8点
                }
            }
        }
    }
}

/// 单词卡片组件（层叠卡片视图内部使用）
private struct CascadingWordCardView: View {
    let word: SimpleWord
    let language: String
    let isExpanded: Bool
    let onExpandToggle: () -> Void
    let onCardTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.word)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text(word.tag)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Text(word.level)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                Button(action: onExpandToggle) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, isExpanded ? 12 : 16)
            
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    // 翻译
                    VStack(alignment: .leading, spacing: 4) {
                        if language == "zh" {
                            Text(word.translationZh)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        } else {
                            Text(word.translationEn)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Text(word.translationZh)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 示例句子
                    if !word.exampleFr.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("示例")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text(word.exampleFr)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .italic()
                            
                            if !word.exampleZh.isEmpty {
                                Text(word.exampleZh)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(isExpanded ? 0.1 : 0.05), 
                radius: isExpanded ? 12 : 8, 
                x: 0, 
                y: isExpanded ? 4 : 2)
        .padding(.horizontal, 16)
        .onTapGesture {
            onCardTapped()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
}

// MARK: - Preview

#Preview {
    let sampleWords = [
        SimpleWord(
            id: "w_bonjour_1",
            word: "bonjour",
            tag: "INTJ",
            level: "A1",
            translationZh: "你好",
            translationEn: "hello",
            exampleFr: "Bonjour, comment ca va ?",
            exampleZh: "你好，你最近怎么样？"
        ),
        SimpleWord(
            id: "w_bonjour_2",
            word: "bonjour",
            tag: "N",
            level: "A1",
            translationZh: "问候",
            translationEn: "greeting",
            exampleFr: "Le bonjour est important dans la culture française.",
            exampleZh: "问候在法国文化中很重要。"
        )
    ]
    
    ScrollView {
        VStack(spacing: 20) {
            PolysemousWordView(
                word: sampleWords[0],
                siblings: sampleWords,
                language: "zh"
            ) { sibling in
                print("Tapped: \(sibling.word)")
            }
            
            CascadingWordCardsView(
                words: sampleWords,
                language: "en"
            ) { word in
                print("Card tapped: \(word.word)")
            }
            .frame(height: 400)
        }
        .padding(.vertical, 20)
    }
    .background(Color.gray.opacity(0.1))
}
