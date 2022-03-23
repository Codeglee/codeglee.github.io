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

#### Here are the key scenarios we'll cover in the series:

1. Our app has a lengthy first-run only onboarding flow that we want to skip for all but our onboarding UI tests
2. We want to isolate our UI tests to use a different API endpoint, fetching 'static' data from a staging environment for example (see the risks[^1] here)

The core parts of this approach are an `AppLauncher` as an entry point to allow us to read and configure our environment before the app is run.

An `AutomationContext` acts as a live-defaulted environment we can use for configuring and tracking automation arguments.

A set of `Automation Identifiers` shared between `App` and `UI tests`.

A `Screen` or `Robot` to make it easy to encapsulate assertions and interactions.

In this first post, we'll cover the _setup_ required to address our first scenario.

#### What to know before we start

UI tests run in their own process separate from your app and remotely interface with it. You'll no doubt have seen this when you see `"MyAppUITests-Runner"` installed in the simulator before your app is installed and run.
What does this mean? it means your app is mostly[^2] run like a black box where the only points of interface are on the initialisation of your app via launch arguments and through the accessibility engine that underpins XCTest.

_Where does that leave us?_ with app initialisation via launch arguments as our primary means of configuring the app.

### Let's Skip Onboarding
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
                ContentView()
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

    init(settingStore: SettingStorage = SettingStore.shared) {
        self.settingStore = settingStore
        showOnboarding = settingStore.showOnboarding
    }

    func markOnboardingSeen() {
        settingStore.showOnboarding = false
        showOnboarding = false
    }
}

```
An example `SettingsStore` might just be a wrapper around `UserDefaults`. For testability you should further abstract `UserDefaults` to allow it to be injectable for testability and avoid resource isolation issues[^3]:

```swift
final class SettingStore: SettingStorage {
	static let shared = SettingsStore()
	private init() {}
	
    var showOnboarding: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hasOnboardingBeenShown")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasOnboardingBeenShown")
        }
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

    private init(settingStore: SettingStorage = SettingStore.shared) {
        self.settingStore = settingStore

        showOnboarding = settingStore.showOnboarding
    }
}
```

**_NOTE:_** That it uses the _same settings store_, if you use the `UserDefaults` wrapper then _beware_[^3].

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

**_NOTE:_** Over in MyApp we remove @main as the entry point
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
3. Our use of `UserDefaults.standard` means that we haven't isolated our settings across our tests or across different builds of the same app i.e if you had a Development vs Internal vs AppStore build they'd all share the same `UserDefaults` at the moment. A better way of managing this would be to use an in-memory store for tests and a persisted one for production.
4. **_Beware_** the impact of using persisted shared state and resources as they can lead to *test pollution* - a significant source of unexpected test behaviour. What is test pollution? Any resource that's ultimately persisted to disk / synchronised in the cloud is shared across tests. Consider if your tests run in parallel, multiple simulators are instantiated running different tests at the same time which use the same files on disk. If `testMarkOnboardingAsSeen` updates `UserDefaults.standard` with `seen = true` and `testMarkOnboardingAsUnseen` runs at the same time, they could easily read and write over each other and your expectations and assertions will fail inconsistently enough to send you on a wild goose chase and write off UI tests as 'flakey'. Not flakey in this way, just incorrectly architected. We'll address this in a future post.
5. We rely on a mutation of `AutomationContext` to do work, hiding this in a property setter is a bit unexpected and easy to miss. A nicer way would be to keep sets `private` and expose a method to allow this instead.

### What's next?

* Writing our first UI tests to verify our onboarding approach works.
* Introducing enum-based constants for strings and automation identifiers
* Introducing the Robot pattern

See the [next post here](https://blog.codeglee.com/2022/03/23/an-automation-approach-pt2.html).

I hope this post was informative, feel free to send me your thoughts via Twitter.


**Footnotes:**

[^1]: _Relying on live networking makes our UI tests more realistic but also more prone to failure in case of outages, unexpected delays, changes in contract at a separate cadence than the app tests etc. Be aware it also puts additional resource pressure on your backend. If this is an issue, moving to an offline-mock based networking approach can be a good choice but with its own tradeoffs._
[^2]: _I say mostly because during development you get some ability to inspect and debug your app using things like the XCUI test recorder._
[^3]: _Points 3 and 4 in "What could we do better" are critical to avoiding flakey inconsistent tests._

