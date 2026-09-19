// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SplitFiles",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SplitFiles", targets: ["SplitFiles"])],
    dependencies: [.package(url: "https://github.com/Lakr233/libghostty-spm.git", revision: "121c8e286d24e21ea1a379da3eaa3556d3a1b8f5")],
    targets: [
        .executableTarget(name: "SplitFiles", dependencies: [.product(name: "GhosttyTerminal", package: "libghostty-spm")])
    ]
)
