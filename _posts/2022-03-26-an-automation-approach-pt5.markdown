---
layout: post
title: UI testing, a simple approach - Part 5
excerpt_separator:  <!--more-->
tags: testing automation
---

### UI test automation continued... where did we get to?
In the [previous post](https://blog.codeglee.com/2022/03/25/an-automation-approach-pt4.html), we solved our test pollution issues by introducing a `Dependency Injection Container` with an isolated _in-memory_ replacement for `UserDefaults`.

In this post:

* We'll start with the problems and opportunities of testing around networking
* We'll take a look at approaches for handling networking.
* We'll also look at how you can wait for state changes that take time (for animations to finish or networking to complete, for example).

### Networking, the ally and enemy of UI tests?

There are different schools of thought on exactly what UI tests should be, should cover and what test-specific affordances the app should contain. 

UI tests can cover:

* User behaviour that cannot be easily unit tested, navigation, visual state changes, animations
* Integration tests proving that modules in your app work together as expected, for example authentication flows resulting in the expected UI states (logged in, error states, logged out etc).
* Asserting that the content of your views is as expected, text, imagery, visual order, accessibility, localisation
* Integration with third party dependencies, network and other resource availability

_But should they?_ It's up to you what you think will add the most value to you and your team and save the most time. When considering this you have to consider the balance of _authenticity_[^1] vs _controlled representation[^2]_, what do I mean by this?

On one side, the more _authentic_ you keep your UI tests, the less consistent, predictable and timely your UI tests are likely to be. On the flipside the closer your tests are to reality, the more confidence you can have that issues found in tests are likely to exist in production too.

Compare that to a _controlled_ approach, where you'd control aspects of the resources and dependencies your app uses like we did with `UserDefaults` in the last post, and you can end up with faster, more dependable, consistent results in your tests. This is at the risk[^3] of missing scenarios, edge cases and states that you haven't controlled or tested for.

_Hopefully_, this has you thinking about where UI tests will add most value for you. That said, let's dig in to some options:

1. You use the _production / live_ endpoint for your tests just like your app does
	* **Pros:**
		*  If your tests fail, you can be confident you've got an issue in the production app too[^4].
		*  If your APIs change and your tests now fail, you know the app (or tests) are out of sync with the backend and need updating to match[^5].
	*  **Cons:**
		*  Fundamentally, your tests are relying on state that's not in your control. Your APIs are subject to change and your live data is also potentially transient, meaning your tests could start failing at any time.
		*  You've added additional load to your backend, if you're not careful you could even bring down your backend if it's not prepared for sporadic sudden load from your tests.
		*  Your tests are subject to any latency introduced by the app needing to make network requests and waiting for responses forcing your tests to be written with an _unknown_ wait-timeout in mind.
		*  Server maintenance, outages or connectivity issues could result in failures which may or may not be useful. **_NOTE:_** It's worth pointing out that UI tests are often run outside of busy periods due to taking a long time, often on a midnightly-basis... which is also a common window for server-upgrades to be applied due to affecting fewer people, you can see the impact this might have.
		*  _Test pollution_ isn't just an app-side issue, remember if you're using a live endpoint and your tests mutate data then you're prone to the same _test pollution_ issues we covered in the previous post except with no way to mitigate them.
2. You use a _test-specific_ endpoint such as a staging / dev version of your production endpoint
	*  **Pro:** In theory, you can keep a dedicated endpoint more static than a live endpoint. If it's under your control then it's more predictable than production, i.e your UI tests can be more consistent and are less likely to fail unexpectedly.
	*  **Cons:**
		*  All of the cons in #1 above
		*  You've added a maintenance burden and this endpoint needs to be kept in sync with producton, if you're out of sync and there's a breaking change for example, your tests could still pass but your production app would fail.
3. You create a mock web server either in app or on the box
	*  **Pros:**
		*  Minimal changes to your networking pipeline, `URLSession` works the same, ignorant of the change in where the responses have come from, you just point to a different url here's [an example approach](https://www.marcosantadev.com/run-swift-ui-tests-mock-api-server/).
		*  Limited to no latency on network calls as it's running locally, fast, stable and predictable.
	*  **Cons:**
		*  Harder to configure, understand, and maintain.
		*  If the API contract changes you won't catch it via these tests as you're 'baking-in' known responses which adds a maintenance cost.
4. You mock your network calls through a `URLProtocol` subclass to return local responses, either custom built responses or by reading local files.
	* 	**Pros:**
		*  Minimal networking changes to supply static/cached responses to your `URLSession` requests.
		*  There are no network round-trips so you end up with faster, consistent (idempotent) results in your tests. 	* 	**Cons:**
		*  This is at the risk[^3] of missing scenarios, edge cases and states that you haven't controlled or tested for.
		*  By using fixed / static responses you become responsible for maintaining valid, up-to-date server responses
5. You abstract all your networking calls behind something like a `Provider` or `Middleware` pattern and swap them out with test equivalents like we did with `UserDefaults`
	* 	**Pro:** Bypasses the networking stack entirely in favour of a typed response that can be easier to reason about, build and maintain
	*   Minimal networking changes to supply static/cached responses to your `URLSession` requests.
	* 	**Cons:**
		*  All the cons of #4 above
		*  Not going via `URLSession` means potentially leaving code paths untested and networking bugs undetected

#### We just covered a bunch of options... take a breath
Hopefully you've got some ideas about which options feel right to you. I tend to find mockist approaches most useful but I'll cover some waiting strategies that can help if you have the variability of live networking as an issue.

Let's look at approaches for #4 and #5.

We'll use the [SuperHero DB](https://superheroapi.com/index.html) as our example API, we'll imagine our app state is modelled like this.

```swift
enum LoadState<T>: Codable where T: Equatable, T: Codable {
    case notLoaded
    case loading
    case loaded(_ items: [T])
    case failed(error: String)
}

struct AppState: Codable {
    let characters: LoadState<[CharacterState]>
}

struct CharacterState: Codable, Equatable {
    let id: Int
    let name: String
    let imageURL: URL
}
```

0

Consider writing a UI test for a network-driven visual loading state, if your tests are running on a machine with an incredibly fast connection then you may never see the loading state, so how can you test all the visual states of your app?

URLProtocol mocking
https://www.hackingwithswift.com/articles/153/how-to-test-ios-networking-code-the-easy-way
Same but more advanced https://www.swiftbysundell.com/articles/testing-networking-logic-in-swift/

So why go for a more representative approach?
UI tests take a while to spool up and run, by default they'll use whatever networking stack your simulator / device have available so your tests will have to wait for network requests to be satisfied.

Consider writing a UI test for a network-driven visual loading state, if your tests are running on a machine with an incredibly fast connection then you may never see the loading state, so how can you test all the visual states of your app?

1. You take more direct control over the networking, by using mocks, alternative can inject a 

Should it be:

* A 100% authentic representation of your app, using production endpoints and APIs and all the same resources as the main app i.e more of an integration test between parts of the app as well as external dependencies
* A representation of your app with external dependencies mocked to allow specific test cases and discrete app flows to be tested
* A way to capture 



// TODO: Point out that using a live environment can be a truly representative test of the working state of an app... but with all the cost of potentially slow speeds, relying on an uncontrolled resource, having to code wait mechanisms to cope with latency.
The quicker tests are to run, the more likely they are to be run. If your test end up taking minutes or longer you're likely to end up running them less, introducing things like nightly UI tests or only running UI tests as a gatekeeper around critical branches, such as only running on commits to main / master.

**_NOTE:_**  I'm only going to deal with `URLSession`-based networking.

When it comes to handling networking there are a bunch of options:


So, fundamentally:
- Net

#### So what did we cover?

1. We looked at a strategy for handling endpoint switching (//TODO: Maybe switch out into separate post given the info.plist etc)
2. URLSessionProvider + URLSessionConfig.protocolClasses via URLProtocol
3. Scheme-based build phase injecting files


### What do we do next?
* Setting [Locale](https://useyourloaf.com/blog/using-launch-arguments-to-test-localizations/), screenshots, fastlane screenshots?


I hope this post was informative, feel free to send me your thoughts via Twitter.

**Footnotes**

[^1]: _Authenticity here means keeping the resources and dependencies of your app as close to original as possible, to ensure your UI tests most closely reflect the real world experience of a user_
[^2]: _By controlled representation I mean you're taking control of some of the dependencies and resources, meaning you get a representative result but it may differ from the real world experience_
[^3]: _Unless you've managed to map every scenario, the potential network responses and any other resources_
[^4]: _Ideally, your backend team has active monitoring and logging in place so your UI tests are not responsible for this_
[^5]: _Ideally you've got contracts defined with your backend-team to ensure breaking API changes and outages are well-managed. Understanding that unlike the web that can simply update pages live, API changes will continue to affect older iOS apps. i.e break once, break everywhere, break forever_
