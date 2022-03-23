---
layout: post
title: UI testing, a simple approach - Part 1
excerpt_separator:  <!--more-->
tags: testing automation
---


### Who is this series for?

Anyone looking for a full end-to-end approach to UI testing in a pragmatic and predictable way

What this series isn't:

* The _only_ way to handle UI test automation
* Without tradeoffs that I'll attempt to point out
* Covering when or why UI tests are a great choice
* Covering mocking network requests.
* Covering the alterations required for structured concurrency and actors

Here's the **TL;DR**; of what I'll cover in the series:

* CommandLine argument-based app initialisation
* An approach for app configuration (using SwiftUI as an example)
* How to isolate our UI test state across builds
* Some helpers for UI test scenario configuration
* A Robots-like approach for UI tests using a fluent interface
* The end-to-end illustrated

_If that sounds interesting, read on._

#### Here are the scenarios we'll cover in the series:

1. Our app has a lengthy first-run only onboarding flow that we want to skip for all but our onboarding UI tests
2. We want to isolate our UI tests to use _static_ data in a staging environment (see the risks[^1] here)
3. We want to enable some additional scenario configuration

The core parts of this approach are an `AppLauncher` to allow us to read and configure our environment before the app is run.

An `AutomationContext` acts as a live-defaulted environment we can use for configuring and tracking automation arguments.

A `LaunchArgumentBuilder` to make it easy to configure our scenarios

A `UITestScreen` to make it easy to encapsulate assertions and behaviours.

In this first post, we'll cover the _setup_ required to address our first scenario.

### Skip Onboarding
Let's imagine our simplified app looks something like this, when the app starts we initialise our state around onboarding.

``` swift

@main
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

protocol SettingStorage {
    var showOnboarding: Bool { get set }
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

```

Introducing an `AutomationContext` is the next step.
``` swift
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
```

*NOTE:* That it uses the _same settings store_ and is _initialised in the same way_.

Next, we need a way to pre-configure the automation context.
So let's create an `AppLauncher` which will grab the `CommandLine` arguments we'll use to configure the application run and a `LaunchArgumentConfigurator` to parse our arguments and update our `AutomationContext` and app state.

``` swift

@main
enum AppLauncher {

    static func main() throws {

        LaunchArgumentConfigurator.configure(AutomationContext.shared, with: CommandLine.arguments)

        MyApp.main()
    }
}

// NOTE: Over in MyApp we remove @main as the entry point
struct MyApp: App {...}

enum LaunchArgumentConfigurator {

    static func configure(_ context: LaunchAutomationContext, with launchArguments: [String]) {
    	if launchArguments.contains("-skipOnboarding") {
            context.showOnboarding = false
        }
    }
}
```

So what have we done? We've removed `@main` from `MyApp` and introduced a new entry point.
We've expanded the role of `AutomationContext` to enable configuring our `SettingsStore` before `MyApp` is run and then finally we've started our app.
What are the downsides of this approach? Well, we've likely introduced some additional app start time as the settings store is initialised, read and written to.

What have we gained here? The ability to unit test our `LaunchArgumentConfigurator, AutomationContext, AppViewModel and SettingStore` via mutations to an injectable instance of `SettingsStorable` before we even get to UI tests which can now be configured to skip onboarding via a launch argument.

#### How do we skip onboarding?
We just need to run the app with the launch argument `"-skipOnboarding"`:
- You can do that in your scheme like so. ![alt text](/assets/images/ui-automation-scheme-arguments.png "Scheme > Run > Arguments > Arguments Passed On Launch showing our skip onboarding flag")
- Or via the launch argument of your app in a UI test
``` swift
func testSkipsOnboarding() {
    let app = XCUIApplication()
    app.launchArguments.append("-skipOnboarding")
    app.launch()

    XCTFail("TODO: Verifying onboarding skipped")
}
```

#### What could we do better?

1. We've left ourselves with a failing test, we should fix that in the next post
2. We should abstract strings so they are maintainable and less prone to error

### What's next?

* Writing our first UI tests to verify our onboarding approach works.
* Introducing enum-based constants for strings and automation identifiers
* Introducing the Robot pattern

I hope this post was informative, feel free to send me your thoughts via Twitter.


**Footnotes:**

[^1]: _Relying on live networking makes our UI tests more realistic but also more prone to failure in case of outages, changes in contract at a separate cadence than the app tests etc. Be aware it also puts additional resource pressure on your backend. If this is an issue, moving to an offline-mock based networking approach can be a good choice but with its own tradeoffs._

