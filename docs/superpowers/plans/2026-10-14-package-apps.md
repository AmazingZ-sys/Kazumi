# 多平台本地打包实现计划

目标：统一打包 Android APK、iOS IPA、macOS DMG、Windows EXE/ZIP，支持指定导出目录；默认 macOS Downloads、Windows 系统桌面（包含重定向桌面）。

设计：Python 3.9+ 标准库实现 `scripts/package.py`，复用 Flutter 构建命令；无需改动业务代码或依赖。默认构建当前宿主支持的平台，显式指定不兼容平台时提前失败。输出按版本和时间创建独立子目录，避免覆盖既有文件。IPA 默认未签名，显式提供 ExportOptions.plist 时签名导出；EXE 使用 Inno Setup 6，ZIP 为免安装备选。

执行步骤：
- [x] 先编写并运行脚本测试，覆盖平台限制、默认目录、失败不导出旧包、包含完整 Windows 运行目录、IPA 目录结构与导出隔离。
- [x] 实现参数解析、工具预检、Flutter 构建、平台打包、错误汇总与 dry-run。
- [x] 添加 Inno Setup 模板和中文使用文档，在 README 添加入口。
- [x] 运行单元/文件系统集成测试、CLI dry-run、语法与 diff 检查。真实构建依赖 SDK、证书及宿主系统，单独报告未验证部分。
