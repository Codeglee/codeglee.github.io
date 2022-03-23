//: [Previous](@previous)

/*
import SwiftUI
import Foundation

// NOTE: You can swap actor for a final class with a standard singleton
final class AutomationContext {
    static let shared = AutomationContext()

    private let settingStore: SettingStorage

    var showOnboarding: Bool {
        didSet {
            settingStore.showOnboarding
        }
    }

    private init(settingStore: SettingStorage = SettingStore()) {
        self.settingStore = settingStore

        showOnboarding = settingStore.showOnboarding
    }
}

protocol SettingStorage {
    var showOnboarding: Bool { get set }
}

struct SettingStore: SettingStorage {
    var showOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasOnboardingBeenShown")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasOnboardingBeenShown")
        }
    }
}

final class AppViewModel: ObservableObject {
    @Published private(set) var showOnboarding: Bool
    private var settingStore: SettingStorage

    init(settingStore: SettingStorage = SettingStore()) {
        self.settingStore = settingStore
        showOnboarding = settingStore.showOnboarding
    }

    func markOnboardingSeen() {
        settingStore.showOnboarding = false
        showOnboarding = false
    }
}

struct MyApp: App {

    @StateObject var app = AppViewModel()

    var body: some Scene {
        WindowGroup {
            if app.showOnboarding {
                OnboardingView(
                    complete: {
                        app.markOnboardingSeen()
                    }
                )
            } else {
                MainAppFlowView()
            }
        }
    }
}

struct OnboardingView: View {
    let complete: () -> Void

    var body: some View {
        VStack {
            Text("Imagine a lengthy onboarding flow here")

            Button(
                action: complete,
                label: {
                    Text("Okay")
                }
            )
        }
    }
}

struct MainAppFlowView: View {
    var body: some View {
        Text("Our main app flow")
    }
}


//@main
enum AppLauncher {

    static func main() throws {

        LaunchArgumentConfigurator.configure(
            AutomationContext.shared,
            with: CommandLine.arguments
        )

        MyApp.main()
    }
}

enum LaunchArgumentConfigurator {

    static func configure(
        _ context: AutomationContext,
        with launchArguments: [String]
    ) {
        if launchArguments.contains("-skipOnboarding") {
            context.showOnboarding = false
        }
    }
}

import XCTest

func testSkipsOnboarding() {
    let app = XCUIApplication()
    app.launchArguments.append("-skipOnboarding")
    app.launch()

    XCTFail("We're not actually verifying we've skipped onboarding yet")
}
*/

//: [Next](@next)

