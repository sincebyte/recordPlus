// swift-tools-version: 5.9
// This project uses XcodeGen (project.yml) for the Xcode project.
// To build: run ./build.sh or:
//   xcodegen generate && xcodebuild -project RecordPlusPlus.xcodeproj -scheme RecordPlusPlus build
import PackageDescription

let package = Package(
    name: "RecordPlusPlus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RecordPlusPlus",
            path: "Sources/RecordPlusPlus",
            resources: [
                .process("AlphaGenerator/ChromaKeyShader.metal")
            ]
        )
    ]
)