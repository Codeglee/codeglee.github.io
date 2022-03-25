---
layout: post
title: UI testing, a simple approach - Part 3
excerpt_separator:  <!--more-->
tags: testing automation
---

### UI test automation continued... where did we get to?
In the [previous post](https://blog.codeglee.com/2022/03/23/an-automation-approach-pt2.html), we covered encapsulating automation and launch argument constants, encapsulated launch argument configuration for our UI tests and wrapped our interactions and assertions in a Robot screen to make our tests easy to read and understand.

In this post we'll:

* Flesh out our `Onboarding` flow views with some more complexity
* We'll write UI tests for `Onboarding` to address the changes in design
* Discover the fundamental flaw in our `SettingStore`

#### Let's make onboarding a bit more complex...

Let's introduce a 3 stage onboarding process. I'll model that with an `OnboardingStage` enum.
For the sake of brevity, I'll extend this enum to return content-specific to the stage.

```swift
enum OnboardingStage: Int, CaseIterable {
    case welcome
    case catalog
    case confirm
    
    var icon: Image { ... }
    var title: String { ... } 
    var body: String { ... }
    var buttonTitle: String { ... }
    var buttonColour: Color { ... }
    var buttonAutomationId: AutomationIdentifying { 
        if self == .confirm {
            return Automation.OnboardingScreen.complete
        } else {
            return Automation.OnboardingScreen.next
        }
    }
}
```
Then a trimmed version of our new onboarding view.

```swift
struct OnboardingView: View {
    @State var stage: OnboardingStage = .welcome
    
    let complete: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.clear

                VStack {

                    Self.onboardingPage(
                        for: stage,
                        in: geometry
                    )

                    Button(
                        action: {
                            if stage.isLast {
                                complete()
                            } else {
                                withAnimation {
                                    stage.next()
                                }
                            }
                        },
                        label: {
                            Text(stage.buttonTitle)
                                .font(.system(.title3, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: Style.cornerRadius,
                                        style: .continuous
                                    ).fill(stage.buttonColour)
                                )
                                .foregroundColor(.primary)
                        })
                    .buttonStyle(.plain)
                    .automationId(stage.automationId)
                }
                .padding(.horizontal)
            }
        }
    }    
```
I've pulled the onboarding page view out for length but fundamentally it's just this:

```swift
Image

Text(stage.title)
.automationId(Automation.OnboardingScreen.title)

Text(stage.body)
```
Tapping the `Next` button goes through the stages from `welcome` to `catalogue` to `confirmation`.

Tapping the `Complete` button calls our `complete: () -> Void` callback.
_**NOTE:**_ Ideally you'd abstract this all behind a testable `ViewModel` but there's a lot to cover here so I won't.

Here's our three screens:

![alt text](/assets/images/onboarding-stages.png "Shows three screens with image, title, body text and a button showing next or complete")

I'm sure you'll forgive the design, it just adds some testable differences. In this case the title and button have `Automation Ids`.

```swift
enum OnboardingScreen: String, AutomationIdentifying {
    case title = "automation.onboarding.stage.title"
    case complete = "automation.onboarding.complete"
    case next = "automation.onboarding.next"
}
```

#### Let's write some UI tests
```swift
final class OnboardingViewTests: BaseUITestCase {
    override func setUp() {
        super.setUp()

        launch()
    }

    /*
        GIVEN I start the app from scratch
        WHEN the onboarding screen shows
        THEN I see the welcome stage
     */
    func testOnboarding_showsWelcomeStageByDefault() {
        OnboardingScreen(app)
            .isOnScreen()
            .showsTitle("Welcome")
            .isShowingNextButton()
    }
}
```
```swift
struct OnboardingScreen {

    private let app: XCUIApplication
    init(_ app: XCUIApplication) {
        self.app = app
    }

    private var title: XCUIElement { app.staticTexts[Automation.OnboardingScreen.title] }
    private var nextButton: XCUIElement { app.buttons[Automation.OnboardingScreen.next] }
    private var completeButton: XCUIElement { app.buttons[Automation.OnboardingScreen.complete] }

    @discardableResult
    func isOnScreen() -> Self {
        XCTAssert(title.exists)
        return self
    }

    @discardableResult
    func showsTitle(_ text: String) -> Self {
        XCTAssertEqual(text, title.label)
        return self
    }

    @discardableResult
    func isShowingNextButton() -> Self {
        XCTAssert(nextButton.exists)
        return self
    }

    @discardableResult
    func isShowingCompleteButton() -> Self {
        XCTAssert(completeButton.exists)
        return self
    }
}
```
We run our tests and... great! They pass. Let's add tests for the next two stages.

We'll add a `next` and `complete` interaction to our `OnboardingScreen`

```swift
@discardableResult
func next() -> Self {
    XCTAssert(nextButton.exists)
    nextButton.tap()
    return self
}

@discardableResult
func complete() -> Self {
    XCTAssert(completeButton.exists)
    completeButton.tap()
    return self
}

```

Then add our remaining UI tests.

```swift
/*
    GIVEN I am on the welcome onboarding stage
    WHEN I press the next button
    THEN I am shown the catalogue stage
 */
func testOnboarding_isOnWelcomeStage_next_showsCatalogueStage() {
    OnboardingScreen(app)
        .isOnScreen()
        .showsTitle("Welcome")
        .next()
        .showsTitle("Shiny, shiny things")
        .isShowingNextButton()
}

/*
    GIVEN I am on the catalogue onboarding stage
    WHEN I press the next button
    THEN I am shown the confirm stage
 */
func testOnboarding_isOnCatalogueStage_next_showsConfirmStage() {
    OnboardingScreen(app)
        .isOnScreen()
        .next()
        .next()
        .showsTitle("Ready to start?")
        .isShowingCompleteButton()
}

/*
    GIVEN I am on the confirm onboarding stage
    WHEN I press the complete button
    THEN I am shown the content screen
 */
func testOnboarding_isOnConfirmStage_next_showsContentScreen() {
    OnboardingScreen(app)
        .isOnScreen()
        .next()
        .next()
        .complete()

    ContentScreen(app)
        .isOnScreen()
}
```
### What happens if I run this?
Well, it depends if you've got randomise execution order or parallel running configured for your tests.
If they're run randomly and the **last** test is run **first** then all the other tests fail.

Why is this? I mentioned this in a previous post, we're suffering from _test pollution_.

You see, the issue is that *if* you used the `UserDefaults`-backed `SettingStore` the *last* test ends up setting `showOnboarding` to `false` and as a result, when they access `UserDefaults` they're told not to show onboarding, instead we jump to the `content screen` so our tests fail.

#### This is a big problem, right?
It absolutely is, and it applies to all persisted shared resources not just `UserDefaults`.

#### So what did we cover?
1. We added a staged onboarding process
2. We added UI tests for our onboarding screens, we tested both the _titles_ and _buttons_ were as expected both by default and after interaction
3. We realised we have a core testing problem to solve

### What do we do next?
We roll our sleeves up and take a look at part 4 of this series where we address _test pollution_ head-on.

I hope this post was informative, feel free to send me your thoughts via Twitter.
