import SwiftUI

#if os(iOS)
import UIKit
import PhotosUI
import AVFoundation
#endif

/// 图片选择器服务，支持从相册选择头像图片
@MainActor
final class ImagePickerService: ObservableObject {
    static let shared = ImagePickerService()
    
    #if os(iOS)
    @Published private(set) var selectedImage: UIImage?
    #endif
    @Published private(set) var isPickingImage: Bool = false
    
    #if os(iOS)
    private var imagePicker: UIImagePickerController?
    private var imagePickerCoordinator: Coordinator?
    #endif
    
    private init() {}
    
    /// 显示图片选择器（从相册选择）
    func presentImagePicker() {
        #if os(iOS)
        isPickingImage = true
        
        // 检查权限
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self.showImagePicker()
                    } else {
                        self.isPickingImage = false
                    }
                }
            }
        } else if status == .authorized || status == .limited {
            showImagePicker()
        } else {
            isPickingImage = false
            // 显示权限提示
            showPermissionAlert()
        }
        #else
        // 在非iOS平台，只记录日志
        print("Image picker not available on this platform")
        isPickingImage = false
        #endif
    }
    
    /// 从文件系统选择图片
    func pickImageFromFiles() {
        #if os(iOS)
        showImagePicker(sourceType: .photoLibrary)
        #else
        print("Image picker not available on this platform")
        #endif
    }
    
    /// 使用相机拍摄图片
    func takePhotoWithCamera() {
        #if os(iOS)
        // 检查相机权限
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraAuthStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.showImagePicker(sourceType: .camera)
                        } else {
                            self.isPickingImage = false
                            self.showCameraPermissionAlert()
                        }
                    }
                }
            } else if cameraAuthStatus == .authorized {
                showImagePicker(sourceType: .camera)
            } else {
                isPickingImage = false
                showCameraPermissionAlert()
            }
        } else {
            isPickingImage = false
            showCameraUnavailableAlert()
        }
        #else
        print("Camera not available on this platform")
        isPickingImage = false
        #endif
    }
    
    /// 取消图片选择
    func cancelImagePicker() {
        isPickingImage = false
    }
    
    #if os(iOS)
    /// 设置选中的图片
    func setSelectedImage(_ image: UIImage?) {
        selectedImage = image
        isPickingImage = false
    }
    #endif
    
    #if os(iOS)
    /// 保存图片到应用沙盒
    func saveImageToAppStorage(_ image: UIImage, filename: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let avatarDirectory = documentsDirectory.appendingPathComponent("avatars")
        
        // 创建avatars目录
        try? fileManager.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        
        // 生成唯一文件名
        let uniqueFilename = "\(UUID().uuidString)_\(filename)"
        let fileURL = avatarDirectory.appendingPathComponent(uniqueFilename)
        
        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            print("Error saving image: \(error)")
            return nil
        }
    }
    #endif
    
    #if os(iOS)
    /// 从应用沙盒加载图片
    func loadImageFromPath(_ path: String) -> UIImage? {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return UIImage(data: data)
        } catch {
            print("Error loading image: \(error)")
            return nil
        }
    }
    #endif
    
    /// 删除保存的图片
    func deleteImageAtPath(_ path: String) {
        #if os(iOS)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
        #endif
    }
    
    #if os(iOS)
    /// 压缩图片
    func compressImage(_ image: UIImage, maxSize: CGFloat = 1024) -> UIImage {
        let size = image.size
        let ratio = maxSize / max(size.width, size.height)
        
        if ratio < 1.0 {
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let compressedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return compressedImage ?? image
        }
        return image
    }
    #endif
    
    #if os(iOS)
    /// 创建圆形头像图片
    func createCircularAvatar(_ image: UIImage, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            
            // 创建圆形裁剪路径
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: size / 2)
            path.addClip()
            
            // 等比居中填充，避免非正方形图片被拉伸变形
            let sourceSize = image.size
            let scale = max(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawOrigin = CGPoint(
                x: bounds.midX - drawSize.width / 2,
                y: bounds.midY - drawSize.height / 2
            )
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
            
            // 添加边框
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(2.0)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()
        }
    }
    #endif
    
    // MARK: - Private Methods
    
    #if os(iOS)
    private func rootViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let root = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? windowScene.windows.first?.rootViewController
        else {
            return nil
        }
        return root
    }

    private func presentAlert(
        title: String,
        message: String,
        includesSettingsShortcut: Bool = false,
        confirmTitle: String = "确定"
    ) {
        guard let rootViewController = rootViewController() else { return }

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        if includesSettingsShortcut {
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "前往设置", style: .default) { _ in
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            })
        } else {
            alert.addAction(UIAlertAction(title: confirmTitle, style: .cancel))
        }

        rootViewController.present(alert, animated: true)
    }

    private func showImagePicker(sourceType: UIImagePickerController.SourceType = .photoLibrary) {
        guard let rootViewController = rootViewController() else {
            isPickingImage = false
            return
        }

        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = false
        imagePickerCoordinator = Coordinator(parent: self)
        picker.delegate = imagePickerCoordinator
        imagePicker = picker

        rootViewController.present(picker, animated: true)
    }
    
    private func showPermissionAlert() {
        presentAlert(
            title: "需要照片权限",
            message: "请允许访问照片库以选择头像",
            includesSettingsShortcut: true
        )
    }
    
    private func showCameraPermissionAlert() {
        presentAlert(
            title: "需要相机权限",
            message: "请允许访问相机以拍摄照片",
            includesSettingsShortcut: true
        )
    }
    
    private func showCameraUnavailableAlert() {
        presentAlert(
            title: "相机不可用",
            message: "此设备没有可用的相机"
        )
    }
    
    // MARK: - Coordinator
    
    private class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerService
        
        init(parent: ImagePickerService) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.setSelectedImage(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.setSelectedImage(originalImage)
            }
            
            parent.imagePicker = nil
            parent.imagePickerCoordinator = nil
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.cancelImagePicker()
            parent.imagePicker = nil
            parent.imagePickerCoordinator = nil
            picker.dismiss(animated: true)
        }
    }
    #endif
}

#if os(iOS)
// MARK: - SwiftUI 图片选择器视图

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if sourceType == .camera, UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            if UIImagePickerController.isCameraDeviceAvailable(.rear) {
                picker.cameraDevice = .rear
            }
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
    
}
#endif

// MARK: - 头像编辑器视图

struct AvatarEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    enum ImageSource: Identifiable {
        case photoLibrary, camera
        var id: Int { hashValue }
    }

    private enum PermissionAlert {
        case photoLibrary, camera
    }

    #if os(iOS)
    @State private var avatarImage: UIImage?
    #endif
    @State private var activeImageSource: ImageSource?
    @State private var permissionAlert: PermissionAlert?
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var isDarkMode: Bool { colorScheme == .dark }
    private var rowIconColor: Color {
        isDarkMode ? Color.white.opacity(0.78) : Color.black.opacity(0.72)
    }
    private var rowTitleColor: Color {
        isDarkMode ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }
    private var rowSubtitleColor: Color {
        isDarkMode ? Color.white.opacity(0.62) : Color.black.opacity(0.48)
    }
    private var rowDividerColor: Color {
        isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }
    private var containerFillColor: Color {
        isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }
    private var containerBorderColor: Color {
        isDarkMode ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    @ViewBuilder
    private func sourceRow(
        icon: String,
        title: String,
        subtitle: String,
        showsDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(rowIconColor)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(rowTitleColor)
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(rowSubtitleColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)

                if showsDivider {
                    Rectangle()
                        .fill(rowDividerColor)
                        .frame(height: 1)
                        .padding(.leading, 64)
                        .padding(.trailing, 14)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                #if os(iOS)
                sourceRow(
                    icon: "photo.on.rectangle.angled",
                    title: appState.localized("Photos", "相册", "फोटो"),
                    subtitle: appState.localized("Choose from your Library", "从相册中选择", "लाइब्रेरी से चुनें"),
                    showsDivider: true
                ) {
                    presentPhotoLibraryPicker()
                }

                sourceRow(
                    icon: "camera",
                    title: appState.localized("Camera", "相机", "कैमरा"),
                    subtitle: appState.localized("Capture a new photo", "拍摄一张新照片", "नई फोटो लें"),
                    showsDivider: false
                ) {
                    presentCameraPicker()
                }
                #endif
            }
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(containerFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(containerBorderColor, lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .offset(y: 8)

            Spacer(minLength: 0)
        }
            #if os(iOS)
            .fullScreenCover(item: $activeImageSource) { source in
                ImagePickerView(
                    selectedImage: $avatarImage,
                    isPresented: Binding(
                        get: { activeImageSource != nil },
                        set: { if !$0 { activeImageSource = nil } }
                    ),
                    sourceType: source == .camera ? .camera : .photoLibrary
                )
                .ignoresSafeArea()
            }
            #endif
            .alert(appState.localized("Error", "错误", "त्रुटि"), isPresented: $showError) {
                Button(appState.localized("OK", "确定", "ठीक है"), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert(permissionAlertTitle, isPresented: Binding(
                get: { permissionAlert != nil },
                set: { if !$0 { permissionAlert = nil } }
            )) {
                Button(appState.localized("Cancel", "取消", "रद्द करें"), role: .cancel) {
                    permissionAlert = nil
                }
                Button(appState.localized("Settings", "设置", "सेटिंग्स")) {
                    openAppSettings()
                    permissionAlert = nil
                }
            } message: {
                Text(permissionAlertMessage)
            }
            #if os(iOS)
            .onChange(of: avatarImage) { _, newImage in
                guard newImage != nil, !isSaving else { return }
                saveAvatar()
            }
            #endif
    }
    
    #if os(iOS)
    private var permissionAlertTitle: String {
        switch permissionAlert {
        case .photoLibrary:
            appState.localized("Photo Access Needed", "需要照片权限", "फ़ोटो एक्सेस चाहिए")
        case .camera:
            appState.localized("Camera Access Needed", "需要相机权限", "कैमरा एक्सेस चाहिए")
        case .none:
            ""
        }
    }

    private var permissionAlertMessage: String {
        switch permissionAlert {
        case .photoLibrary:
            appState.localized(
                "Allow photo access in Settings to choose an avatar.",
                "请在设置中允许访问照片，才能选择头像。",
                "अवतार चुनने के लिए सेटिंग्स में फ़ोटो एक्सेस की अनुमति दें।"
            )
        case .camera:
            appState.localized(
                "Allow camera access in Settings to take an avatar photo.",
                "请在设置中允许访问相机，才能拍摄头像。",
                "अवतार फ़ोटो लेने के लिए सेटिंग्स में कैमरा एक्सेस की अनुमति दें।"
            )
        case .none:
            ""
        }
    }

    private func presentPhotoLibraryPicker() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            activeImageSource = .photoLibrary
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Task { @MainActor in
                    if status == .authorized || status == .limited {
                        activeImageSource = .photoLibrary
                    } else {
                        permissionAlert = .photoLibrary
                    }
                }
            }
        case .denied, .restricted:
            permissionAlert = .photoLibrary
        @unknown default:
            permissionAlert = .photoLibrary
        }
    }

    private func presentCameraPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = appState.localized(
                "Camera is not available on this device.",
                "此设备没有可用的相机。",
                "इस डिवाइस पर कैमरा उपलब्ध नहीं है।"
            )
            showError = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            activeImageSource = .camera
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        activeImageSource = .camera
                    } else {
                        permissionAlert = .camera
                    }
                }
            }
        case .denied, .restricted:
            permissionAlert = .camera
        @unknown default:
            permissionAlert = .camera
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func saveAvatar() {
        guard let image = avatarImage else { return }
        
        isSaving = true
        
        // 压缩图片
        let compressedImage = ImagePickerService.shared.compressImage(image, maxSize: 1024)
        
        // 创建圆形头像
        let circularAvatar = ImagePickerService.shared.createCircularAvatar(compressedImage, size: 300)
        
        // 保存到应用沙盒
        if let savedPath = ImagePickerService.shared.saveImageToAppStorage(circularAvatar, filename: "avatar.jpg") {
            // 更新AppState
            appState.avatarPath = savedPath
            
            // 短暂延迟后关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isSaving = false
                dismiss()
            }
        } else {
            errorMessage = appState.localized("Failed to save avatar", "保存头像时出错", "अवतार सेव नहीं हो पाया")
            showError = true
            isSaving = false
        }
    }
    #endif
}

// MARK: - Preview

#Preview {
    AvatarEditorView()
        .environmentObject(AppState())
}
