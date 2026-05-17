import UIKit
import AudioToolbox

// MARK: - 全局枚举
enum ShuffleMode: Int {
    case none = 0, numbers, operators, all
    var description: String {
        switch self {
        case .none: return "不打乱"
        case .numbers: return "数字打乱"
        case .operators: return "符号打乱"
        case .all: return "全部打乱"
        }
    }
}

// MARK: - AppDelegate
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        
        return true
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        
        if let viewController = window?.rootViewController as? ViewController {
            viewController.handleShortcutItem(shortcutItem)
        }
        
        completionHandler(true)
    }
}

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    // MARK: - UI 组件
    var resultLabel: UILabel!
    var processLabel: UILabel!
    var historyButton: UIButton!
    var themeButton: UIButton!
    var settingsButton: UIButton!
    var scientificButtons: [UIButton] = []
    var allButtons: [UIButton] = []
    
    // 背景层
    var backgroundImageView: UIImageView?
    var blurEffectView: UIVisualEffectView?
    var backgroundMask: UIView?
    
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    let buttonTitles = [
        ["AC", "+/-", "%", "÷"], ["7", "8", "9", "×"],
        ["4", "5", "6", "-"], ["1", "2", "3", "+"], ["0", ".", "⌫", "="]
    ]
    
    let scientificTitles = ["sin", "cos", "tan", "√", "x²", "1/x", "ln", "log", "π", "e"]
    
    var leftValue = "", rightValue = "", currentOperation = ""
    var isNewOperation = true
    var historyRecords: [String] = []
    
    var lastCalculationProcess: String = ""
    var lastExpression: String = ""
    var lastResult: String = ""
    
    var isDarkMode = true
    var isSoundEnabled = true
    var isVibrationEnabled = true
    var decimalPlaces = 2
    
    private var isShowingSettings = false
    private var isShowingAbout = false
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSettings()
        loadHistory()
        setupBackground()
        setupUI()
        updateTheme()
        applyBackgroundSettings()
        refreshButtonLayout()
        
        // 准备触觉反馈
        feedbackGenerator.prepare()
        
        // 添加旋转监听
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.createShortcutItems()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 布局更新
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundImageView?.frame = view.bounds
        blurEffectView?.frame = view.bounds
        backgroundMask?.frame = view.bounds
        
        layoutScientificButtons()
        calculateButtonFrames()
    }

    // MARK: - 旋转处理
    @objc func orientationChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            
            let shouldShow = self.shouldShowScientificButtons()
            if shouldShow {
                self.createScientificButtons()
            } else {
                self.scientificButtons.forEach { $0.removeFromSuperview() }
                self.scientificButtons.removeAll()
            }
            
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - 刷新按钮布局
    func refreshButtonLayout() {
        allButtons.forEach { $0.removeFromSuperview() }
        allButtons.removeAll()
        
        let mode = ShuffleMode(rawValue: UserDefaults.standard.integer(forKey: "ShuffleMode")) ?? .none
        var flat = buttonTitles.flatMap { $0 }
        
        if mode == .numbers {
            shuffleSpec(&flat) { Double($0) != nil || $0 == "." }
        } else if mode == .operators {
            shuffleSpec(&flat) { Double($0) == nil && $0 != "." }
        } else if mode == .all {
            flat.shuffle()
        }
        
        for t in flat {
            let btn = UIButton(type: .custom)
            btn.setTitle(t, for: .normal)
            btn.addTarget(self, action: #selector(btnPress(_:)), for: .touchUpInside)
            btn.addTarget(self, action: #selector(btnDown(_:)), for: .touchDown)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .medium)
            view.addSubview(btn)
            allButtons.append(btn)
        }
        
        updateTheme()
        view.setNeedsLayout()
    }

    // MARK: - 打乱辅助方法
    func shuffleSpec(_ t: inout [String], _ f: (String)->Bool) {
        var sub = t.filter(f)
        sub.shuffle()
        var j = 0
        for i in 0..<t.count {
            if f(t[i]) {
                t[i] = sub[j]
                j += 1
            }
        }
    }
    
    // MARK: - 3D Touch 菜单
    func createShortcutItems() {
        var shortcutItems = [UIApplicationShortcutItem]()
        
        let newIcon = UIApplicationShortcutIcon(type: .compose)
        let newItem = UIApplicationShortcutItem(
            type: "com.tusitoast.calculator.new",
            localizedTitle: "新计算",
            localizedSubtitle: "开始新的计算",
            icon: newIcon,
            userInfo: nil
        )
        shortcutItems.append(newItem)
        
        let historyIcon = UIApplicationShortcutIcon(type: .time)
        let historyItem = UIApplicationShortcutItem(
            type: "com.tusitoast.calculator.history",
            localizedTitle: "历史记录",
            localizedSubtitle: "查看最近计算",
            icon: historyIcon,
            userInfo: nil
        )
        shortcutItems.append(historyItem)
        
        let themeIcon = UIApplicationShortcutIcon(type: .love)
        let themeItem = UIApplicationShortcutItem(
            type: "com.tusitoast.calculator.theme",
            localizedTitle: "切换主题",
            localizedSubtitle: isDarkMode ? "切换到白天" : "切换到夜间",
            icon: themeIcon,
            userInfo: nil
        )
        shortcutItems.append(themeItem)
        
        let settingsIcon = UIApplicationShortcutIcon(type: .play)
        let settingsItem = UIApplicationShortcutItem(
            type: "com.tusitoast.calculator.settings",
            localizedTitle: "设置",
            localizedSubtitle: "个性化配置",
            icon: settingsIcon,
            userInfo: nil
        )
        shortcutItems.append(settingsItem)
        
        UIApplication.shared.shortcutItems = shortcutItems
    }
    
    @objc func handleShortcutItem(_ item: UIApplicationShortcutItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch item.type {
            case "com.tusitoast.calculator.new":
                self.clearAll()
            case "com.tusitoast.calculator.history":
                self.historyTapped()
            case "com.tusitoast.calculator.theme":
                self.themeTapped()
            case "com.tusitoast.calculator.settings":
                self.settingsTapped()
            default:
                break
            }
        }
    }
    
    // MARK: - 背景逻辑
    func setupBackground() {
    backgroundImageView = UIImageView(frame: view.bounds)
    backgroundImageView?.clipsToBounds = true
    backgroundImageView?.contentMode = .scaleAspectFill  // 保持这个不变
    backgroundImageView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]  // 添加这一行
    view.addSubview(backgroundImageView!)
        
        let style: UIBlurEffect.Style = isDarkMode ? .dark : .light
        blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        blurEffectView?.frame = view.bounds
        blurEffectView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blurEffectView!)
        
        backgroundMask = UIView(frame: view.bounds)
        backgroundMask?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundMask!)
        
        backgroundImageView?.isHidden = true
        blurEffectView?.isHidden = true
        backgroundMask?.isHidden = true
    }
    
    func applyBackgroundSettings() {
        let hasBg = UserDefaults.standard.bool(forKey: "UseCustomBackground")
        backgroundImageView?.isHidden = !hasBg
        blurEffectView?.isHidden = !hasBg
        backgroundMask?.isHidden = !hasBg
        
       if hasBg {
            let alpha = UserDefaults.standard.float(forKey: "BgAlpha")
            backgroundMask?.backgroundColor = (isDarkMode ? UIColor.black : UIColor.white).withAlphaComponent(CGFloat(1.0 - alpha))
            
            let blurVal = UserDefaults.standard.float(forKey: "BgBlur")
            blurEffectView?.alpha = CGFloat(blurVal)
            
            // 删除 mode 那行，强制使用 scaleAspectFill
            backgroundImageView?.contentMode = .scaleAspectFill
            
            if let data = UserDefaults.standard.data(forKey: "CustomBackgroundImage") {
                backgroundImageView?.image = UIImage(data: data)
                        }
                    }
                    updateTheme()
                } 
 // MARK: - 相册代理
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let edited = info[.editedImage] as? UIImage
        let original = info[.originalImage] as? UIImage
        
        if let image = edited ?? original {
            // 裁剪图片为屏幕比例
            let screenSize = UIScreen.main.bounds.size
            let screenRatio = screenSize.width / screenSize.height
            let imageRatio = image.size.width / image.size.height
            
            var cropRect: CGRect
            if imageRatio > screenRatio {
                // 图片更宽，裁剪宽度
                let cropWidth = image.size.height * screenRatio
                cropRect = CGRect(x: (image.size.width - cropWidth) / 2,
                                 y: 0,
                                 width: cropWidth,
                                 height: image.size.height)
            } else {
                // 图片更高，裁剪高度
                let cropHeight = image.size.width / screenRatio
                cropRect = CGRect(x: 0,
                                 y: (image.size.height - cropHeight) / 2,
                                 width: image.size.width,
                                 height: cropHeight)
            }
            
            if let croppedImage = image.cgImage?.cropping(to: cropRect) {
                let finalImage = UIImage(cgImage: croppedImage)
                if let imageData = finalImage.jpegData(compressionQuality: 0.8) {
                    UserDefaults.standard.set(true, forKey: "UseCustomBackground")
                    UserDefaults.standard.set(imageData, forKey: "CustomBackgroundImage")
                    applyBackgroundSettings()
                }
            } else {
                // 如果裁剪失败，直接使用原图
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    UserDefaults.standard.set(true, forKey: "UseCustomBackground")
                    UserDefaults.standard.set(imageData, forKey: "CustomBackgroundImage")
                    applyBackgroundSettings()
                }
            }
        }
        picker.dismiss(animated: true, completion: nil)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    // MARK: - UI 构建
    func setupUI() {
        processLabel = UILabel()
        processLabel.text = ""
        processLabel.textAlignment = .right
        processLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        processLabel.textColor = .gray
        processLabel.alpha = 0.7
        processLabel.adjustsFontSizeToFitWidth = true
        processLabel.minimumScaleFactor = 0.5
        processLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(processLabel)
        
        resultLabel = UILabel()
        resultLabel.text = "0"
        resultLabel.textAlignment = .right
        resultLabel.font = UIFont.systemFont(ofSize: getResultLabelFontSize(), weight: .light)
        resultLabel.adjustsFontSizeToFitWidth = true
        resultLabel.minimumScaleFactor = 0.5
        resultLabel.layer.borderWidth = 1.0
        resultLabel.layer.cornerRadius = 8
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultLabel)
        
        historyButton = createSmallBtn(title: "📋", action: #selector(historyTapped))
        themeButton = createSmallBtn(title: "🌙", action: #selector(themeTapped))
        settingsButton = createSmallBtn(title: "⚙️", action: #selector(settingsTapped))
        
        [historyButton, themeButton, settingsButton].forEach { view.addSubview($0!) }
        
        let safeArea = view.safeAreaLayoutGuide
        let isSmallScreen = view.bounds.height <= 568
        
        NSLayoutConstraint.activate([
            processLabel.bottomAnchor.constraint(equalTo: resultLabel.topAnchor, constant: -8),
            processLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            processLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            processLabel.heightAnchor.constraint(equalToConstant: isSmallScreen ? 12 : 15),
            
            resultLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: isSmallScreen ? 10 : 20),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resultLabel.heightAnchor.constraint(equalToConstant: isSmallScreen ? 70 : 100),
            
            themeButton.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: isSmallScreen ? 10 : 15),
            themeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            themeButton.widthAnchor.constraint(equalToConstant: isSmallScreen ? 40 : 50),
            themeButton.heightAnchor.constraint(equalToConstant: isSmallScreen ? 40 : 50),
            
            historyButton.centerYAnchor.constraint(equalTo: themeButton.centerYAnchor),
            historyButton.trailingAnchor.constraint(equalTo: themeButton.leadingAnchor, constant: isSmallScreen ? -20 : -30),
            historyButton.widthAnchor.constraint(equalToConstant: isSmallScreen ? 40 : 50),
            historyButton.heightAnchor.constraint(equalToConstant: isSmallScreen ? 40 : 50),
            
            settingsButton.centerYAnchor.constraint(equalTo: themeButton.centerYAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: themeButton.trailingAnchor, constant: isSmallScreen ? 20 : 30),
            settingsButton.widthAnchor.constraint(equalToConstant: isSmallScreen ? 40 : 50),
            settingsButton.heightAnchor.constraint(equalToConstant: isSmallScreen ? 40 : 50)
            ])
        
        if shouldShowScientificButtons() {
            createScientificButtons()
        }
    }
    
    func getResultLabelFontSize() -> CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        if screenHeight <= 568 {
            return 48
        } else if screenHeight <= 667 {
            return 56
        } else {
            return 60
        }
    }
    
    func createSmallBtn(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 26)
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }
    
    // MARK: - 机型判断
    func shouldShowScientificButtons() -> Bool {
        let screenHeight = max(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        let screenWidth = min(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        let isLandscape = view.bounds.width > view.bounds.height
        
        if isLandscape {
            return true
        }
        
        if screenHeight <= 568 {
            return false
        }
        
        let isMaxModel = screenHeight >= 896 && screenWidth >= 414
        let isPlusModel = !isMaxModel && screenHeight == 736 && screenWidth == 414
        
        return isPlusModel || isMaxModel
    }
    
    // MARK: - 科学计算按钮
    func createScientificButtons() {
        scientificButtons.forEach { $0.removeFromSuperview() }
        scientificButtons.removeAll()
        
        let screenHeight = max(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        let screenWidth = min(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        let isPlusModel = screenHeight == 736 && screenWidth == 414
        let isLandscape = view.bounds.width > view.bounds.height
        
        let buttonFontSize: CGFloat = isPlusModel ? 13 : 16
        let titlesToShow = (isPlusModel && !isLandscape) ? Array(scientificTitles.prefix(8)) : scientificTitles
        
        for (index, title) in titlesToShow.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: buttonFontSize, weight: .medium)
            button.backgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.3)
            button.layer.cornerRadius = 6
            button.addTarget(self, action: #selector(scientificButtonTapped(_:)), for: .touchUpInside)
            button.tag = index
            view.addSubview(button)
            scientificButtons.append(button)
        }
    }
    
    func layoutScientificButtons() {
        guard !scientificButtons.isEmpty else { return }
        
        let screenHeight = max(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        let screenWidth = min(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        let isPlusModel = screenHeight == 736 && screenWidth == 414
        let isSmallScreen = view.bounds.height <= 568
        let isLandscape = view.bounds.width > view.bounds.height
        
        let themeButtonBottom = themeButton.frame.maxY
        let startY = themeButtonBottom + (isSmallScreen ? 8 : 12)
        
        var buttonsPerRow = isPlusModel ? 8 : 5
        if isLandscape {
            buttonsPerRow = 8
        }
        
        let spacing: CGFloat = isLandscape ? 12 : (isPlusModel ? 8 : 10)
        let horizontalPadding: CGFloat = isLandscape ? 30 : 20
        
        let buttonWidth = (view.bounds.width - horizontalPadding * 2 - CGFloat(buttonsPerRow - 1) * spacing) / CGFloat(buttonsPerRow)
        let buttonHeight: CGFloat = isLandscape ? 44 : (isPlusModel ? 36 : 40)
        
        for (index, button) in scientificButtons.enumerated() {
            let row = index / buttonsPerRow
            let col = index % buttonsPerRow
            let x = horizontalPadding + CGFloat(col) * (buttonWidth + spacing)
            let y = startY + CGFloat(row) * (buttonHeight + spacing)
            button.frame = CGRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
        }
    }
    
    func updateScientificButtonsTheme() {
        for button in scientificButtons {
            if isDarkMode {
                button.backgroundColor = UIColor(white: 0.25, alpha: 0.8)
                button.setTitleColor(.white, for: .normal)
            } else {
                button.backgroundColor = UIColor(white: 0.9, alpha: 0.8)
                button.setTitleColor(.darkGray, for: .normal)
            }
        }
    }
    
    @objc func scientificButtonTapped(_ sender: UIButton) {
        guard let title = sender.currentTitle else { return }
        
        if isVibrationEnabled {
            feedbackGenerator.impactOccurred()
        }
        
        let currentText = resultLabel.text ?? "0"
        let currentValue = Double(currentText) ?? 0
        
        var result: Double = 0
        var operation = ""
        
        switch title {
        case "sin":
            result = sin(currentValue * .pi / 180)
            operation = "sin(\(currentValue))"
        case "cos":
            result = cos(currentValue * .pi / 180)
            operation = "cos(\(currentValue))"
        case "tan":
            result = tan(currentValue * .pi / 180)
            operation = "tan(\(currentValue))"
        case "√":
            result = sqrt(currentValue)
            operation = "√(\(currentValue))"
        case "x²":
            result = currentValue * currentValue
            operation = "(\(currentValue))²"
        case "1/x":
            result = 1 / currentValue
            operation = "1/\(currentValue)"
        case "ln":
            result = log(currentValue)
            operation = "ln(\(currentValue))"
        case "log":
            result = log10(currentValue)
            operation = "log(\(currentValue))"
        case "π":
            result = Double.pi
            operation = "π"
            resultLabel.text = "\(result)"
            leftValue = "\(result)"
            processLabel.text = operation
            return
        case "e":
            result = M_E
            operation = "e"
            resultLabel.text = "\(result)"
            leftValue = "\(result)"
            processLabel.text = operation
            return
        default:
            return
        }
        
        let formatted = fmt(result)
        resultLabel.text = formatted
        leftValue = formatted
        rightValue = ""
        currentOperation = ""
        isNewOperation = true
        
        lastExpression = operation
        processLabel.text = lastExpression
        
        let historyItem = "\(operation) = \(formatted)"
        historyRecords.insert(historyItem, at: 0)
        if historyRecords.count > 20 {
            historyRecords.removeLast()
        }
        saveHistory()
    }
    
    // MARK: - 数字键盘布局
    func calculateButtonFrames() {
        view.layoutIfNeeded()
        
        let isSmallScreen = view.bounds.height <= 568
        let isLandscape = view.bounds.width > view.bounds.height
        
        var scientificBottom: CGFloat = 0
        
        if !scientificButtons.isEmpty {
            if let lastButton = scientificButtons.last {
                scientificBottom = lastButton.frame.maxY
            } else {
                scientificBottom = themeButton.frame.maxY + (isSmallScreen ? 8 : 12)
            }
        } else {
            scientificBottom = themeButton.frame.maxY + (isSmallScreen ? 8 : 12)
        }
        
        let numberPadStartY = scientificBottom + (isSmallScreen ? 8 : 12)
        
        let screenWidth = view.bounds.width
        let horizontalPadding: CGFloat = isLandscape ? 30 : (isSmallScreen ? 40 : 60)
        let spacing: CGFloat = isLandscape ? 12 : (isSmallScreen ? 10 : 14)
        
        let side = max((screenWidth - horizontalPadding - 3 * spacing) / 4, 40)
        
        let totalButtonsWidth = 4 * side + 3 * spacing
        let hPadding = max((screenWidth - totalButtonsWidth) / 2, 8)
        
        let totalNumberPadHeight = 5 * side + 4 * spacing
        let bottomSpacing: CGFloat = 8
        
        let maxAllowedY: CGFloat
        
        if view.safeAreaInsets.bottom > 0 {
            maxAllowedY = view.bounds.height - view.safeAreaInsets.bottom - bottomSpacing - side
        } else {
            maxAllowedY = view.bounds.height - bottomSpacing - side
        }
        
        var finalStartY = numberPadStartY
        
        if finalStartY + totalNumberPadHeight > maxAllowedY + side {
            finalStartY = max(scientificBottom + 5, maxAllowedY - totalNumberPadHeight + side)
        }
        
        if finalStartY + totalNumberPadHeight > view.bounds.height - bottomSpacing {
            finalStartY = view.bounds.height - totalNumberPadHeight - bottomSpacing
        }
        
        for (idx, btn) in allButtons.enumerated() {
            let r = idx / 4
            let c = idx % 4
            btn.frame = CGRect(x: hPadding + CGFloat(c) * (side + spacing),
                               y: finalStartY + CGFloat(r) * (side + spacing),
                               width: side,
                               height: side)
            btn.layer.cornerRadius = side / 2
            btn.titleLabel?.font = UIFont.systemFont(ofSize: side * 0.4, weight: .medium)
        }
    }
    
    // MARK: - 按钮点击事件
    @objc func btnDown(_ s: UIButton) {
        if isVibrationEnabled {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        }
        
        if isSoundEnabled {
            AudioServicesPlaySystemSound(1104)
        }
        
        s.alpha = 0.3
    }
    
    @objc func btnPress(_ s: UIButton) {
        s.alpha = UserDefaults.standard.bool(forKey: "UseCustomBackground") ? 0.8 : 1.0
        guard let t = s.currentTitle else { return }
        
        switch t {
        case "0"..."9":
            handleNum(t)
        case ".":
            handleDec()
        case "AC":
            clearAll()
        case "⌫":
            back()
        case "+", "-", "×", "÷":
            op(t)
        case "=":
            calc()
        case "+/-":
            pm()
        case "%":
            pct()
        default:
            break
        }
    }
    
    func handleNum(_ n: String) {
        if isNewOperation {
            if currentOperation.isEmpty {
                leftValue = ""
            } else {
                rightValue = ""
            }
            isNewOperation = false
        }
        
        if currentOperation.isEmpty {
            leftValue += n
            resultLabel.text = leftValue
        } else {
            rightValue += n
            resultLabel.text = rightValue
        }
    }
    
    func op(_ o: String) {
        if !leftValue.isEmpty && !rightValue.isEmpty {
            calc()
        }
        currentOperation = o
        isNewOperation = true
    }
    
    @objc func clearAll() {
        leftValue = ""
        rightValue = ""
        currentOperation = ""
        resultLabel.text = "0"
        isNewOperation = true
        
        if !lastCalculationProcess.isEmpty {
            processLabel.text = lastExpression
        } else {
            processLabel.text = ""
        }
    }
    
    func back() {
        if !rightValue.isEmpty {
            rightValue.removeLast()
            resultLabel.text = rightValue.isEmpty ? "0" : rightValue
        } else if !leftValue.isEmpty {
            leftValue.removeLast()
            resultLabel.text = leftValue.isEmpty ? "0" : leftValue
        }
    }
    
    func handleDec() {
        if currentOperation.isEmpty {
            if !leftValue.contains(".") {
                leftValue += leftValue.isEmpty ? "0." : "."
            }
            resultLabel.text = leftValue
        } else {
            if !rightValue.contains(".") {
                rightValue += rightValue.isEmpty ? "0." : "."
            }
            resultLabel.text = rightValue
        }
        isNewOperation = false
    }
    
    func pm() {
        if let v = Double(resultLabel.text ?? "0") {
            let r = fmt(-v)
            if currentOperation.isEmpty {
                leftValue = r
            } else {
                rightValue = r
            }
            resultLabel.text = r
        }
    }
    
    func pct() {
        if let v = Double(resultLabel.text ?? "0") {
            let r = fmt(v / 100)
            if currentOperation.isEmpty {
                leftValue = r
            } else {
                rightValue = r
            }
            resultLabel.text = r
        }
    }
    
    func calc() {
        guard let l = Double(leftValue), let r = Double(rightValue) else { return }
        
        var res: Double = 0
        
        switch currentOperation {
        case "+":
            res = l + r
        case "-":
            res = l - r
        case "×":
            res = l * r
        case "÷":
            res = r != 0 ? l / r : 0
        default:
            return
        }
        
        let formatted = fmt(res)
        
        let process = "\(leftValue) \(currentOperation) \(rightValue) = \(formatted)"
        
        lastCalculationProcess = process
        lastExpression = "\(leftValue) \(currentOperation) \(rightValue)"
        lastResult = formatted
        
        processLabel.text = lastExpression
        processLabel.alpha = 1.0
        
        historyRecords.insert(process, at: 0)
        if historyRecords.count > 20 {
            historyRecords.removeLast()
        }
        
        saveHistory()
        
        leftValue = formatted
        rightValue = ""
        currentOperation = ""
        resultLabel.text = formatted
        isNewOperation = true
    }
    
    func fmt(_ n: Double) -> String {
        let f = NumberFormatter()
        f.maximumFractionDigits = decimalPlaces
        f.minimumFractionDigits = 0
        f.numberStyle = .decimal
        f.groupingSeparator = ""
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    
    @objc func themeTapped() {
        isDarkMode.toggle()
        updateTheme()
        applyBackgroundSettings()
        saveSettings()
        createShortcutItems()
    }
    
    func updateTheme() {
        guard resultLabel != nil else { return }
        
        let hasBg = UserDefaults.standard.bool(forKey: "UseCustomBackground")
        let bg = isDarkMode ? UIColor.black : UIColor(white: 0.95, alpha: 1.0)
        let txt = isDarkMode ? UIColor.white : UIColor.black
        
        view.backgroundColor = bg
        resultLabel.textColor = txt
        processLabel.textColor = isDarkMode ? UIColor.lightGray : UIColor.darkGray
        resultLabel.layer.borderColor = txt.withAlphaComponent(0.3).cgColor
        themeButton.setTitle(isDarkMode ? "🌙" : "☀️", for: .normal)
        
        [historyButton, themeButton, settingsButton].forEach { $0.tintColor = txt }
        
        updateScientificButtonsTheme()
        
        let operatorColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        let functionColor = isDarkMode ? UIColor.lightGray : UIColor(white: 0.8, alpha: 1.0)
        let numberBgColor = isDarkMode ? UIColor(white: 0.2, alpha: 1.0) : UIColor.white
        
        for btn in allButtons {
            let t = btn.currentTitle ?? ""
            btn.alpha = hasBg ? 0.75 : 1.0
            
            if ["÷", "×", "-", "+", "="].contains(t) {
                btn.backgroundColor = operatorColor
                btn.setTitleColor(.white, for: .normal)
            } else if ["AC", "+/-", "%", "⌫"].contains(t) {
                btn.backgroundColor = functionColor
                btn.setTitleColor(isDarkMode ? .white : .black, for: .normal)
            } else {
                btn.backgroundColor = numberBgColor
                btn.setTitleColor(txt, for: .normal)
            }
        }
    }
    
    @objc func settingsTapped() {
        guard !isShowingSettings else { return }
        isShowingSettings = true
        
        let settingsVC = SettingsViewController()
        settingsVC.mainViewController = self
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .fullScreen
        
        present(nav, animated: true)
    }
    
    @objc func historyTapped() {
        let alert = UIAlertController(title: "历史记录", message: nil, preferredStyle: .actionSheet)
        
        if historyRecords.isEmpty {
            alert.message = "暂无历史记录"
        } else {
            let recentHistory = historyRecords.prefix(10)
            for record in recentHistory {
                let action = UIAlertAction(title: record, style: .default) { [weak self] _ in
                    self?.useHistoryRecord(record)
                }
                alert.addAction(action)
            }
        }
        
        if !historyRecords.isEmpty {
            alert.addAction(UIAlertAction(title: "清空历史", style: .destructive) { [weak self] _ in
                self?.historyRecords.removeAll()
                self?.saveHistory()
            })
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = historyButton
            popoverController.sourceRect = historyButton.bounds
        }
        
        present(alert, animated: true)
    }
    
    func useHistoryRecord(_ record: String) {
        let components = record.components(separatedBy: " = ")
        if components.count == 2 {
            let expression = components[0]
            let result = components[1]
            
            processLabel.text = expression
            resultLabel.text = result
            
            leftValue = result
            rightValue = ""
            currentOperation = ""
            isNewOperation = true
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(isDarkMode, forKey: "DarkMode")
        UserDefaults.standard.set(isSoundEnabled, forKey: "SoundEnabled")
        UserDefaults.standard.set(isVibrationEnabled, forKey: "VibrationEnabled")
        UserDefaults.standard.set(decimalPlaces, forKey: "DecimalPlaces")
    }
    
    func loadSettings() {
        isDarkMode = UserDefaults.standard.bool(forKey: "DarkMode")
        isSoundEnabled = UserDefaults.standard.object(forKey: "SoundEnabled") as? Bool ?? true
        isVibrationEnabled = UserDefaults.standard.object(forKey: "VibrationEnabled") as? Bool ?? true
        decimalPlaces = UserDefaults.standard.object(forKey: "DecimalPlaces") as? Int ?? 2
        
        if UserDefaults.standard.object(forKey: "BgAlpha") == nil {
            UserDefaults.standard.set(0.8, forKey: "BgAlpha")
        }
        if UserDefaults.standard.object(forKey: "BgBlur") == nil {
            UserDefaults.standard.set(0.5, forKey: "BgBlur")
        }
    }
    
    func saveHistory() {
        UserDefaults.standard.set(historyRecords, forKey: "CalculationHistory")
    }
    
    func loadHistory() {
        if let savedHistory = UserDefaults.standard.array(forKey: "CalculationHistory") as? [String] {
            historyRecords = savedHistory
        }
    }
    
    func settingsDidDismiss() {
        isShowingSettings = false
    }
    
    func showAbout() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard !self.isShowingAbout else {
                return
            }
            
            if let presentedVC = self.presentedViewController {
                presentedVC.dismiss(animated: true) {
                    self.presentAbout()
                }
            } else {
                self.presentAbout()
            }
        }
    }
    
    private func presentAbout() {
        isShowingAbout = true
        
        let aboutVC = AboutDetailViewController()
        aboutVC.isDarkMode = isDarkMode
        aboutVC.modalPresentationStyle = .overFullScreen
        aboutVC.modalTransitionStyle = .crossDissolve
        
        aboutVC.onDismiss = { [weak self] in
            self?.isShowingAbout = false
        }
        
        present(aboutVC, animated: true)
    }
}

// MARK: - 设置界面
class SettingsViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    weak var mainViewController: ViewController?
    private var isProcessingAbout = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "个性化设置"
        view.backgroundColor = isDarkMode ? UIColor(white: 0.1, alpha: 1) : .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(close))
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "返回", style: .plain, target: nil, action: nil)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mainViewController?.settingsDidDismiss()
    }
    
    var isDarkMode: Bool {
        return UserDefaults.standard.bool(forKey: "DarkMode")
    }
    
    @objc func close() {
        mainViewController?.refreshButtonLayout()
        mainViewController?.applyBackgroundSettings()
        dismiss(animated: true)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return [2, 2, 4, 1][section]
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return ["交互", "计算", "背景", "关于"][section]
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = isDarkMode ? .lightGray : .darkGray
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
        
        cell.backgroundColor = isDarkMode ? UIColor(white: 0.15, alpha: 1.0) : .white
        cell.textLabel?.textColor = isDarkMode ? .white : .black
        cell.detailTextLabel?.textColor = isDarkMode ? .lightGray : .gray
        
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = "按键音效"
            cell.accessoryView = createSwitch(key: "SoundEnabled")
            
        case (0, 1):
            cell.textLabel?.text = "触觉反馈"
            cell.accessoryView = createSwitch(key: "VibrationEnabled")
            
        case (1, 0):
            cell.textLabel?.text = "小数位数"
            cell.detailTextLabel?.text = "\(UserDefaults.standard.integer(forKey: "DecimalPlaces"))"
            cell.accessoryType = .disclosureIndicator
            
        case (1, 1):
            cell.textLabel?.text = "打乱模式"
            let mode = ShuffleMode(rawValue: UserDefaults.standard.integer(forKey: "ShuffleMode")) ?? .none
            cell.detailTextLabel?.text = mode.description
            cell.accessoryType = .disclosureIndicator
            
        case (2, 0):
            cell.textLabel?.text = "选取背景图"
            let hasBg = UserDefaults.standard.bool(forKey: "UseCustomBackground")
            cell.detailTextLabel?.text = hasBg ? "已选择" : "未选择"
            cell.accessoryType = .disclosureIndicator
            
        case (2, 1):
            cell.textLabel?.text = "模糊度"
            cell.accessoryView = createSlider(key: "BgBlur")
            
        case (2, 2):
            cell.textLabel?.text = "透明度"
            cell.accessoryView = createSlider(key: "BgAlpha")
            
        case (2, 3):
            cell.textLabel?.text = "填充方式"
            let seg = UISegmentedControl(items: ["填充", "适应"])
            seg.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "BgContentMode")
            seg.addTarget(self, action: #selector(modeCh(_:)), for: .valueChanged)
            seg.tintColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
            cell.accessoryView = seg
            
        case (3, 0):
            cell.textLabel?.text = "关于"
            cell.detailTextLabel?.text = "版本信息"
            cell.accessoryType = .disclosureIndicator
            
        default:
            break
        }
        
        return cell
    }
    
    func createSwitch(key: String) -> UISwitch {
        let s = UISwitch()
        s.isOn = UserDefaults.standard.bool(forKey: key)
        s.addTarget(self, action: #selector(swCh(_:)), for: .valueChanged)
        s.accessibilityLabel = key
        s.onTintColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        return s
    }
    
    @objc func swCh(_ sender: UISwitch) {
        if let k = sender.accessibilityLabel {
            UserDefaults.standard.set(sender.isOn, forKey: k)
        }
    }
    
    func createSlider(key: String) -> UISlider {
        let s = UISlider(frame: CGRect(x: 0, y: 0, width: 150, height: 30))
        s.value = UserDefaults.standard.float(forKey: key)
        s.accessibilityLabel = key
        s.addTarget(self, action: #selector(sdCh(_:)), for: .valueChanged)
        s.minimumTrackTintColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        return s
    }
    
    @objc func sdCh(_ sender: UISlider) {
        UserDefaults.standard.set(sender.value, forKey: sender.accessibilityLabel ?? "")
        mainViewController?.applyBackgroundSettings()
    }
    
    @objc func modeCh(_ sender: UISegmentedControl) {
        UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: "BgContentMode")
        mainViewController?.applyBackgroundSettings()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 && indexPath.row == 1 {
            let alert = UIAlertController(title: "打乱模式", message: "请选择按钮打乱方式", preferredStyle: .actionSheet)
            
            let modes: [ShuffleMode] = [.none, .numbers, .operators, .all]
            for mode in modes {
                let action = UIAlertAction(title: mode.description, style: .default) { [weak self] _ in
                    UserDefaults.standard.set(mode.rawValue, forKey: "ShuffleMode")
                    self?.mainViewController?.refreshButtonLayout()
                    tableView.reloadRows(at: [indexPath], with: .automatic)
                }
                alert.addAction(action)
            }
            
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            
            if let popoverController = alert.popoverPresentationController {
                popoverController.sourceView = tableView.cellForRow(at: indexPath)
                popoverController.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
            }
            
            present(alert, animated: true)
        }
        else if indexPath.section == 1 && indexPath.row == 0 {
            let alert = UIAlertController(title: "小数位数", message: "选择保留的小数位数", preferredStyle: .actionSheet)
            
            for i in 0...6 {
                let action = UIAlertAction(title: "\(i) 位", style: .default) { [weak self] _ in
                    UserDefaults.standard.set(i, forKey: "DecimalPlaces")
                    self?.mainViewController?.decimalPlaces = i
                    tableView.reloadRows(at: [indexPath], with: .automatic)
                }
                alert.addAction(action)
            }
            
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            
            if let popoverController = alert.popoverPresentationController {
                popoverController.sourceView = tableView.cellForRow(at: indexPath)
                popoverController.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
            }
            
            present(alert, animated: true)
        }
        else if indexPath.section == 2 && indexPath.row == 0 {
            showBackgroundImageOptions()
        }
        else if indexPath.section == 3 && indexPath.row == 0 {
            let aboutVC = AboutDetailViewController()
            aboutVC.isDarkMode = isDarkMode
            aboutVC.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(aboutVC, animated: true)
        }
    }
    
    func showBackgroundImageOptions() {
        let alert = UIAlertController(title: "背景图设置", message: "请选择操作", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📷 从相册选择", style: .default) { _ in
            self.pickImageFromLibrary()
        })
        
        if UserDefaults.standard.bool(forKey: "UseCustomBackground") {
            alert.addAction(UIAlertAction(title: "❌ 取消背景图", style: .destructive) { _ in
                self.removeBackgroundImage()
            })
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popoverController = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 2)) {
                popoverController.sourceView = cell
                popoverController.sourceRect = cell.bounds
            }
        }
        
        present(alert, animated: true)
    }
    
    func pickImageFromLibrary() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        present(picker, animated: true)
    }
    
    func removeBackgroundImage() {
        UserDefaults.standard.set(false, forKey: "UseCustomBackground")
        UserDefaults.standard.removeObject(forKey: "CustomBackgroundImage")
        mainViewController?.applyBackgroundSettings()
        tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .automatic)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let edited = info[.editedImage] as? UIImage
        let original = info[.originalImage] as? UIImage
        
        if let image = edited ?? original {
            if let imageData = image.jpegData(compressionQuality: 0.6) {
                UserDefaults.standard.set(true, forKey: "UseCustomBackground")
                UserDefaults.standard.set(imageData, forKey: "CustomBackgroundImage")
                mainViewController?.applyBackgroundSettings()
                tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .automatic)
            }
        }
        picker.dismiss(animated: true)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - 关于详情页面
class AboutDetailViewController: UIViewController {
    
    var isDarkMode: Bool = true
    var onDismiss: (() -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "关于"
        view.backgroundColor = isDarkMode ? UIColor(white: 0.1, alpha: 1) : UIColor(white: 0.95, alpha: 1)
        setupUI()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        view.addGestureRecognizer(tapGesture)
    }
    
    func setupUI() {
        let isSmallScreen = view.bounds.height <= 568
        
        let iconImage = getAppIcon()
        
        let iconImageView = UIImageView(image: iconImage)
        iconImageView.layer.cornerRadius = isSmallScreen ? 15 : 20
        iconImageView.layer.masksToBounds = true
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconImageView)
        
        let titleLabel = UILabel()
        titleLabel.text = "超级计算器"
        titleLabel.font = UIFont.boldSystemFont(ofSize: isSmallScreen ? 24 : 28)
        titleLabel.textColor = isDarkMode ? .white : .black
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let systemVersion = UIDevice.current.systemVersion
        let deviceName = UIDevice.current.modelName
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = isSmallScreen ? 8 : 12
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        
        let currentYear = Calendar.current.component(.year, from: Date())
        
        let infoItems = [
            ("📱 设备型号", deviceName),
            ("⚙️ 系统版本", "iOS \(systemVersion)"),
            ("📦 应用版本", "\(version) (Build \(build))"),
            ("👨‍💻 开发者", "tusitoast"),
            ("📧 联系方式", "2136162256@qq.com"),
            ("© 版权", "\(currentYear) 超级计算器")
        ]
        
        for (title, value) in infoItems {
            let rowView = createInfoRow(title: title, value: value, isSmallScreen: isSmallScreen)
            stackView.addArrangedSubview(rowView)
        }
        
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: isSmallScreen ? 20 : 30),
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: isSmallScreen ? 60 : 80),
            iconImageView.heightAnchor.constraint(equalToConstant: isSmallScreen ? 60 : 80),
            
            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: isSmallScreen ? 10 : 15),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: isSmallScreen ? 20 : 30),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.heightAnchor.constraint(equalToConstant: CGFloat(infoItems.count * (isSmallScreen ? 35 : 44)))
            ])
    }
    
    func getAppIcon() -> UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return createPlaceholderIcon()
    }
    
    func createPlaceholderIcon() -> UIImage {
        let size = CGSize(width: 80, height: 80)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.orange.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
    
    func createInfoRow(title: String, value: String, isSmallScreen: Bool) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = isDarkMode ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.95, alpha: 1)
        containerView.layer.cornerRadius = 6
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: isSmallScreen ? 14 : 16, weight: .medium)
        titleLabel.textColor = isDarkMode ? .lightGray : .darkGray
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: isSmallScreen ? 14 : 16, weight: .regular)
        valueLabel.textColor = isDarkMode ? .white : .black
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.8
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: isSmallScreen ? 90 : 100),
            
            valueLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            valueLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8)
            ])
        
        return containerView
    }
    
    @objc func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if let containerView = view.subviews.first(where: { $0 is UIButton == false }) {
            if !containerView.frame.contains(location) {
                dismiss(animated: true) { [weak self] in
                    self?.onDismiss?()
                }
            }
        }
    }
}

// MARK: - UIDevice 扩展
extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        if identifier == "x86_64" || identifier == "arm64" {
            return "Simulator"
        }
        
        return identifier
    }
}
