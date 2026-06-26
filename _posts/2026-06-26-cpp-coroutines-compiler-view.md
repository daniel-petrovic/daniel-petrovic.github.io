---
title: C++ coroutines through the compiler's eyes
description: A reference-style walkthrough of how the C++ standard specifies coroutines and the co_await expression, distilled into pseudocode that mirrors what a compiler actually does.
date: 2026-06-26 10:00:00 +0200
tags:
  - c++
  - coroutines
  - compiler
  - language
---

The C++ standard specifies coroutines and `co_await` in two key sections:

- **[`[dcl.fct.def.coroutine]`](https://eel.is/c++draft/dcl.fct.def.coroutine)** — what makes a function a coroutine, the promise type, the replacement body, allocation.
- **[`[expr.await]`](https://eel.is/c++draft/expr.await)** — the `co_await` expression itself: how the awaiter is built and how suspension works.

Both sections are written as precise normative wording, but they are already very close to an algorithm. This post strips away the legalese and shows what the compiler actually does, using pseudocode that follows the specification almost one-to-one.

---

## 1. What makes a function a coroutine

A function is a coroutine if its body contains a `co_return`, `co_await`, or `co_yield`.

```cpp
task<int> f();

task<void> g() {
    int i = co_await f();
    co_return i + 1;
}
```

The return type (`task<int>`) must name a promise type via `std::coroutine_traits<R, Args...>::promise_type`.

---

## 2. The replacement body (`[dcl.fct.def.coroutine]`)

The standard says the compiler behaves *as if* the function body were replaced by the following (paraphrasing paragraph 5):

```
{
    promise-type promise promise-constructor-arguments;
    try {
        co_await promise.initial_suspend();
        function-body
    } catch (...) {
        if (!initial-await-resume-called)
            throw;
        promise.unhandled_exception();
    }
final-suspend:
    co_await promise.final_suspend();
}
```

The `initial-await-resume-called` flag starts `false` and is set to `true` just before `await_resume()` of the initial suspend completes.

### 2.1 Promise construction

The promise is constructed with an argument list `q1, q2, ..., qn`:

- For a non-static member function, `q1` is `*this` (the object parameter), and `q2...qn` are lvalue copies of the function parameters.
- For a free function, `q1...qn` are lvalue copies of the function parameters.
- If no matching constructor is found, `promise-constructor-arguments` is empty.

### 2.2 Return object

Before `initial_suspend`, the compiler calls `promise.get_return_object()`. This is evaluated once and used to initialize the return value.

---

## 3. Full coroutine transformation pseudocode

Combining paragraphs 5, 8, 10, and 11 of `[dcl.fct.def.coroutine]`:

```
R coroutine(P1 p1, P2 p2, ...)
{
    // ---------------------------------------------------------------
    // 1. Allocate coroutine state (the "frame")
    // ---------------------------------------------------------------
    //   Lookup operator new in scope of promise_type, then ::operator new.
    //   The parameter copies p1, p2, ... can be passed as additional
    //   arguments for a placement allocation function.

    frame* state = allocate_coroutine_frame(sizeof(frame_state), p1, p2, ...);

    if (state == nullptr) {
        // Only if promise_type::get_return_object_on_allocation_failure exists.
        return promise_type::get_return_object_on_allocation_failure();
    }

    // ---------------------------------------------------------------
    // 2. Copy parameters into the frame (they survive suspension)
    // ---------------------------------------------------------------
    state->p1 = std::move(p1);
    state->p2 = std::move(p2);
    // ...

    // ---------------------------------------------------------------
    // 3. Construct the promise object inside the frame
    // ---------------------------------------------------------------
    promise_type& promise = construct_at(&state->promise, state->p1, state->p2, ...);

    // ---------------------------------------------------------------
    // 4. Obtain the return object
    // ---------------------------------------------------------------
    R return_object = promise.get_return_object();

    // ---------------------------------------------------------------
    // 5. Obtain a handle to self (for await_suspend)
    // ---------------------------------------------------------------
    coroutine_handle<promise_type> self =
        coroutine_handle<promise_type>::from_promise(promise);

    bool initial_await_resume_called = false;

    // ---------------------------------------------------------------
    // 6. Execute the replacement body
    // ---------------------------------------------------------------
    try {
        // -- initial suspend --
        co_await promise.initial_suspend();
        initial_await_resume_called = true;

        // -- user body --
        function_body;
    }
    catch (...) {
        if (!initial_await_resume_called)
            throw;
        promise.unhandled_exception();
    }

final_suspend:
    // -- final suspend --
    co_await promise.final_suspend();

    // -- destroy frame --
    destroy_locals();
    std::destroy_at(&promise);
    operator delete(state);
}
```

---

## 4. The `co_await` expression (`[expr.await]`)

This is the heart of coroutine suspension. Paragraphs 3–5 define the machinery in terms of exposition-only objects `a`, `o`, `e`, `h`.

### 4.1 Building the awaiter (paragraph 3)

```
// Step 1: optional await_transform
//   If the promise type defines await_transform and this co_await
//   is not an implicit yield/initial/final await, then
//   a = promise.await_transform(expr).
//   Otherwise, a = expr directly.

awaitable a;
if (has_await_transform<promise_type> && !implicit_await) {
    a = promise.await_transform(expr);
} else {
    a = expr;
}

// Step 2: operator co_await resolution
//   Look for a viable operator co_await for a.
//   If found, o = operator co_await(a).
//   If not found, o = a.
//   If o is a prvalue, materialise it to an xvalue.

awaiter o = resolve_operator_co_await(a);

// Step 3: e is an lvalue referring to o
awaiter& e = o;

// Step 4: h is the coroutine handle for the enclosing coroutine
coroutine_handle<promise_type> h = /* handle of current coroutine */;

// Step 5: define the three required member calls
//   await-ready  → bool(e.await_ready())
//   await-suspend → e.await_suspend(h)
//       Must return void, bool, or coroutine_handle<Z>.
//   await-resume  → e.await_resume()
```

### 4.2 Execution (paragraph 5)

```
// ---------------------------------------------------------------
// Evaluate the await-expression
// ---------------------------------------------------------------
// The result type and value category of the entire co_await
// expression match those of e.await_resume().

if (!bool(e.await_ready())) {
    // The coroutine is now considered suspended.
    // We are at a coroutine suspend point.

    try {
        auto r = e.await_suspend(h);

        if constexpr (returns<coroutine_handle, decltype(r)>) {
            // Symmetric transfer: resume the returned coroutine.
            // Control eventually returns to this coroutine's caller/resumer.
            r.resume();
            return_to_caller_or_resumer();

        } else if constexpr (returns<bool, decltype(r)>) {
            if (!r) {
                // Do NOT suspend; resume immediately.
                goto resume;
            }
            return_to_caller_or_resumer();

        } else {  // void
            return_to_caller_or_resumer();
        }
    }
    catch (...) {
        // The exception is caught, the coroutine is resumed,
        // and the exception is immediately rethrown.
        goto resume;
    }
}

resume:
return e.await_resume();
```

A subtle point: the `co_await` expression overall has the type and value category of `e.await_resume()`. That is why you can write:

```cpp
int value = co_await some_awaitable;
```

---

## 5. The compiler's actual lowering: a state machine

The standard does **not** mandate a state machine. Every major implementation (Clang, GCC, MSVC) lowers coroutines into a resumable switch-based state machine because that is the obvious way to implement the "suspend and resume later" semantics.

```
struct coroutine_frame {
    promise_type promise;

    // parameter copies (survive suspension)
    P1 p1;
    P2 p2;

    // local variables that live across suspension points
    int x;
    std::string s;
    // ...

    // the suspension state (which resume point to jump to)
    int state = 0;

    R resume() {
        switch (state) {
        case 0:
            // initial suspend
            if (!promise.initial_suspend().await_ready()) {
                state = 1;
                if (promise.initial_suspend().await_suspend(self))
                    return;   // back to caller
            }
            // fall through
        case 1:
            promise.initial_suspend().await_resume();

            // -- user code --
            // co_await some_expr;
            {
                auto aw = /* build awaiter */;
                if (!aw.await_ready()) {
                    state = 2;
                    if (aw.await_suspend(self))
                        return;   // back to caller/resumer
                }
            }
        case 2:
            {
                auto aw = /* rebuild or reference the same awaiter */;
                int result = aw.await_resume();
                // use result...
            }

            // more code, more cases...

        case FINAL:
            // final suspend
            if (!promise.final_suspend().await_ready()) {
                state = FINAL_SUSPENDED;
                auto r = promise.final_suspend().await_suspend(self);
                if constexpr (returns<coroutine_handle, decltype(r)>) {
                    r.resume();
                }
                // never resumes from here in normal flow
                return;
            }
        }
    }
};
```

The key insight: **each suspension point becomes a new state in the state machine**. The state is stored in the coroutine frame and is read on resume to jump to the correct `case` label.

---

## 6. Putting it all together

If you expand every `co_await` in the replacement body using the `[expr.await]` rules, you arrive at something very close to what a compiler front-end generates before the final state-machine lowering:

```
R coroutine(P1 p1, P2 p2, ...)
{
    frame = allocate_frame(...);

    // copy params, construct promise, get return object

    try {
        // ----------------------------------------------------------
        // initial_suspend (co_await promise.initial_suspend())
        // ----------------------------------------------------------
        {
            awaiter& e = /* get awaiter for promise.initial_suspend() */;
            if (!e.await_ready()) {
                suspend;
                switch (e.await_suspend(self)) {
                case coroutine_handle: e.await_suspend(self).resume(); return return_object;
                case bool:             if (e.await_suspend(self)) return return_object; break;
                case void:             e.await_suspend(self); return return_object;
                }
            }
        }
        initial_await_resume_called = true;
        // (await_resume() called implicitly, result discarded)

        // ----------------------------------------------------------
        // user body (with expanded co_awaits)
        // ----------------------------------------------------------
        {
            // co_await expr;
            awaiter& e = /* get awaiter for expr */;
            result_type r = /* see co_await execution above */;

            // ... rest of body ...
        }

    }
    catch (...) {
        if (!initial_await_resume_called)
            throw;
        promise.unhandled_exception();
    }

final_suspend:
    {
        // ----------------------------------------------------------
        // final_suspend (co_await promise.final_suspend())
        // ----------------------------------------------------------
        awaiter& e = /* get awaiter for promise.final_suspend() */;
        if (!e.await_ready()) {
            suspend;
            switch (e.await_suspend(self)) {
            case coroutine_handle: e.await_suspend(self).resume(); /* fall through to cleanup */;
            case bool:             if (e.await_suspend(self)) /* fall through to cleanup */; break;
            case void:             e.await_suspend(self); /* fall through to cleanup */;
            }
        }
    }

    // cleanup
    std::destroy_at(&promise);
    // destroy parameter copies
    // destroy locals
    operator delete(frame);
}
```

---

## 7. Summary

| Standard concept | What the compiler does |
|---|---|
| **Promise type** | `coroutine_traits<R, Args...>::promise_type` — the glue type that controls suspension, return value, and exception handling. |
| **Coroutine frame** | Heap-allocated (or elided) storage for parameters, promise, and live locals. |
| **`co_await expr`** | Builds an awaiter via `await_transform` + `operator co_await`, then calls `await_ready` → `await_suspend` → `await_resume`. |
| **`await_suspend` return types** | `void` — suspend unconditionally; `bool` — conditional suspend; `coroutine_handle<Z>` — symmetric transfer. |
| **State machine** | Each suspension point becomes a `case` in a switch. The state is stored in the frame and read on resume. |
| **`get_return_object()`** | Called once before `initial_suspend` to produce the return value visible to the caller. |
| **Exception handling** | Catches everything; if `initial_suspend` never completed, rethrows; otherwise calls `promise.unhandled_exception()`. |

The two standard sections `[dcl.fct.def.coroutine]` and `[expr.await]` together describe an algorithm that is almost directly executable as pseudocode. The final transformation into a switch-based state machine is an implementation strategy — but it is universal enough that thinking of coroutines as "compiler-generated state machines" is both accurate and useful.
