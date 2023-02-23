---
layout: post
title: Increasing Unit Testing
excerpt_separator:  <!--more-->
tags: testing
---

## Progressive refactoring towards testability

*Let's imagine for a moment...* we've just finished writing some core functionality for our app.

We didn't follow **_TDD_**[^1] and we're not entirely sure what the **_SOLID_** principles are or why they're valuable and important.

Luckily for us the work has a spec with acceptance criteria. You may or may not be familiar with BDD[^2] but it's commonly used when describing features and acceptance criteria. They cover app behaviours and expected states from a user-perspective, that said there is (as with all things programming) infinite variation in interpretation.

They tend to follow the pattern:

* **"GIVEN"** *(An initial state)*
* **"WHEN"** *(An event occurs)*
* **"THEN"** *(An expected outcome is achieved)*

We'll assume our ticket has the following acceptance criteria, feel free to come back to this list:

```swift
GIVEN the user navigates to the widget list
WHEN the view is shown and there is no widget data
THEN we see an empty state placeholder

GIVEN the user navigates to the widget list
WHEN the view is shown
THEN we see the app is checking for updates

GIVEN the user is on the widget list
WHEN the app is checking for widget updates
THEN we see an indicator of progress

GIVEN the user is on the widget list
WHEN widget data has been loaded
THEN the user sees a scrollable list of widgets with name and price in alphabetical order

GIVEN the user navigates to the widget list
WHEN the view has widget data
THEN they are shown when the widgets were last updated as a relative date e.g. 1 minute ago, 3 hours ago.

GIVEN the user is on the widget list
WHEN there is an error
THEN an error message and a reload button are shown 

GIVEN the user is on the widget list
WHEN widget data is being loaded or has been loaded
THEN the reload button is hidden and any error message is hidden

GIVEN the user is on the widget list
WHEN the app successfully checks for updates
THEN the app does not check for widget data for another 60 seconds
```
We read the acceptance criteria and built out our `WidgetListView` using a `WidgetListViewModel` to encapsulate our screen's logic and functionality.

Now, because this class and functionality is critical to our application, we want to write some unit tests to make sure it works correctly and as expected.

Let's cover what our class looks like right now and bonus points if you can find everything wrong with this (*Hint*: there's a lot wrong with it):

```swift
// NOTE: These are our network data types
struct WidgetResponse: Codable {
    let id: UUID
    let name: String
    let price: Decimal
}

struct WidgetsResponse: Codable {
    let widgets: [WidgetResponse]
    let lastUpdated: Date
}
```

```swift
// NOTE: This is our view model
final class WidgetListViewModel: ObservableObject {

    var widgets: [WidgetResponse] = []
    var errorMessage: String?
    // NOTE: Using Date here makes it hard to test
    var lastPolledDisplayDate: String {
        RelativeDateTimeFormatter()
            .localizedString(
                for: lastPolled,
                relativeTo: Date()
            )
    }
    private var lastPolled: Date = Date().addingTimeInterval(-60)

    func load() {
        guard lastPolled < Date().addingTimeInterval(-60) else {
            debugPrint("AppViewModel", "load", "Loaded too recently")
            return
        }
        let backendURL = URL(
            string: "https://run.mocky.io/v3/d5e2f910-6cd4-4055-8653-ff0c36f28f34"
        )!

        _ = URLSession
            .shared
            .dataTask(
                with: backendURL
            ) { data, response, error in
                let decoder = JSONDecoder()
                if let data = data {
                    let widgets = try? decoder.decode(
                        WidgetsResponse.self,
                        from: data
                    )

                    self.widgets = widgets?.widgets ?? []
                }
                    self.lastPolled = Date()
            }

        //task.resume()
    }
}
```

Hopefully you'll have spotted a bunch of issues here but let's start by writing our first test. There are lots of different styles for test naming but we'll use this pattern for argument state:
 `func test_{functionName}_{initialState?}_{expectedResultState}`

#### Let's write our first test 

```swift
import XCTest
@testable import RefactoringToTests

final class WidgetListViewModelTests: XCTestCase {

    func test_init_hasExpectedDefaults() {
        let model = WidgetListViewModel()

        XCTAssertTrue(model.widgets.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual("", model.lastPolledDisplayDate)
    }
}
```
Can you see what's going to fail?

#### Our first test failure

```swift
XCTAssertEqual failed: ("") is not equal to ("1 minute ago")
```

If we jump back to our ACs, it says:
```
...
WHEN the view has widget data
THEN they are shown when the widgets were last updated
```

Our code here fails because of this code
```swift
    var lastPolledDisplayDate: String {
        RelativeDateTimeFormatter()
            .localizedString(
                for: lastPolled,
                relativeTo: Date()
            )
    }
    private var lastPolled: Date = Date().addingTimeInterval(-60)
```

When we built this, we were thinking of the other AC:
```
...
WHEN the app successfully checks for updates
THEN the app does not check for widget data for another 60 seconds
```
We introduced the time-based check to stop too many requests but needed


// Not using Widgets.lastUpdated
//

/*
    Time-based code
    Networking
    File-IO
    Database
 */

protocol CurrentDateProviding {
    func now() -> Date
}

extension Date: CurrentDateProviding {
    func now() -> Date {
        Date()
    }
}

final class FakeCurrentDateProvider: CurrentDateProviding {

}


-----

When a class relies on another class, you're creating an implicit tight-coupling between the two.

SOLID principles

Interface segregation principle
- A client should never be forced to implement an interface that it doesn’t use, or clients shouldn’t be forced to depend on methods they do not use.

Split your protocols down discretely (Reader, Writer)

Dependency Inversion Principle

[Depend on abstraction, not on concretions]
Entities must depend on abstractions, not on concretions. It states that the high-level module must not depend on the low-level module, but they should depend on abstractions.

[^1]: Test Driven Development
[^2]: Behaviour Driven Development