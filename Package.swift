// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnyFoundationModels",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .macCatalyst(.v18),
        .visionOS(.v2)
    ],
    products: [
        // Backends
        .library(name: "OllamaFoundationModels", targets: ["OllamaFoundationModels"]),
        .library(name: "ClaudeFoundationModels", targets: ["ClaudeFoundationModels"]),
        .library(name: "ResponseFoundationModels", targets: ["ResponseFoundationModels"]),
        .library(name: "MLXFoundationModels", targets: ["MLXFoundationModels"]),
    ],
    traits: [
        .trait(name: "Ollama"),
        .trait(name: "Claude"),
        .trait(name: "Response"),
        .trait(name: "MLX"),
        .default(enabledTraits: []),
    ],
    dependencies: [
        // Core API
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", from: "1.8.0"),
        // Claude
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.0"),
        // MLX
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6"),
    ],
    targets: [
        // ===== Backend Targets =====
        .target(
            name: "OllamaFoundationModels",
            dependencies: [
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels",
                         condition: .when(traits: ["Ollama"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels",
                         condition: .when(traits: ["Ollama"])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("OLLAMA_ENABLED", .when(traits: ["Ollama"])),
            ]
        ),
        .target(
            name: "ClaudeFoundationModels",
            dependencies: [
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels",
                         condition: .when(traits: ["Claude"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels",
                         condition: .when(traits: ["Claude"])),
                .product(name: "Configuration", package: "swift-configuration",
                         condition: .when(traits: ["Claude"])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("CLAUDE_ENABLED", .when(traits: ["Claude"])),
            ]
        ),
        .target(
            name: "ResponseFoundationModels",
            dependencies: [
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels",
                         condition: .when(traits: ["Response"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels",
                         condition: .when(traits: ["Response"])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("RESPONSE_ENABLED", .when(traits: ["Response"])),
            ]
        ),
        .target(
            name: "MLXFoundationModels",
            dependencies: [
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels",
                         condition: .when(traits: ["MLX"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels",
                         condition: .when(traits: ["MLX"])),
                .product(name: "MLXLLM", package: "mlx-swift-lm",
                         condition: .when(traits: ["MLX"])),
                .product(name: "MLXVLM", package: "mlx-swift-lm",
                         condition: .when(traits: ["MLX"])),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm",
                         condition: .when(traits: ["MLX"])),
                .product(name: "Hub", package: "swift-transformers",
                         condition: .when(traits: ["MLX"])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("MLX_ENABLED", .when(traits: ["MLX"])),
            ]
        ),

        // ===== Tests =====
        .testTarget(
            name: "OllamaFoundationModelsTests",
            dependencies: [
                .target(name: "OllamaFoundationModels", condition: .when(traits: ["Ollama"])),
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels",
                         condition: .when(traits: ["Ollama"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels",
                         condition: .when(traits: ["Ollama"])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("OLLAMA_ENABLED", .when(traits: ["Ollama"])),
            ]
        ),
        .testTarget(
            name: "ClaudeFoundationModelsTests",
            dependencies: [
                .target(name: "ClaudeFoundationModels", condition: .when(traits: ["Claude"])),
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels",
                         condition: .when(traits: ["Claude"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels",
                         condition: .when(traits: ["Claude"])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("CLAUDE_ENABLED", .when(traits: ["Claude"])),
            ]
        ),
        .testTarget(
            name: "ResponseFoundationModelsTests",
            dependencies: [
                .target(name: "ResponseFoundationModels", condition: .when(traits: ["Response"])),
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels",
                         condition: .when(traits: ["Response"])),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels",
                         condition: .when(traits: ["Response"])),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .define("RESPONSE_ENABLED", .when(traits: ["Response"])),
            ]
        ),
    ]
)
