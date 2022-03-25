---
layout: post
title: UI testing, a simple approach - Part 4
excerpt_separator:  <!--more-->
tags: testing automation
---

### UI test automation continued... where did we get to?
In the [previous post](https://blog.codeglee.com/2022/03/23/an-automation-approach-pt3.html), we fleshed out our onboarding flow and added UI tests for covering onboarding and the transition to our main content view.
In so doing, we hit the issue of _test pollution_ as a result of using shared `UserDefaults` across tests.

In this post, we'll address this issue by:

* Introducing a `Dependencies` environment object that we'll use app-wide for our concrete dependencies.
* Refactoring our `SettingStore` to use a protocol for `UserDefaults`
* Introducing an in-memory `UserDefaults` replacement that we can configure for our tests

#### Let's review our `SettingStore` implementation
```swift
final class SettingStore: SettingStorage {
    static let shared = SettingStore()
    private init() {}

    var showOnboarding: Bool {
        get {
            !UserDefaults.standard.bool(forKey: "hasOnboardingBeenShown")
        }
        set {
            UserDefaults.standard.set(!newValue, forKey: "hasOnboardingBeenShown")
        }
    }
}
```
What's wrong here? well, a number of things...

1. `UserDefaults.standard` is a shared resource that can be mutated by any test in our test suite, at any time (if tests are run in parallel), _this is our core issue_
2. We're tightly coupling this class with the concrete class `UserDefaults`
3. We can't safely unit test `SettingStore` given it's reliance on a concretion, not an abstraction
4. We're using string constants which are less maintainable and more error prone (typos are easy to make and hard to spot!)

Let's address all of these issues. As we're currently only interacting with `UserDefaults` via a `boolean` let's just handle that scenario for now. We'll start by introducing an enum for our settings keys[^1].

```swift
enum SettingStoreKey: String {
    case hasOnboardingBeenShown
}
```
Then we'll introduce an abstraction around our `UserDefaults` scenario.

```swift
protocol UserDefaultInterfacing {
    func set(_ value: Bool, forKey key: SettingStoreKey)
    func bool(forKey key: SettingStoreKey) -> Bool
}
```
Before we conform `UserDefaults` to it, note we're using our `SettingStoreKey` here, this will make the call site nicer to work with.

```swift
extension UserDefaults: UserDefaultInterfacing {
    func set(_ value: Bool, forKey key: SettingStoreKey) {
        set(value, forKey: key.rawValue)
    }
    func bool(forKey key: SettingStoreKey) -> Bool {
        bool(forKey: key.rawValue)
    }
}
```
Finally, we update our `SettingStore` with the injected abstraction with `UserDefaults` as our default for our app.
**_NOTE:_** We remove the private initialiser and our singleton as we want to ensure we're using the correct instance everywhere.

```swift
final class SettingStore: SettingStorage {
    let userDefaults: UserDefaultInterfacing

    init(userDefaults: UserDefaultInterfacing = UserDefaults.standard) {
        self.userDefaults = userDefaults
    }

    var showOnboarding: Bool {
        get {
            !userDefaults.bool(forKey: .hasOnboardingBeenShown)
        }
        set {
            userDefaults.set(!newValue, forKey: .hasOnboardingBeenShown)
        }
    }
}
```
_Great!_ now we've got a unit-testable `SettingStore` and a reusable abstraction over `UserDefaults`.

Let's move on to our UI test affordance, we'll create a non-persisted in-memory cached dictionary equivalent of `UserDefaults`.

```swift 
final class InMemoryUserDefaults: UserDefaultInterfacing {
    private var cache: [String: Bool] = [:]

    func set(_ value: Bool, forKey key: SettingStoreKey) {
        cache[key.rawValue] = value
    }

    func bool(forKey key: SettingStoreKey) -> Bool {
        cache[key.rawValue] ?? false
    }
}
```
**_NOTE:_** This is a naive implementation, we're not handling additional functionality present in `UserDefaults` such as the ability to `register defaults`. If your app needs this, bear that in mind.

_Cool!_ let's move on to our UI test interface through `LaunchArgumentConfigurator`.

```swift
enum LaunchArgumentConfigurator {

    static func configure(
        _ dependencies: Dependencies,
        with launchArguments: [String]
    ) {
        if launchArguments.contains(LaunchArgumentKey.useInMemoryUserDefaults.rawValue) {
            dependencies.replace(with: SettingStore(userDefaults: InMemoryUserDefaults()))
        }

        if launchArguments.contains(LaunchArgumentKey.skipOnboarding.rawValue) {
            dependencies.settingStore.showOnboarding = false
        }
    }
}

enum LaunchArgumentKey {
    // NOTE: We add a key to use for UI tests
    case useInMemoryUserDefaults = "-useInMemoryUserDefaults"
    ...
}

```

Wait, where did `AutomationContext` go? and what is `Dependencies`?
Let me show you what `Dependencies` does and we'll circle back.

```swift
final class Dependencies {
    static let shared = Dependencies()

    private(set) var settingStore: SettingStorage

    private init(settingStore: SettingStorage = SettingStore(userDefaults: UserDefaults.standard)) {
        self.settingStore = settingStore
    }

    func replace(with settingStore: SettingStorage) {
        self.settingStore = settingStore
    }
}
```
So `Dependencies` is a simple dependency container we can use to inject either the app `UserDefaults` implementation or our in-memory test alternative.

**_NOTE:_** When it comes to implementing *Networking* in our app, we could use this same dependency container approach in order to switch between an app-default or a static, offline alternative.

If you build at this point, you'd notice there's an error here:
`dependencies.settingStore.showOnboarding = false`

With the error:
 `Cannot assign to property: 'settingStore' setter is inaccessible`.

This is because our `SettingStorage protocol` isn't type-constrained so it could be conformed to by an `immutable struct` or a `class`. If it were a `struct`, the compiler can't tell if it would be mutable hence the error. We need to be more specific. Here I'll just say `SettingStorage` has to be implemented by a `class` by constraining to `AnyObject` this limits `SettingStorage` to `classes` exclusively which, as reference types, are freely mutable:

```swift
protocol SettingStorage: AnyObject {
```

So, where did `AutomationContext` go? Well, for now, it's performing the same role as `Dependencies` so we've removed it, however as we build other UI-test specific flows we may bring it back.

Let's update any references to `SettingStore.shared` with `Dependencies.shared.settingStore`.

```swift
final class AppViewModel: ObservableObject {
    init(settingStore: SettingStorage = Dependencies.shared.settingStore)
    ...
}
```

The very last task is to update our UI tests so they trigger use of our safe, testable in-memory alternative.

In `BaseUITestCase` we add:

```swift
    func useTestSafeUserDefaults() {
        launchArguments.insert(LaunchArgumentKey.useInMemoryUserDefaults.rawValue)
    }
```
We could add this call in both our `OnboardingView` and `ContentView` tests, however as we want all our UI tests to be safe and predictable by default, we'll add it to our `BaseUITestCase`'s `setUp`.

```swift
    override func setUp() {
        ...
        launchArguments = Set<String>(app.launchArguments)
        useTestableUserDefaults()
    }
```

Let's re-run our tests, in parallel and randomly and run them 100 times to be sure we fixed the _test pollution_ issue.
Here's how you set up parallel test running, go to `Scheme > Tests > Info > Options`:

![alt text](/assets/images/tests-run-in-parallel.png "Scheme > Tests > Info > Options showing the parallel and random run options")

Here's how you set up repeated test runs:

_Right-click your UI test project and pick run repeatedly_
![alt text](/assets/images/tests-run-repeatedly.png "Showing the repeated test run options")

_Decide on your scenario and conditions_
![alt text](/assets/images/tests-run-repeatedly-dialog.png "Showing the repeated test run option dialog")

### The result?
All our tests pass, in any order, regardless of being run serially or in parallel.

As [Paul Hudson points out](https://www.hackingwithswift.com/articles/153/how-to-test-ios-networking-code-the-easy-way) tests should be **FIRST:**
Fast, Isolated, Repeatable, Self-Verifying and Timely.

**Fast:** UI tests are much slower than unit tests as they have a lot more setup required before they can run and a higher resource overhead when running but swapping to an in-memory replacement rather than a file-IO backed `UserDefaults` actually does speed our test up.

**Isolated:** We've isolated one of the dependencies, we've eliminated a reason for the tests to fail

**Repeatable:** 
That's what we've improved with the changes in this post, by isolating `UserDefaults` our tests can now be run in parallel, in any order with the same repeatable results. No test flakeyness in sight.

**Self-Verifing:**
Our tests need to be valuable, it's easy to increase code coverage with UI tests just by interacting with a screen but if you're not verifing state and behaviour with assertions that coverage is a lie, those tests are meaningless. 
In our case we're testing both UI state as well as inter-screen navigation behaviour.

**Timely:**
Here's it's referring to TDD, "you should know what you're trying to build before you build" it.
For the format and focus of this series I didn't follow TDD but it's a great technique, if you haven't tried it before, give it a go!

#### So what did we cover?

1. We introduced a Dependency container that we'll use app-wide for our replaceable concrete dependencies.
2. We refactored our `SettingStore` to use an injectable protocol for `UserDefaults`, making our `SettingsStore` unit testable.
3. We introduced an in-memory `UserDefaults` replacement that we configured through our UI tests
4. We added predictability to our common test case, ran our UI tests and proved that we've fixed our core issues.

### What do we do next?
* We'll take a look at approaches for handling networking.
* We'll also look at how you can wait for state changes that take time (for animations to finish or networking to complete, for example).


I hope this post was informative, feel free to send me your thoughts via Twitter.

**Footnotes**

[^1]: _Consider the rule of three before introducing a enum for constants like this_