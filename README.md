<div align="center">

<img src=".github/assets/tekmor-icon.svg" width="108" />

# Tekmor

由 CubeCLI 驱动的 STM32 工具箱

**[Ask DeepWiki](https://deepwiki.com/UE-DND/Tekmor)**

</div>

Tekmor 专注于本地 STM32 项目的日常开发工作流：导入 CMake 项目后即可完成配置、构建、固件烧录与芯片复位，并在同一工作台内查看构建日志、串口输出与交互终端。

---

Tekmor 基于 Swift 6 与 SwiftUI 构建。应用内集成对 `STM32CubeCLI`、`CMake`、`Ninja` 与 `arm-none-eabi` 工具链的管理与调度，支持在应用内自动下载并校验所需的 Apple Silicon 原生工具包，无需手动拼接命令行脚本。

主要能力包括：

- **CMake 构建**：支持读取项目预设（CMake Presets）、指定目标与相对路径工具链文件，所有构建产物均输出至 Tekmor 构建缓存。
- **固件烧录与复位**：支持通过 ST-LINK / SWD 或 UART Bootloader 进行校验烧录与复位，也支持直接烧录独立固件镜像（`.elf`、`.axf`、`.out`、`.hex`、`.bin`）。
- **串口与终端工作台**：内置串口监视器与项目终端，支持在应用内实时查看、搜索日志并发送交互指令。

> [!NOTE]
> 1. Tekmor 仅面向 Apple Silicon（`arm64`）架构的 Mac，最低系统要求为 **macOS 15**。
> 2. 使用构建或烧录功能前，需在应用内手动下载并安装相关工具链。

## 从源码构建

- 搭载 Apple Silicon 的 Mac，系统版本为 macOS 15 或更高
- Xcode（支持 Swift 6）

使用 `xcodebuild` 构建 `Tekmor` 应用：

```bash
xcodebuild -project Tekmor.xcodeproj -scheme Tekmor -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode build
```

## 贡献代码

若发现问题，欢迎任何形式的贡献！无论是修复错误、改进功能，还是提升代码质量，我们都非常欢迎您的参与。
