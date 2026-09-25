// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "background_downloader", path: "../.packages/background_downloader-9.5.9"),
        .package(name: "file_picker_darwin", path: "../.packages/file_picker_darwin-1.1.0"),
        .package(name: "flutter_gemma", path: "../.packages/flutter_gemma-1.7.0"),
        .package(name: "flutter_secure_storage_darwin", path: "../.packages/flutter_secure_storage_darwin-0.4.0"),
        .package(name: "gal", path: "../.packages/gal-2.3.3"),
        .package(name: "google_sign_in_ios", path: "../.packages/google_sign_in_ios-6.3.5"),
        .package(name: "integration_test", path: "../.packages/integration_test"),
        .package(name: "large_file_handler", path: "../.packages/large_file_handler-0.5.2"),
        .package(name: "package_info_plus", path: "../.packages/package_info_plus-10.2.1"),
        .package(name: "pdfx", path: "../.packages/pdfx-2.11.0"),
        .package(name: "permission_handler_apple", path: "../.packages/permission_handler_apple-9.6.1"),
        .package(name: "share_plus", path: "../.packages/share_plus-13.3.0"),
        .package(name: "shared_preferences_foundation", path: "../.packages/shared_preferences_foundation-2.5.7"),
        .package(name: "sqflite_darwin", path: "../.packages/sqflite_darwin-2.4.3+1"),
        .package(name: "url_launcher_ios", path: "../.packages/url_launcher_ios-6.4.2"),
        .package(name: "wakelock_plus", path: "../.packages/wakelock_plus-1.8.0"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "background-downloader", package: "background_downloader"),
                .product(name: "file-picker-darwin", package: "file_picker_darwin"),
                .product(name: "flutter-gemma", package: "flutter_gemma"),
                .product(name: "flutter-secure-storage-darwin", package: "flutter_secure_storage_darwin"),
                .product(name: "gal", package: "gal"),
                .product(name: "google-sign-in-ios", package: "google_sign_in_ios"),
                .product(name: "integration-test", package: "integration_test"),
                .product(name: "large-file-handler", package: "large_file_handler"),
                .product(name: "package-info-plus", package: "package_info_plus"),
                .product(name: "pdfx", package: "pdfx"),
                .product(name: "permission-handler-apple", package: "permission_handler_apple"),
                .product(name: "share-plus", package: "share_plus"),
                .product(name: "shared-preferences-foundation", package: "shared_preferences_foundation"),
                .product(name: "sqflite-darwin", package: "sqflite_darwin"),
                .product(name: "url-launcher-ios", package: "url_launcher_ios"),
                .product(name: "wakelock-plus", package: "wakelock_plus"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
