import SwiftUI

//
//  UITestSnippests.swift
//
//
//  Created by Tristan Warner-Smith on 23/03/2022.
//

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
                ContentView()
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
.automationId(
    Automation
        .OnboardingScreen
        .complete
)
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Our main app flow")
            .automationId(
                Automation
                    .ContentScreen
                    .title
            )
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

enum LaunchArgumentKey: String, Hashable {
    case skipOnboarding = "-skipOnboarding"
}

enum LaunchArgumentConfigurator {

    static func configure(
        _ context: AutomationContext,
        with launchArguments: [String]
    ) {
        if launchArguments.contains(LaunchArgumentKey.skipOnboarding.rawValue) {
            context.showOnboarding = false
        }
    }
}

import XCTest

class BaseUITestCase: XCTestCase {
    var app: XCUIApplication!//[^2]
    private var launchArguments = Set<String>()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()

        app.launchArguments.forEach { argument in
            launchArguments.insert(argument)
        }
    }

    override func tearDown() {
        app = nil

        super.tearDown()
    }

    func skipOnboarding() {
        launchArguments.insert(LaunchArgumentKey.skipOnboarding.rawValue)
    }

    func launch() {
        let arguments = launchArguments.reduce(into: [], { result, argument in
            result.append(argument)
        })
        app.launchArguments = arguments
        app.launch()
    }
}

final actor LaunchArgumentBuilder {

    private var arguments: Set<String>

    init(initialArguments: [String]) {
        var dedupedArguments = Set<String>()
        initialArguments.forEach { dedupedArguments.insert($0) }

        self.arguments = dedupedArguments
    }

    @discardableResult
    func skipOnboarding() -> LaunchArgumentBuilder {
        arguments.insert(LaunchArgumentKey.skipOnboarding.rawValue)

        return self
    }

    func build() -> [String] {
        arguments.reduce(into: [], { result, keyValue in
            result.append(keyValue)
        })
    }
}

final class MainAppFlowViewTests: BaseUITestCase {
    override func setUp() {
        super.setUp()

        skipOnboarding()
        launch()
    }

    /*
     GIVEN we've previously seen the onboarding flow
     WHEN the app starts
     THEN the main app flow is shown
     */
    /*
    func testAfterSkippingOnboardingContentViewIsVisible() {
        let contentViewTitleElement = app.staticTexts[
            Automation.ContentScreen.title.rawValue
        ]
        XCTAssert(contentViewTitleElement.exists)
    }*/
    func testAfterSkippingOnboardingContentViewIsVisible() {
        ContentScreen(app)
            .isOnScreen()
    }
}


enum Automation {
    enum OnboardingScreen: String, AutomationIdentifying {
        case complete = "automation.onboarding.complete"
    }

    enum ContentScreen: String, AutomationIdentifying {
        case title = "automation.content.title"
    }
}

protocol AutomationIdentifying {
    var id: String { get }
}
extension AutomationIdentifying where Self: RawRepresentable, Self.RawValue == String {
    var id: String { rawValue }
}

extension View {
    func automationId(_ identifying: AutomationIdentifying) -> some View {
        accessibilityIdentifier(identifying.id)
    }
}

extension XCUIElementQuery {
    subscript(_ identifying: AutomationIdentifying) -> XCUIElement {
        self[identifying.id]
    }
}

struct ContentScreen {
    private let app: XCUIApplication
    init(_ app: XCUIApplication) {
        self.app = app
    }

    private var title: XCUIElement {
        app.staticTexts[Automation.ContentScreen.title]
    }

    @discardableResult
    func isOnScreen() -> Self {
        XCTAssert(title.exists)
        return self
    }
}


/*


func testSkipsOnboarding() {
    let app = XCUIApplication()
    app.launchArguments.append("-skipOnboarding")
    app.launch()

    XCTFail("We're not actually verifying we've skipped onboarding yet")
}
*/
