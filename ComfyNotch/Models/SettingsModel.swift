import AppKit
import Combine
import Sparkle
import AVKit

class SettingsModel: ObservableObject {
    static let shared = SettingsModel(userDefaults: .standard)

    @Published var selectedTab: SettingsView.Tab = .general
    @Published var selectedNotchTab: Int = 0
    
    
    @Published var isFirstLaunch: Bool = true
    @Published var hasFirstWindowBeenOpenOnce = false
    
    @Published var selectedWidgets: [String] = []
    @Published var isSettingsWindowOpen: Bool = false
    @Published var openStateYOffset = CGFloat(35)
    @Published var snapOpenThreshold: CGFloat = 0.9
    @Published var aiApiKey: String = ""
    
    @Published var selectedProvider: AIProvider = .openAI
    @Published var selectedOpenAIModel: OpenAIModel = .gpt3
    @Published var selectedAnthropicModel: AnthropicModel = .claudeV1
    @Published var selectedGoogleModel: GoogleModel = .palm
    
    @Published var clipboardManagerMaxHistory: Int = 30
    @Published var clipboardManagerPollingIntervalMS: Int = 1000
    
    @Published var fileTrayDefaultFolder: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("ComfyNotch Files", isDirectory: true)
    
    /// ----------- FileTray Settings ----------
    @Published var fileTrayPersistFiles : Bool = false
    @Published var useCustomSaveFolder : Bool = false
    
    /// qr options
    @Published var fileTrayAllowOpenOnLocalhost: Bool = false
    @Published var fileTrayPort: Int = 8000
    @Published var localHostPin: String = "1111"
    
    /// ----------- Notch Settings -----------
    @Published var showDividerBetweenWidgets: Bool = false
    @Published var hoverTargetMode: HoverTarget = .album
    @Published var nowPlayingScrollSpeed: Int = 40
    @Published var enableNotchHUD: Bool = false
    /// Controlling the width of the notch
    @Published var notchMaxWidth: CGFloat = 710
    let setNotchMinWidth: CGFloat = 500
    let setNotchMaxWidth: CGFloat = 1000
    
    /*
     NOTE: this is is very important because this will be what
     the notch will be set to when it is closed, if this is
     <= 0 this is a BIG ISSUE
     this is cuz in `Managers/UIManager.swift` we use this:
     
     let notchHeight = getNotchHeight()
     
     let panelRect = NSRect(
        x: (screenFrame.width - startPanelWidth) / 2,
        y: screenFrame.height - notchHeight - startPanelYOffset,
        width: startPanelWidth,
        height: notchHeight
     )
     */
    @Published var notchMinFallbackHeight: CGFloat = 40
    /// Min and Max Values for the fallback Height
    let notchHeightMin : Int = 35
    let notchHeightMax : Int = 50
    
    /// Function to reset the min fallback height to the default value
    public func resetNotchMinFallbackHeight() {
        notchMinFallbackHeight = 40
    }
    
    
    @Published var quickAccessWidgetDistanceFromLeft: CGFloat = 18
    @Published var oneFingerAction: TouchAction = .none
    @Published var twoFingerAction: TouchAction = .none
    @Published var notchScrollThreshold: CGFloat = 50
    
    /// ---------- Music Player Settings ----------
    @Published var showMusicProvider: Bool = true
    @Published var musicController: MusicController = .mediaRemote
    @Published var overridenMusicProvider: MusicProvider = .none
    
    /// ---------- Camera Settings ----------
    @Published var isCameraFlipped: Bool = false
    /// Suggest Users to enable this for better memory management
    @Published var enableCameraOverlay: Bool = true
    /// This is the amount of time before the camera
    /// overlay hides itself, default will be 20 seconds
    @Published var cameraOverlayTimer: Int = 20
    @Published var cameraQualitySelection: AVCaptureSession.Preset = .high
    
    /// ---------- Messages Settings ----------
    /// This is required to be false on start cuz theres no way
    /// to prompt or make the user silence "Messages" Notifications,
    /// Maybe we can add a prompt later on to ask the user or just
    /// force it down
    @Published var enableMessagesNotifications: Bool = false
    @Published var messagesHandleLimit: Int = 30
    @Published var messagesMessageLimit: Int = 20
    @Published var currentMessageAudioFile: String = ""
    
    /// ---------- Display Settings ----------
    @Published var selectedScreen: NSScreen! = NSScreen.main!
    /// ---------- Animation Settings ----------
    @Published var openingAnimation: String = "iOS"
    @Published var notchBackgroundAnimation: ShaderOption = .ambientGradient
    @Published var enableMetalAnimation: Bool = true
    @Published var constant120FPS: Bool = false
    
    /// ---------- Utils Settings ----------
    /// Set to true at the start, will change if the user wants tp
    /// The thing is that if the user turns this off we have to verify that the
    /// clipboard and the bluetooth listeners are off, or else just dont
    /// let the userr turn it off
    @Published var enableUtilsOption: Bool = true
    @Published var enableClipboardListener: Bool = true
    
    lazy var updaterController: SPUStandardUpdaterController = {
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()
    
    private var cancellables = Set<AnyCancellable>()
    private let defaults: UserDefaults
    
    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        loadSettings()
        
        $isSettingsWindowOpen
            .receive(on: RunLoop.main)
            .sink { isOpen in
                if isOpen {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
    
    func checkForUpdatesSilently() {
        updaterController.updater.checkForUpdatesInBackground()
    }
    
    // MARK: - Save Settings
    
    /// Saves the current settings to UserDefaults
    func saveSettings() {
        
        // Saving the last state for whatever widgets are selected
        defaults.set(selectedWidgets, forKey: "selectedWidgets")
        
        /// ----------------------- Camera Settings -----------------------
        defaults.set(isCameraFlipped, forKey: "isCameraFlipped")
        defaults.set(enableCameraOverlay, forKey: "enableCameraOverlay")
        if cameraOverlayTimer < 5 {
            cameraOverlayTimer = 5
        }
        defaults.set(cameraOverlayTimer, forKey: "cameraOverlayTimer")
        
        /// ----------------------- API Key Settings -----------------------
        /// For some reason the api key was getting called to save even if it was empty
        /// So I had to add this check, prolly gonna have to check that reason out <- TODO
        if !aiApiKey.isEmpty {
            defaults.set(aiApiKey, forKey: "aiApiKey")
        }
        
        /// ----------------------- FileTray Settings ------------------------------------
        /// Save the fileTrayFolder
        /// Set Default for the file tray folder if nothing is found
        fileTrayDefaultFolder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ComfyNotch Files", isDirectory: true)
        /// if we reach here, that means that the fileTray is populated no matter what so we can force it to get stored
        if !fileTrayDefaultFolder.path.isEmpty {
            defaults.set(fileTrayDefaultFolder.path(), forKey: "fileTrayDefaultFolder")
        }
        defaults.set(fileTrayPersistFiles, forKey: "fileTrayPersistFiles")
        defaults.set(fileTrayAllowOpenOnLocalhost, forKey: "fileTrayAllowOpenOnLocalhost")
        
        if fileTrayPort > 0 && fileTrayPort < 65536 {
            defaults.set(fileTrayPort, forKey: "fileTrayPort")
        } else {
            fileTrayPort = 8000 // Default port
            defaults.set(fileTrayPort, forKey: "fileTrayPort")
        }
        
        if localHostPin != "" {
            defaults.set(localHostPin, forKey: "localHostPin")
        } else {
            localHostPin = "1111" // Default pin
            defaults.set(localHostPin, forKey: "localHostPin")
        }
        
        /// ----------------------- ClipBoard Settings -----------------------------------
        if clipboardManagerMaxHistory >= 0 {
            defaults.set(clipboardManagerMaxHistory, forKey: "clipboardManagerMaxHistory")
        }
        if clipboardManagerPollingIntervalMS >= 0 {
            defaults.set(clipboardManagerPollingIntervalMS, forKey: "clipboardManagerPollingIntervalMS")
        }
        /// ----------------------- Notch Settings -------------------------------------
        defaults.set(showDividerBetweenWidgets, forKey: "showDividerBetweenWidgets")
        
        defaults.set(hoverTargetMode.rawValue, forKey: "hoverTargetMode")
        
        if nowPlayingScrollSpeed > 0 {
            defaults.set(nowPlayingScrollSpeed, forKey: "nowPlayingScrollSpeed")
        } else {
            defaults.set(40, forKey: "nowPlayingScrollSpeed")
        }
        defaults.set(enableNotchHUD, forKey: "enableNotchHUD")
        
        if notchMinFallbackHeight <= 0 {
            notchMinFallbackHeight = 40
        }
        defaults.set(notchMinFallbackHeight, forKey: "notchMinFallbackHeight")
        
        /// Make sure that the maxWidth is always > 500 the rest is up to the user to break, maybe add a limit of like 1000
        if notchMaxWidth < setNotchMinWidth {
            notchMaxWidth = setNotchMinWidth
        }
        if notchMaxWidth > setNotchMaxWidth {
            notchMaxWidth = setNotchMaxWidth
        }
        
        defaults.set(notchMaxWidth, forKey: "notchMaxWidth")
        
        defaults.set(quickAccessWidgetDistanceFromLeft, forKey: "quickAccessWidgetDistanceFromLeft")
        
        defaults.set(oneFingerAction.rawValue, forKey: "oneFingerAction")
        defaults.set(twoFingerAction.rawValue, forKey: "twoFingerAction")
        defaults.set(notchScrollThreshold, forKey: "notchScrollThreshold")
        
        /// ----------------------- Music Player Settings -----------------------
        defaults.set(showMusicProvider, forKey: "showMusicProvider")
        defaults.set(musicController.rawValue, forKey: "musicController")
        defaults.set(overridenMusicProvider.rawValue, forKey: "overridenMusicProvider")
        
        /// ----------------------- Messages Settings -----------------------
        defaults.set(enableMessagesNotifications, forKey: "enableMessagesNotifications")
        if messagesHandleLimit < 10 {
            messagesHandleLimit = 10
        }
        defaults.set(messagesHandleLimit, forKey: "messagesHandleLimit")
        
        if messagesMessageLimit < 10 {
            messagesMessageLimit = 10
        }
        defaults.set(messagesMessageLimit, forKey: "messagesMessageLimit")
        
        /// ----------------------- Display Settings -----------------------
        if let screen = selectedScreen {
            /// We Will Set the screen id
            defaults.set(screen.displayID, forKey: "selectedScreenID")
        }
        /// ----------------------- Animation Settings -----------------------
        defaults.set(openingAnimation, forKey: "openingAnimation")
        defaults.set(notchBackgroundAnimation.rawValue, forKey: "notchBackgroundAnimation")
        defaults.set(enableMetalAnimation, forKey: "enableMetalAnimation")
        defaults.set(constant120FPS, forKey: "constant120FPS")
        
        /// ------------ Utils Settings -----------------------
        defaults.set(enableUtilsOption, forKey: "enableUtilsOption")
        defaults.set(enableClipboardListener, forKey: "enableClipboardListener")
    }
    
    // MARK: - Load Settings
    /// Loads the last saved settings from UserDefaults
    func loadSettings() {
        // Load fallback notch height with validation
        if let notchMinFallbackHeight = defaults.object(forKey: "notchMinFallbackHeight") as? Double {
            self.notchMinFallbackHeight = CGFloat(notchMinFallbackHeight > 0 ? notchMinFallbackHeight : 40)
        } else {
            self.notchMinFallbackHeight = CGFloat(40)
        }
        
        // Loading the last state for the settings window
        if let loadedWidgets = defaults.object(forKey: "selectedWidgets") as? [String] {
            self.selectedWidgets = loadedWidgets
        } else {
            // Set default if nothing is saved
            self.selectedWidgets = WidgetRegistry.shared.getDefaultWidgets()
        }
        
        /// ----------------------- Camera Settings -----------------------
        // Loading the last state for camera flip
        if defaults.object(forKey: "isCameraFlipped") != nil {
            self.isCameraFlipped = defaults.bool(forKey: "isCameraFlipped")
        }
        if defaults.object(forKey: "enableCameraOverlay") != nil {
            self.enableCameraOverlay = defaults.bool(forKey: "enableCameraOverlay")
        }
        if let cameraOverlayTimer = defaults.object(forKey: "cameraOverlayTimer") as? Int {
            self.cameraOverlayTimer = cameraOverlayTimer
        } else {
            // Set default if nothing is saved
            self.cameraOverlayTimer = 20
        }
        
        /// ----------------------- API Key Settings -----------------------
        // Loading the last api_key the user entered
        if let apiKey = defaults.string(forKey: "aiApiKey") {
            self.aiApiKey = apiKey
        }
        
        /// ----------------------- FileTray Settings ------------------------------------
        if let fileTrayDefaultFolder = defaults.string(forKey: "fileTrayDefaultFolder") {
            self.fileTrayDefaultFolder = URL(fileURLWithPath: fileTrayDefaultFolder)
        }
        if let fileTrayPersistFiles = defaults.object(forKey: "fileTrayPersistFiles") as? Bool {
            self.fileTrayPersistFiles = fileTrayPersistFiles
        }
        
        if let fileTrayAllowOpenOnLocalhost = defaults.object(forKey: "fileTrayAllowOpenOnLocalhost") as? Bool {
            self.fileTrayAllowOpenOnLocalhost = fileTrayAllowOpenOnLocalhost
        } else {
            self.fileTrayAllowOpenOnLocalhost = false
        }
        
        if let fileTrayPort = defaults.object(forKey: "fileTrayPort") as? Int {
            self.fileTrayPort = fileTrayPort
        } else {
            self.fileTrayPort = 8000 // Default port
        }
        
        if let localHostPin = defaults.string(forKey: "localHostPin") {
            self.localHostPin = localHostPin
        } else {
            self.localHostPin = "1111" // Default pin
        }
        
        /// ----------------------- ClipBoard Settings -----------------------------------
        if let clipboardManagerMaxHistory = defaults.object(forKey: "clipboardManagerMaxHistory") as? Int {
            self.clipboardManagerMaxHistory = clipboardManagerMaxHistory
        }
        /// Load in the clipboardManagerPollingIntervalMS
        if let clipboardManagerPollingIntervalMS = defaults.object(forKey: "clipboardManagerPollingIntervalMS") as? Int {
            self.clipboardManagerPollingIntervalMS = clipboardManagerPollingIntervalMS
        }
        if let showDividerBetweenWidgets = defaults.object(forKey: "showDividerBetweenWidgets") as? Bool {
            self.showDividerBetweenWidgets = showDividerBetweenWidgets
        }
        
        /// ----------------------- Notch Scroll Settings -----------------------
        if let hoverTarget = defaults.object(forKey: "hoverTargetMode") as? String {
            self.hoverTargetMode = HoverTarget(rawValue: hoverTarget) ?? .album
        } else {
            self.hoverTargetMode = .album // Default to album
        }
        
        if let nowPlayingScrollSpeed = defaults.object(forKey: "nowPlayingScrollSpeed") as? Int {
            self.nowPlayingScrollSpeed = nowPlayingScrollSpeed
        } else {
            self.nowPlayingScrollSpeed = 40
        }
        if let enableNotchHUD = defaults.object(forKey: "enableNotchHUD") as? Bool {
            self.enableNotchHUD = enableNotchHUD
        } else {
            self.enableNotchHUD = false
        }
        
        if let notchMaxWidth = defaults.object(forKey: "notchMaxWidth") as? CGFloat {
            self.notchMaxWidth = notchMaxWidth
        } else {
            self.notchMaxWidth = 710
        }
        /// quickAccessWidgetDistanceFromLeft Loading Logic
        if let quickAccessWidgetDistanceFromLeft = defaults.object(forKey: "quickAccessWidgetDistanceFromLeft") as? CGFloat {
            self.quickAccessWidgetDistanceFromLeft = quickAccessWidgetDistanceFromLeft
        } else {
            self.quickAccessWidgetDistanceFromLeft = 18
        }
        
        if let oneFingerActionRawValue = defaults.string(forKey: "oneFingerAction"),
           let oneFingerAction = TouchAction(rawValue: oneFingerActionRawValue) {
            self.oneFingerAction = oneFingerAction
        } else {
            self.oneFingerAction = .none
        }
        
        if let twoFingerActionRawValue = defaults.string(forKey: "twoFingerAction"),
           let twoFingerAction = TouchAction(rawValue: twoFingerActionRawValue) {
            self.twoFingerAction = twoFingerAction
        } else {
            self.twoFingerAction = .none
        }
        
        if let notchScrollThreshold = defaults.object(forKey: "notchScrollThreshold") as? CGFloat {
            self.notchScrollThreshold = notchScrollThreshold
        } else {
            self.notchScrollThreshold = 50 // Default threshold
        }
        
        /// ----------------------- Music Player Settings -----------------------
        if let showMusicProvider = defaults.object(forKey: "showMusicProvider") as? Bool {
            self.showMusicProvider = showMusicProvider
        } else {
            self.showMusicProvider = true
        }
        
        if let musicControllerRawValue = defaults.string(forKey: "musicController"),
           let musicController = MusicController(rawValue: musicControllerRawValue) {
            self.musicController = musicController
        } else {
            self.musicController = .mediaRemote
        }
        
        if let overridenMusicProviderRawValue = defaults.string(forKey: "overridenMusicProvider"),
           let overridenMusicProvider = MusicProvider(rawValue: overridenMusicProviderRawValue) {
            self.overridenMusicProvider = overridenMusicProvider
        } else {
            self.overridenMusicProvider = .none
        }
        
        /// ----------------------- Messages Settings -----------------------
        if let enableMessagesNotifications = defaults.object(forKey: "enableMessagesNotifications") as? Bool {
            self.enableMessagesNotifications = enableMessagesNotifications
        } else {
            self.enableMessagesNotifications = false
        }
        
        if let messagesHandleLimit = defaults.object(forKey: "messagesHandleLimit") as? Int {
            self.messagesHandleLimit = messagesHandleLimit
        } else {
            self.messagesHandleLimit = 30
        }
        
        if let messagesMessageLimit = defaults.object(forKey: "messagesMessageLimit") as? Int {
            self.messagesMessageLimit = messagesMessageLimit
        } else {
            self.messagesMessageLimit = 20
        }
        
        /// ----------------------- Display Settings -----------------------
        if let screen = defaults.object(forKey: "selectedScreenID") as? CGDirectDisplayID {
            self.selectedScreen = NSScreen.screens.first(where: { $0.displayID == screen }) ?? NSScreen.main
        } else {
            self.selectedScreen = NSScreen.main
        }
        
        /// ----------------------- Animation Settings -----------------------
        if let openingAnimation = defaults.string(forKey: "openingAnimation") {
            self.openingAnimation = openingAnimation
        } else {
            self.openingAnimation = "iOS" // Default animation
        }
        
        if let name = defaults.string(forKey: "notchBackgroundAnimation"),
           let option = ShaderOption(rawValue: name) {
            self.notchBackgroundAnimation = option
        } else {
            self.notchBackgroundAnimation = .ambientGradient
        }
        
        if let enableMetalAnimation = defaults.object(forKey: "enableMetalAnimation") as? Bool {
            self.enableMetalAnimation = enableMetalAnimation
        } else {
            self.enableMetalAnimation = true // Default to true
        }
        
        if let constant120FPS = defaults.object(forKey: "constant120FPS") as? Bool {
            self.constant120FPS = constant120FPS
        } else {
            self.constant120FPS = false // Default to false
        }
        
        /// ----------------------- Utils Settings -----------------------
        if let enableUtilsOption = defaults.object(forKey: "enableUtilsOption") as? Bool {
            self.enableUtilsOption = enableUtilsOption
        } else {
            self.enableUtilsOption = true
        }
        
        if let enableClipboardListener = defaults.object(forKey: "enableClipboardListener") as? Bool {
            self.enableClipboardListener = enableClipboardListener
        } else {
            self.enableClipboardListener = true
        }
    }
    
    public func saveSettingsForDisplay(for screen: NSScreen) {
        self.selectedScreen = screen
        
        // Save the display ID of the selected screen
        if let displayID = screen.displayID {
            defaults.set(displayID, forKey: "selectedScreenID")
        }
    }
    
    // MARK: - Widget Update Logic
    
    /// Updates `selectedWidgets` and triggers a reload notification immediately
    /// This was a design choice to keep it in the settings page, this is becuase
    /// the settings is what manages and loads in the widgets at runtime and while
    /// the application is running
    func updateSelectedWidgets(with widgetName: String, isSelected: Bool) {
        
        debugLog("Updating selected widgets with: \(widgetName), isSelected: \(isSelected)")
        
        // Starting With Remove Logic so we can clear out any old widgets
        
        if !isSelected {
            if selectedWidgets.contains(widgetName) {
                selectedWidgets.removeAll { $0 == widgetName }
                UIManager.shared.expandedWidgetStore.removeWidget(named: widgetName)
                debugLog("Removed widget: \(widgetName)")
            } else {
                debugLog("Widget \(widgetName) not found in selected widgets")
                exit(0)
            }
        }
        
        // Add Logic
        if isSelected {
            if !selectedWidgets.contains(widgetName) {
                selectedWidgets.append(widgetName)
                if let widget = WidgetRegistry.shared.getWidget(named: widgetName) {
                    UIManager.shared.addWidgetToBigPanel(widget)
                    debugLog("Added widget: \(widgetName)")
                }
            }
        }
        
        saveSettings()
        debugLog("NEW Saved Settings: \(selectedWidgets)")
        
        // Refresh the UI only if the panel is open
        if UIManager.shared.panelState == .open {
            refreshUI()
        } else {
            debugLog("Panel is not open, not refreshing UI")
        }
    }
    
    // MARK: - UI Update Logic
    
    func refreshUI() {
        if UIManager.shared.panelState == .open {
            AudioManager.shared.startMediaTimer()
            UIManager.shared.smallPanel.contentView?.needsLayout = true
            UIManager.shared.smallPanel.contentView?.layoutSubtreeIfNeeded()
            
            DispatchQueue.main.async {
                UIManager.shared.smallPanel.contentView?.needsDisplay = true
                UIManager.shared.applyExpandedWidgetLayout()
            }
        }
    }
    
    func removeAndAddBackCurrentWidgets() {
        debugLog("🔄 Rebuilding widgets in the panel based on the updated order.")
        
        // Clear all currently displayed widgets
        UIManager.shared.expandedWidgetStore.clearWidgets()
        
        // Iterate over the updated selectedWidgets list
        for widgetName in selectedWidgets {
            if let widget = WidgetRegistry.shared.getWidget(named: widgetName) {
                UIManager.shared.addWidgetToBigPanel(widget)
            } else {
                debugLog("⚠️ Widget \(widgetName) not found in WidgetRegistry.")
            }
        }
        
        // Finally, refresh the UI
        refreshUI()
    }
}
