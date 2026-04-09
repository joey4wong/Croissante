#!/bin/bash

# Croissante iOS SwiftUI App - 构建和运行脚本
# 使用 Xcode 26 会自动获得 iOS 26 Liquid Glass 效果

set -euo pipefail

echo "🚀 准备构建 Croissante iOS SwiftUI 应用..."
echo "📱 这是一个完整的 SwiftUI 应用，包含 iOS 26 Liquid Glass Tab 栏"

# 检查是否安装了 Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode 未安装或不在 PATH 中"
    echo "请先安装 Xcode 26 或更高版本"
    exit 1
fi

# 显示当前 Xcode 版本
echo "📦 Xcode 版本:"
xcodebuild -version

# 创建临时工作目录
WORK_DIR="/tmp/Croissante-build"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 复制项目文件
echo "📁 复制项目文件..."
cp -r Croissante "$WORK_DIR/"

# 创建简单的 Xcode 项目文件
echo "🛠️ 创建 Xcode 项目..."
mkdir -p "$WORK_DIR/Croissante.xcodeproj"

: <<'LEGACY_PBXPROJ'
cat > "$WORK_DIR/Croissante.xcodeproj/project.pbxproj" << 'PROJ'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		8C7F3A6E2A1B4B8F00A3C2B1 /* CroissanteApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8C7F3A6D2A1B4B8F00A3C2B1 /* CroissanteApp.swift */; };
		8C7F3A702A1B4B8F00A3C2B1 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8C7F3A6F2A1B4B8F00A3C2B1 /* ContentView.swift */; };
		8C7F3A722A1B4B8F00A3C2B1 /* AppState.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8C7F3A712A1B4B8F00A3C2B1 /* AppState.swift */; };
		8C7F3A742A1B4B8F00A3C2B1 /* LearningRecord.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8C7F3A732A1B4B8F00A3C2B1 /* LearningRecord.swift */; };
		8C7F3A762A1B4B8F00A3C2B1 /* words.json in Resources */ = {isa = PBXBuildFile; fileRef = 8C7F3A752A1B4B8F00A3C2B1 /* words.json */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		8C7F3A6D2A1B4B8F00A3C2B1 /* CroissanteApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CroissanteApp.swift; sourceTree = "<group>"; };
		8C7F3A6F2A1B4B8F00A3C2B1 /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
		8C7F3A712A1B4B8F00A3C2B1 /* AppState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppState.swift; sourceTree = "<group>"; };
		8C7F3A732A1B4B8F00A3C2B1 /* LearningRecord.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LearningRecord.swift; sourceTree = "<group>"; };
		8C7F3A752A1B4B8F00A3C2B1 /* words.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = words.json; sourceTree = "<group>"; };
		8C7F3A782A1B4B8F00A3C2B1 /* Croissante.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Croissante.app; sourceTree = BUILT_PRODUCTS_DIR; };
		8C7F3A7A2A1B4B8F00A3C2B1 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		8C7F3A7C2A1B4B8F00A3C2B1 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		8C7F3A6C2A1B4B8F00A3C2B1 /* Croissante */ = {
			isa = PBXGroup;
			children = (
				8C7F3A6D2A1B4B8F00A3C2B1 /* CroissanteApp.swift */,
				8C7F3A6F2A1B4B8F00A3C2B1 /* ContentView.swift */,
				8C7F3A712A1B4B8F00A3C2B1 /* AppState.swift */,
				8C7F3A732A1B4B8F00A3C2B1 /* LearningRecord.swift */,
				8C7F3A752A1B4B8F00A3C2B1 /* words.json */,
				8C7F3A7A2A1B4B8F00A3C2B1 /* Info.plist */,
			);
			path = Croissante;
			sourceTree = "<group>";
		};
		8C7F3A7F2A1B4B8F00A3C2B1 /* Products */ = {
			isa = PBXGroup;
			children = (
				8C7F3A782A1B4B8F00A3C2B1 /* Croissante.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		8C7F3A792A1B4B8F00A3C2B1 /* Croissante */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 8C7F3A7E2A1B4B8F00A3C2B1 /* Build configuration list for PBXNativeTarget "Croissante" */;
			buildPhases = (
				8C7F3A7B2A1B4B8F00A3C2B1 /* Sources */,
				8C7F3A7C2A1B4B8F00A3C2B1 /* Frameworks */,
				8C7F3A7D2A1B4B8F00A3C2B1 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Croissante;
			productName = Croissante;
			productReference = 8C7F3A782A1B4B8F00A3C2B1 /* Croissante.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		8C7F3A6A2A1B4B8F00A3C2B1 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					8C7F3A792A1B4B8F00A3C2B1 /* Croissante */ = {
						CreatedOnToolsVersion = 15.0;
						DevelopmentTeam = "";
					};
				};
			};
			buildConfigurationList = 8C7F3A6B2A1B4B8F00A3C2B1 /* Build configuration list for PBXProject "Croissante" */;
			compatibilityVersion = "Xcode 15.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 8C7F3A6A2A1B4B8F00A3C2B1;
			productRefGroup = 8C7F3A7F2A1B4B8F00A3C2B1 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				8C7F3A792A1B4B8F00A3C2B1 /* Croissante */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		8C7F3A7D2A1B4B8F00A3C2B1 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				8C7F3A762A1B4B8F00A3C2B1 /* words.json in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		8C7F3A7B2A1B4B8F00A3C2B1 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				8C7F3A702A1B4B8F00A3C2B1 /* ContentView.swift in Sources */,
				8C7F3A6E2A1B4B8F00A3C2B1 /* CroissanteApp.swift in Sources */,
				8C7F3A742A1B4B8F00A3C2B1 /* LearningRecord.swift in Sources */,
				8C7F3A722A1B4B8F00A3C2B1 /* AppState.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		8C7F3A802A1B4B8F00A3C2B1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		8C7F3A812A1B4B8F00A3C2B1 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		8C7F3A822A1B4B8F00A3C2B1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = "";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 2;
				DEVELOPMENT_ASSET_PATHS = "\"Croissante/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				INFOPLIST_FILE = Croissante/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.Croissante;
				PRODUCT_NAME = "Croissante";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		8C7F3A832A1B4B8F00A3C2B1 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = "";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 2;
				DEVELOPMENT_ASSET_PATHS = "\"Croissante/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				INFOPLIST_FILE = Croissante/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.Croissante;
				PRODUCT_NAME = "Croissante";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
	};
	rootObject = 8C7F3A6A2A1B4B8F00A3C2B1 /* Project object */;
}
PROJ

LEGACY_PBXPROJ

cat > "$WORK_DIR/Croissante.xcodeproj/project.pbxproj" << 'PBXPROJ'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		A00000000000000000000030 /* CroissanteApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000010 /* CroissanteApp.swift */; };
		A00000000000000000000031 /* Colors.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000011 /* Colors.swift */; };
		A00000000000000000000032 /* DailyRecord.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000012 /* DailyRecord.swift */; };
		A00000000000000000000033 /* LearningRecord.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000013 /* LearningRecord.swift */; };
		A00000000000000000000034 /* SimpleWord.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000014 /* SimpleWord.swift */; };
		A00000000000000000000035 /* AppIconManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000015 /* AppIconManager.swift */; };
		A00000000000000000000036 /* ImagePickerService.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000016 /* ImagePickerService.swift */; };
		A00000000000000000000037 /* SRSManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000017 /* SRSManager.swift */; };
		A00000000000000000000038 /* SpotlightService.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000018 /* SpotlightService.swift */; };
		A00000000000000000000039 /* Trie.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000019 /* Trie.swift */; };
		A0000000000000000000003A /* AppState.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0000000000000000000001A /* AppState.swift */; };
		A0000000000000000000003B /* AmbientLightBackground.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0000000000000000000001B /* AmbientLightBackground.swift */; };
		A0000000000000000000003C /* CheckInHeatmapView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0000000000000000000001C /* CheckInHeatmapView.swift */; };
		A0000000000000000000003D /* PolysemousWordView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0000000000000000000001D /* PolysemousWordView.swift */; };
		A0000000000000000000003E /* SearchSheetView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0000000000000000000001E /* SearchSheetView.swift */; };
		A0000000000000000000003F /* WordCardView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0000000000000000000001F /* WordCardView.swift */; };
		A00000000000000000000040 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000020 /* ContentView.swift */; };
		A00000000000000000000041 /* words.json in Resources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000021 /* words.json */; };
		A00000000000000000000042 /* conjugation.json in Resources */ = {isa = PBXBuildFile; fileRef = A00000000000000000000022 /* conjugation.json */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		A00000000000000000000010 /* CroissanteApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CroissanteApp.swift; sourceTree = "<group>"; };
		A00000000000000000000011 /* Colors.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Constants/Colors.swift; sourceTree = "<group>"; };
		A00000000000000000000012 /* DailyRecord.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Models/DailyRecord.swift; sourceTree = "<group>"; };
		A00000000000000000000013 /* LearningRecord.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Models/LearningRecord.swift; sourceTree = "<group>"; };
		A00000000000000000000014 /* SimpleWord.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Models/SimpleWord.swift; sourceTree = "<group>"; };
		A00000000000000000000015 /* AppIconManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Services/AppIconManager.swift; sourceTree = "<group>"; };
		A00000000000000000000016 /* ImagePickerService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Services/ImagePickerService.swift; sourceTree = "<group>"; };
		A00000000000000000000017 /* SRSManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Services/SRSManager.swift; sourceTree = "<group>"; };
		A00000000000000000000018 /* SpotlightService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Services/SpotlightService.swift; sourceTree = "<group>"; };
		A00000000000000000000019 /* Trie.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Utils/Trie.swift; sourceTree = "<group>"; };
		A0000000000000000000001A /* AppState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ViewModels/AppState.swift; sourceTree = "<group>"; };
		A0000000000000000000001B /* AmbientLightBackground.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/Components/AmbientLightBackground.swift; sourceTree = "<group>"; };
		A0000000000000000000001C /* CheckInHeatmapView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/Components/CheckInHeatmapView.swift; sourceTree = "<group>"; };
		A0000000000000000000001D /* PolysemousWordView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/Components/PolysemousWordView.swift; sourceTree = "<group>"; };
		A0000000000000000000001E /* SearchSheetView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/Components/SearchSheetView.swift; sourceTree = "<group>"; };
		A0000000000000000000001F /* WordCardView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/Components/WordCardView.swift; sourceTree = "<group>"; };
		A00000000000000000000020 /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/ContentView.swift; sourceTree = "<group>"; };
		A00000000000000000000021 /* words.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = words.json; sourceTree = "<group>"; };
		A00000000000000000000022 /* conjugation.json */ = {isa = PBXFileReference; lastKnownFileType = text.json; path = conjugation.json; sourceTree = "<group>"; };
		A00000000000000000000023 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		A00000000000000000000005 /* Croissante.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Croissante.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		A00000000000000000000009 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		A00000000000000000000002 = {
			isa = PBXGroup;
			children = (
				A00000000000000000000003 /* Croissante */,
				A00000000000000000000004 /* Products */,
			);
			sourceTree = "<group>";
		};
		A00000000000000000000003 /* Croissante */ = {
			isa = PBXGroup;
			children = (
				A00000000000000000000010 /* CroissanteApp.swift */,
				A00000000000000000000011 /* Colors.swift */,
				A00000000000000000000012 /* DailyRecord.swift */,
				A00000000000000000000013 /* LearningRecord.swift */,
				A00000000000000000000014 /* SimpleWord.swift */,
				A00000000000000000000015 /* AppIconManager.swift */,
				A00000000000000000000016 /* ImagePickerService.swift */,
				A00000000000000000000017 /* SRSManager.swift */,
				A00000000000000000000018 /* SpotlightService.swift */,
				A00000000000000000000019 /* Trie.swift */,
				A0000000000000000000001A /* AppState.swift */,
				A0000000000000000000001B /* AmbientLightBackground.swift */,
				A0000000000000000000001C /* CheckInHeatmapView.swift */,
				A0000000000000000000001D /* PolysemousWordView.swift */,
				A0000000000000000000001E /* SearchSheetView.swift */,
				A0000000000000000000001F /* WordCardView.swift */,
				A00000000000000000000020 /* ContentView.swift */,
				A00000000000000000000021 /* words.json */,
				A00000000000000000000022 /* conjugation.json */,
				A00000000000000000000023 /* Info.plist */,
			);
			path = Croissante;
			sourceTree = "<group>";
		};
		A00000000000000000000004 /* Products */ = {
			isa = PBXGroup;
			children = (
				A00000000000000000000005 /* Croissante.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		A00000000000000000000006 /* Croissante */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A0000000000000000000000B /* Build configuration list for PBXNativeTarget "Croissante" */;
			buildPhases = (
				A00000000000000000000007 /* Sources */,
				A00000000000000000000009 /* Frameworks */,
				A00000000000000000000008 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Croissante;
			productName = Croissante;
			productReference = A00000000000000000000005 /* Croissante.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		A00000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastUpgradeCheck = 2630;
				TargetAttributes = {
					A00000000000000000000006 /* Croissante */ = {
						CreatedOnToolsVersion = 26.0;
					};
				};
			};
			buildConfigurationList = A0000000000000000000000A /* Build configuration list for PBXProject "Croissante" */;
			compatibilityVersion = "Xcode 26.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = A00000000000000000000002;
			productRefGroup = A00000000000000000000004 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				A00000000000000000000006 /* Croissante */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		A00000000000000000000008 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000041 /* words.json in Resources */,
				A00000000000000000000042 /* conjugation.json in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		A00000000000000000000007 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A00000000000000000000030 /* CroissanteApp.swift in Sources */,
				A00000000000000000000031 /* Colors.swift in Sources */,
				A00000000000000000000032 /* DailyRecord.swift in Sources */,
				A00000000000000000000033 /* LearningRecord.swift in Sources */,
				A00000000000000000000034 /* SimpleWord.swift in Sources */,
				A00000000000000000000035 /* AppIconManager.swift in Sources */,
				A00000000000000000000036 /* ImagePickerService.swift in Sources */,
				A00000000000000000000037 /* SRSManager.swift in Sources */,
				A00000000000000000000038 /* SpotlightService.swift in Sources */,
				A00000000000000000000039 /* Trie.swift in Sources */,
				A0000000000000000000003A /* AppState.swift in Sources */,
				A0000000000000000000003B /* AmbientLightBackground.swift in Sources */,
				A0000000000000000000003C /* CheckInHeatmapView.swift in Sources */,
				A0000000000000000000003D /* PolysemousWordView.swift in Sources */,
				A0000000000000000000003E /* SearchSheetView.swift in Sources */,
				A0000000000000000000003F /* WordCardView.swift in Sources */,
				A00000000000000000000040 /* ContentView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		A0000000000000000000000C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				SDKROOT = iphoneos;
			};
			name = Debug;
		};
		A0000000000000000000000D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				SDKROOT = iphoneos;
			};
			name = Release;
		};
		A0000000000000000000000E /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 2;
				ENABLE_TESTABILITY = YES;
				INFOPLIST_FILE = Croissante/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 26.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.jw.Croissante;
				PRODUCT_NAME = Croissante;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		A0000000000000000000000F /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 2;
				INFOPLIST_FILE = Croissante/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 26.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.jw.Croissante;
				PRODUCT_NAME = Croissante;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		A0000000000000000000000A /* Build configuration list for PBXProject "Croissante" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A0000000000000000000000C /* Debug */,
				A0000000000000000000000D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		A0000000000000000000000B /* Build configuration list for PBXNativeTarget "Croissante" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A0000000000000000000000E /* Debug */,
				A0000000000000000000000F /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
/* End XCConfigurationList section */
	};
	rootObject = A00000000000000000000001 /* Project object */;
}
PBXPROJ

# 创建共享 Scheme（给 xcodebuild 使用）
mkdir -p "$WORK_DIR/Croissante.xcodeproj/xcshareddata/xcschemes"
cat > "$WORK_DIR/Croissante.xcodeproj/xcshareddata/xcschemes/Croissante.xcscheme" << 'SCHEME'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2630"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "A00000000000000000000006"
               BuildableName = "Croissante.app"
               BlueprintName = "Croissante"
               ReferencedContainer = "container:Croissante.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "A00000000000000000000006"
            BuildableName = "Croissante.app"
            BlueprintName = "Croissante"
            ReferencedContainer = "container:Croissante.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "A00000000000000000000006"
            BuildableName = "Croissante.app"
            BlueprintName = "Croissante"
            ReferencedContainer = "container:Croissante.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
SCHEME

# 创建 Info.plist
cat > "$WORK_DIR/Croissante/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Croissante</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
PLIST

echo "🔨 编译项目..."
cd "$WORK_DIR"
if xcodebuild -project Croissante.xcodeproj -scheme Croissante -configuration Debug -derivedDataPath "$WORK_DIR/DerivedData" -destination 'generic/platform=iOS Simulator' build; then
    echo "✅ 编译成功！"
    echo ""
    echo "🎉 项目已准备就绪！"
    echo ""
    echo "📱 如何在 Xcode 26 中运行："
    echo "1. 打开 Xcode 26"
    echo "2. 选择 'Open a project or file'"
    echo "3. 导航到: $WORK_DIR/Croissante.xcodeproj"
    echo "4. 选择任意 iOS 模拟器"
    echo "5. 点击运行按钮（▶️）"
    echo ""
    echo "🌟 功能亮点："
    echo "   • iOS 26 Liquid Glass Tab 栏（自动应用）"
    echo "   • 包含 6,000+ 法语单词"
    echo "   • 发现、收藏、个人资料三个标签页"
    echo "   • 完整的状态管理和数据持久化"
    echo "   • 支持中英文双语界面"
    echo ""
    echo "项目文件位于：$WORK_DIR"
else
    echo "❌ 编译失败"
    echo "请确保已安装 Xcode 26 并配置好命令行工具"
    echo "运行: sudo xcode-select --switch /Applications/Xcode.app"
fi
