---
layout: post
title: Wake up to Redux - a state management pattern
excerpt_separator:  <!--more-->
---

#### Take a breath
I'm about to tell you a dark tale. A story not so far from reality in a lot of codebases, as one might like to think.

Picture if you will, a core team building out an application over several years starting with a prototype, small in scope and with a well-defined architecture.

Over time it evolves as requirements and features change, different team members come and go, different philosophies, patterns and architectures are applied. In the dark recesses of the codebase, tech debt increases.

In time, the app reaches a point of sufficient size and complexity that no one person can keep the whole of the app in their head.
Not only that, the underlying data that drives the app is becoming more complex and mysterious with any manner of asynchronous or background processes mutating the data at any time.

The app is no longer predictable, unexpected state bugs manifest seemingly at random, inspecting the current state is nigh on impossible and debugging issues is mind-boggling. Then come the race conditions, multiple places wrestling each other, trying to update the data at the same time. You can barely see straight, sleep escapes you, you don't know where you are anymore.

#### It's okay, mop your brow, it was just a nightmare
You're safe and among friends, this is but a cautionary tale to tell you about **Redux**, a state management pattern that can help alleviate and entirely avoid these kinds of horrors.

Thankfully the mobile teams I've worked with haven't had issues quite this extreme to deal with but you should always open to potential code and quality improvements.

So, if you have no idea who, why or what is changing your data from one moment to the next, struggle with race conditions or order of operation bugs or find it hard to debug or inspect the state of your app, read on.

Still here? great, let's dig into the central tenets of Redux:

**Single source of truth**

- The state of the app is stored in an object tree with a single point of access.

**State is read only**

- State can only be changed by dispatching `Actions`
    - Actions encapsulate the intent to transform the state
- All changes are made synchronously, applied one-by-one in a strict order
    - This results in no race conditions
- Actions are simple objects and can be logged, serialised and easily tested

**State is transformed by using pure functions**
- Reducers are pure functions that take a previous state, an action to be applied and return the next state.
- Reducers are called in order and can be split into smaller reducers dealing with specific state
- Pure functions are super testable, pass an action, get a state back. Is it the expected state? Great! No need for mocks.

Three strong principles that hopefully you can already see the glimmer of utility in. It's worth calling out that although these are the _intended_ pillars and will serve you well, there's a lot of [nuance](https://blog.isquaredsoftware.com/2017/05/idiomatic-redux-tao-of-redux-part-1/) to how you might go about using it.

Principles aside, Redux consists of a few different parts.

- `Store`
    + Holds the `State`
    + Dispatches Actions
    + Applies reducers to actions and exclusivey updates the state
- `Reducer`
    + A pure function taking the current `State`, an `Action` and returns an updated `State`
    + If a specific `Reducer` doesn't handle the `Action` then it may return `State` unchanged.
- `Actions`
    + Primitive objects that contain the intended change and nothing more
    + Keep free of reference types

There are optional components that can be added that I'll try and cover later. `Middleware` + `ActionCreators` both enable asynchronous actions.

In `Swift` this could look something like this:

```
final class Store {
    private let reducer: Reducer
    private let serialDispatcher: DispatchQueueing
    private let mainThreadDispatcher: Dispatching
    private(set) var state: State

    init(
        state: State,
        reducers: [Reducer],
        serialDispatcher: DispatchQueueing,
        mainThreadDispatcher: Dispatching
        ) {
            self.serialDispatcher = serialDispatcher
            self.mainThreadDispatcher = mainThreadDispatcher

            let combinedReducers: Reducer = { state, action in
                return reducers.reduce(state) { $1($0, action) }
            }
            self.reducer = combinedReducers
            self.state = state
        }

    func dispatch(action: ActionProtocol) {
        serialDispatcher.enqueue { [weak self] in
            guard let self = self else { return }
            
            let initialState = self.state
            
            self.state = self.reducer(initialState, action)
        }
    }
}
```

```
protocol ActionDispatching {
    func dispatch(action: ActionProtocol)
}

protocol ActionProtocol {}
```

`typealias Reducer = (_ state: AppState, _ action: ActionProtocol) -> AppState`

```
//NOTE: This could be implemented as an OperationQueue subclass with maxConcurrentOperationCount of 1
protocol DispatchQueueing {
    func enqueue(_ block: @escaping() -> Void)
}

//NOTE: This could be a wrapped DispatchQueue
protocol Dispatching {
    func async(_ block: @escaping () -> Void)
}
```

**That's it!**
With this solution you can safely dispatch an action without fear, you can fully test every aspect of state mutation.

*Except*... what about asynchronous actions? what about state change notifications?

**Good questions! Give yourself a pat on the back!**
As with all programming problems there are any number of solutions.
Let's start with **asynchrony**. There are two approaches that seem to have traction, `Middleware` and `Action Creators`.

`Middleware` is called with an `Action` before the `State` has changed. `Middleware` is not allowed to mutate the state and **cannot block execution**, it's basically just an opportunity to kick start async operations, potentially with callbacks or long-running task completion handlers.
If `Middleware` wants to update the `State` it enqueues `Actions` via the `Store`.

`Action Creators`, sometimes called `Thunks` encapsulate a function, so rather than just being a plain old object containing data, it may act on that data too before dispatching an `Action` itself on completion.
To avoid blocking, `Action Creators` can be performed via `Middleware`.

Essentially both allow you to encapsulate asynchronous actions without blocking, in slightly different ways. Pick your poison.

Let's say you're writing an app to sell `Widgets`.

```
struct State {
    let widgets: [Widget]
}

struct Widget {
    let id: Int
    let name: String
}
```

On your `WidgetListViewController` you want to let users `Refresh` the list of `Widgets` so you call `store.dispatch(RefreshWidgetsAction())`.

Here's how we define our middleware:

```
protocol Middleware {
    func apply(state: State, action: Action)
}
```

Our widget provider:

```
protocol WidgetProviding {
    func provideWidgets(completion: () -> [Widget])
}
```

The middleware to perform async widget providing.

```
final class WidgetProviderMiddleware: Middleware {
    private let widgetProvider: WidgetProviding
    private let backgroundDispatcher: Dispatching
    private let actionDispatcher: ActionDispatching
    private let requestFrequencyLimitInSeconds: TimeInterval
    
    private var widgetsLastProvided: Date = Date()

    init(...)

    func apply(state: State, action: Action) {
        switch action {
            case let action as RefreshWidgetsAction {
                backgroundDispatcher.async { [weak self] in
                    //NOTE: Naively limit requests to once every N seconds
                    if Date() > widgetsLastProvided.addingTimeInterval(requestFrequencyLimitInSeconds) {
                    widgetProvider.provideWidgets { widgets in
                        //NOTE: Async action completed, let's update the state
                        actionDispatcher.dispatch(UpdateWidgetsAction(widgets: widgets))
                        widgetsLastProvided = Date()
                    }
                }
            }
}
```

Now the `Reducer` to update the state:

```
func reduce(state: State, action: ActionProtocol) -> State {
    switch action {
        case let action as UpdateWidgetsAction:
            return State(widgets: action.widgets)
        default: return state
    }
}
```

There we go, our `WidgetListViewController` can dispatch `RefreshWidgetActions` with no knowledge of what happens to it.
The `Action` passes through the `WidgetProviderMiddleware` which kicks off a network / database fetch operation and on completion the middleware dispatches a new action to update the `Widgets` through a `Reducer`.

There are other scenarios you might feasibly want to handle, maintaining load states, limiting request frequency etc. Note that if you start modelling load states you need to guarantee that those states are updated in failure as well as success paths.

It's worth noting that your `Redux` `State` type should be considered model data, not VIEW data. Your view might ultimately transform the source `State` before presentation but that separation should be maintained. Allowing your `State` to grow massive may become a headache and result in performance problems. Don't fill your `State` with `Data` or `UIImage`s, store identifiers that can be loaded on demand. Your choices around allowing `Optional` state might help if you wanted to allow partial `State` loading.

Now, say you want to track certain events in the app, just add an `AnalyticsMiddleware`, easy!

```
final class AnalyticsMiddleware: Middleware {

    private let backgroundDispatcher: Dispatching
    private let externalTracker: Tracking

    init(...)

    func apply(state: State, action: Action) {
        switch action {
            case let action as RefreshWidgetsAction {
                backgroundDispatcher.async { [weak self] in
                    self?.externalTracker.refreshWidgetsRequested()
                }
            }
            default: return
        }
    }
}

struct RefreshWidgetsAction: Action {}
```

So we've got `State` mutation and `Asynchronicity` locked down but our `WidgetListViewController` doesn't update yet!

Pick your choice of `Observable` model, maybe you're using `RxSwift`, `Combine`, `KVO` or any other pattern that does Publisher / Subscriber notifications.

An example might be as simple as defining a listener:

```
protocol UpdateListener {
    func stateUpdated()
}
```

In our `Store`:

```
private var listeners: [UpdateListener]

private(set) var state: State {
    didSet {
        mainThreadDispatcher.async {
            [weak self] in
            
            self?.listeners.forEach {
                $0.stateUpdated()
            }
        }
    }
}
```

In our `WidgetListViewController`:

```
//NOTE: Assumes our widgetListCollectionView data source accesses State on reload

extension WidgetListViewController: UpdateListener {
    func stateUpdated() {
        widgetListCollectionView.reloadData()
    }
}
```

You can make it more reactive than that, but essentially that's it end to end.

---

### Conclusion
Hopefully, you can see the value such an approach might have.:
- Our `State` is consistent, predictable and (functionally) immutable.
- Every part is easily tested from the `Store` through the `Reducers` and `Middleware` without creating Mocks (*cough* except thread dispatchers).
- It's easy to inspect the current state
- You can track every dispatched action end to end making it easy to debug.

There we go ladies, gentlemen and the plethora of goodness in between.
*Redux*, can it help save you from your nightmares?
