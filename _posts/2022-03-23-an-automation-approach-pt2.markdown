---
layout: post
title: UI testing, a simple approach - Part 2
excerpt_separator:  <!--more-->
tags: testing automation
---

### UI test automation continued... where did we get to?
In the [previous post](https://blog.codeglee.com/2022/03/23/an-automation-approach-pt1.html), we covered the setup required to externally initialise and configure our app such that the onboarding app flow could be skipped for UI test purposes.

In this post we'll:

* Introduce an approach for shared automation identifiers
* Improve our app initialisation via a shared typed enum
* Swap our string constants for enum-based ones
* Encapsulate our screens behaviours and assertions using the Robot pattern
* Pass our failing UI test verifying that our onboarding approach works

#### App-side LaunchArguments
We'll start by addressing the launch arguments[^1].
Let's start on the app side by encapsulating the string constant into a `LaunchArgumentKey enum`.

```swift
enum LaunchArgumentKey: String {
    case skipOnboarding = "-skipOnboarding"
}
```
We'll make this `enum` _shared_ across both the App and UI Test targets.

On the app side we'll update our `LaunchArgumentConfigurator` to use `LaunchArgumentKey`.

```swift
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
```

**_NOTE:_** If we had more launch arguments, particularly ones with associated values we could do some more interesting and intelligent configuration but for now this is enough to increase maintainability.

Next, on the UI test side, we'll introduce a helper class to better manage launch arguments. This gives us a reusable abstraction over launch arguments.

```swift
class BaseUITestCase: XCTestCase {
    var app: XCUIApplication!
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
```
For context around the use of `XCUIApplication!` see here[^2].

#### Revisiting our UI test
Here's our test case updated to use `skipOnboarding` and `launch` for the Main App Flow.

```swift
final class ContentViewTests: BaseUITestCase {
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
    func testAfterSkippingOnboardingContentViewIsVisible() {
        XCTFail("We can't assert anything yet")
    }
}
```
Great, we've made it simple to skip onboarding as part of `setUp` but we have nothing to assert we're on the right view yet, let's address that now.

#### An approach for accessibility identifiers
For us to verify we're on a particular screen we need something to look for. In the app we add a shared enum modelled as screens with identifiable parts. Pick a naming convention that works for you and ensures uniqueness.

**_NOTE:_** We share the `Automation` enum across both app and test targets.
```swift
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
```

A Swift View extension helps us enforce type safety
```swift
extension View {
    func automationId(_ identifying: AutomationIdentifying) -> some View {
        accessibilityIdentifier(identifying.id)
    }
}
```
Now, in our `OnboardingView` we update our button with an identifier:

```swift
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
```
In our `ContentView` we add our identifier:
```swift
Text("Our main app flow")
    .automationId(
        Automation
            .ContentScreen
            .title
    )
```

#### Let's update our UI test
```swift

    func testAfterSkippingOnboardingContentViewIsVisible() {
        let contentViewTitleElement = app.staticTexts[
            Automation.ContentScreen.title.rawValue
        ]
        XCTAssert(contentViewTitleElement.exists)
    }
```
And our test passes, woot! ... but imagine the other UI tests to follow that rely on us being on this screen, duplicating this same logic and having to know so much of the internals of the implementation.

#### ...it's Robot time
Here's the approach we'll take:

* Model a view or independent portions as a component/screen
* Use a fluent interface to chain behaviours and assertions
* For interactions use the imperative tense i.e commands such as `select`, `next`, `complete`
* For assertions use the present tense `is`, `has`, `shows` etc

First, let's introduce an `XCUIElementQuery` helper so we can query for `AutomationIdentifiers` directly.

```swift
extension XCUIElementQuery {
    subscript(_ identifying: AutomationIdentifying) -> XCUIElement {
        self[identifying.id]
    }
} 
```
Then we model our view as a screen hiding the implementation and exposing the assertions and interactions into a 'Robot':
```swift
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

```

Our `ContentScreen` Robot takes the `app` instance to use and while this might feel like boilerplate, after all, when would we need another app? Well, in several important scenarios such as:
* When we need to access a platform screen such as accessing `Safari` with `XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")`
* Or `App settings` with `XCUIApplication(bundleIdentifier: "com.apple.Preferences")`

We've covered a lot of ground already but let's finally refactor our test.

```swift
func testAfterSkippingOnboardingContentViewIsVisible() {
    ContentScreen(app)
        .isOnScreen()
}

```
Looks good, it's easy to read and understand but it's a little too simple. Let's tackle a more complex scenario next time.


#### What did we cover?
1. A simple mechanism for starting the application in a pre-configured state through `AppLauncher`, `LaunchArguments`, `LaunchArgumentConfigurator` and `AutomationContext` configured from UI tests.
2. `BaseUITestCase` to encapsulate the understanding of launch argument configuration.
3. A strongly-typed approach for accessibility identifiers via the `Automation` enums
4. Encapsulating assertions and behaviours in a 'Robot' allows the call site to be easily readable and understandable.
5. Passing our failing test and refactoring to use Robots.


### What's next?

* We'll flesh out our `Onboarding` flow views
* Add some more advanced behaviours to test
* Add UI tests for our introduced `Onboarding` flow.
* Swap our dangerous use of `UserDefaults` for an `AutomationContext`-led but in-memory alternative

I hope this post was informative, feel free to send me your thoughts via Twitter.


**Footnotes:**

[^1]: _In a real app you'll want to do this when you have more than one use case (I use the rule of three - on the third repetition, abstract and improve)_
[^2]: _We're implicitly unwrapping here to allow for setup and teardown to clean up appropriately._

