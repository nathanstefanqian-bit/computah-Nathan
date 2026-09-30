// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Computah",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Computah", targets: ["Computah"])],
    targets: [
        .target(name: "ComputahCore", resources: [.process("Prompts")]),
        .target(name: "ComputahSpeech", linkerSettings: [.linkedLibrary("z")]),
        .executableTarget(name: "Computah", dependencies: ["ComputahCore", "ComputahSpeech"],
                          resources: [.copy("Resources/Sounds")]),
        .executableTarget(name: "ComputahCoreChecks", dependencies: ["ComputahCore", "ComputahSpeech"],
                          path: "Tests/ComputahCoreChecks"),
    ],
    swiftLanguageModes: [.v5]
)
