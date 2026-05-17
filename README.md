# 🧮 超级计算器

一款功能丰富的 iOS 计算器应用，支持基础运算、科学计算、主题切换和自定义背景。

## 📱 功能特性

### 基础功能
✅ 四则运算（加、减、乘、除）
✅ 小数点、正负号、百分比
✅ 退格删除、一键清空
✅ 计算结果自动格式化

### 科学计算
✅ 三角函数（sin、cos、tan）
✅ 平方根、平方、倒数
✅ 自然对数、常用对数
✅ π 和 e 常数

### 个性化设置
✅ 🌙 深色/浅色主题切换
✅ 🖼️ 自定义背景图片
✅ 🔊 按键音效开关
✅ 📳 触觉反馈开关
✅ 🔢 小数位数设置（0-6位）
✅ 🎲 按钮打乱模式

### 其他功能
✅ 📋 计算历史记录（保存最近20条）
✅ 3D Touch 快捷菜单
✅ 大屏机型自动显示科学按钮
✅ 横屏适配

## 📋 系统要求

- iOS 12.0+
- iPhone / iPad

## 🔧 安装与编译

### 1. 克隆项目
git clone https://github.com/Tusi-Toast/iOSSuperCalculator.git
cd iOSSuperCalculator

### 2. 用 Xcode 打开
open SuperCalculator.xcodeproj

### 3. 选择设备并运行
- 选择模拟器（iPhone 8 / iPhone XR 等）
- 或连接真机 iPhone
- 点击 Xcode 的运行按钮 ▶️

### 4. 打包 IPA 文件

在桌面创建 `build_ipa.sh` 脚本，内容如下：

```bash
#!/bin/bash
cd /Users/macbook/Desktop/SuperCalculator

xcodebuild -project SuperCalculator.xcodeproj -scheme SuperCalculator -configuration Release -sdk iphoneos build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "*.app" -path "*/Release-iphoneos/*" 2>/dev/null | head -1)

cd ~/Desktop
rm -rf Payload
mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -r SuperCalculator.ipa Payload/
rm -rf Payload

echo "✅ IPA 已生成: ~/Desktop/SuperCalculator.ipa"
```

执行打包：

```bash
chmod +x ~/Desktop/build_ipa.sh
~/Desktop/build_ipa.sh
```


### 5. 安装到 iPhone
- 使用爱思助手：拖拽 IPA 到应用安装区域
- 或使用命令行：
brew install ios-deploy
ios-deploy --bundle ~/Desktop/SuperCalculator.ipa

### 6. 首次运行信任证书
iPhone 上：设置 → 通用 → VPN与设备管理 → 信任开发者证书

## 👨‍💻 开发者
- 作者: Tusi-Toast
- GitHub: https://github.com/Tusi-Toast

## 📄 许可证
MIT License

⭐ 如果觉得这个项目不错，欢迎给个 Star！
