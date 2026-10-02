import SwiftUI

#if os(iOS)
import UIKit
import PhotosUI
import AVFoundation
#endif

@MainActor
final class ImagePickerService {
    static let shared = ImagePickerService()

    private init() {}

    #if os(iOS)
    func saveImageToAppStorage(_ image: UIImage, filename: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let avatarDirectory = documentsDirectory.appendingPathComponent("avatars")
        try? fileManager.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        let fileURL = avatarDirectory.appendingPathComponent("\(UUID().uuidString)_\(filename)")
        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }

    func loadImageFromPath(_ path: String) -> UIImage? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return UIImage(data: data)
    }

    func compressImage(_ image: UIImage, maxSize: CGFloat = 1024) -> UIImage {
        let size = image.size
        let ratio = maxSize / max(size.width, size.height)
        guard ratio < 1.0 else { return image }
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let compressedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return compressedImage ?? image
    }

    func createCircularAvatar(_ image: UIImage, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: size / 2)
            path.addClip()
            let sourceSize = image.size
            let scale = max(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawOrigin = CGPoint(x: bounds.midX - drawSize.width / 2, y: bounds.midY - drawSize.height / 2)
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(2.0)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()
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
                    title: appState.localized("Photos", "相册"),
                    subtitle: appState.localized("Choose from your Library", "从相册中选择"),
                    showsDivider: true
                ) {
                    presentPhotoLibraryPicker()
                }

                sourceRow(
                    icon: "camera",
                    title: appState.localized("Camera", "相机"),
                    subtitle: appState.localized("Capture a new photo", "拍摄一张新照片"),
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
            .alert(appState.localized("Error", "错误"), isPresented: $showError) {
                Button(appState.localized("OK", "确定"), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert(permissionAlertTitle, isPresented: Binding(
                get: { permissionAlert != nil },
                set: { if !$0 { permissionAlert = nil } }
            )) {
                Button(appState.localized("Cancel", "取消"), role: .cancel) {
                    permissionAlert = nil
                }
                Button(appState.localized("Settings", "设置")) {
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
            appState.localized("Photo Access Needed", "需要照片权限")
        case .camera:
            appState.localized("Camera Access Needed", "需要相机权限")
        case .none:
            ""
        }
    }

    private var permissionAlertMessage: String {
        switch permissionAlert {
        case .photoLibrary:
            appState.localized("Allow photo access in Settings to choose an avatar.", "请在设置中允许访问照片，才能选择头像。")
        case .camera:
            appState.localized("Allow camera access in Settings to take an avatar photo.", "请在设置中允许访问相机，才能拍摄头像。")
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
            errorMessage = appState.localized("Camera is not available on this device.", "此设备没有可用的相机。")
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
            errorMessage = appState.localized("Failed to save avatar", "保存头像时出错")
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
