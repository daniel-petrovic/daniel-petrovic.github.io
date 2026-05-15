---
title: C++26 std::execution, executors, and where the model fits
description: A practical introduction to the standardized C++26 execution model, with code examples and a simple explanation of how execution context is separated from work.
date: 2026-05-15 11:00:00 +0200
tags:
  - c++
  - concurrency
  - executors
---

When people talk about modern C++ executors today, the important name to know is **`std::execution`**.

That matters because the execution model is no longer just a vague future direction: it is now associated with the **C++26 standard model** rather than with a C++23-era discussion.

So the right framing is:

> `std::execution` is the standardized direction for senders/receivers, schedulers, and composable async execution in C++26.

That does **not** mean every compiler and standard library ships the full model today, but it does mean the design is no longer just speculative background material.

## The problem the executor model is trying to solve

In older C++ code, the scheduling decision is often baked directly into the code that does the work:

- `std::thread` creates a new thread immediately
- thread pools often expose their own custom queue APIs
- callback frameworks invent their own scheduling model

That makes async code harder to compose, harder to test, and harder to move between runtimes.

You want to be able to say:

> "run this work on this execution context"

without hardwiring the task itself to a particular implementation detail.

That is the big idea behind executors and schedulers.

## The simple mental model

At a high level:

- **work** is the function you want to run
- **scheduler / executor** decides where that work runs
- **sender/receiver** describes how async work starts, completes, and composes

Even if implementation support is still catching up across toolchains, that separation is the useful part to understand.

## A familiar before-and-after example

Without an executor-like abstraction, code often looks like this:

```cpp
#include <thread>
#include <iostream>

void process_data() {
    std::cout << "processing on a dedicated thread\n";
}

int main() {
    std::thread worker(process_data);
    worker.join();
}
```

This is fine for small examples, but the execution policy is fixed: _spawn a thread right now_.

That is often the wrong level of abstraction. Maybe you really wanted:

- a thread pool,
- an event loop,
- or an inline scheduler during tests.

The executor model tries to make that choice explicit and swappable.

## A tiny executor-shaped example

This is **not** the real standard API, but it shows the idea:

```cpp
#include <functional>
#include <iostream>
#include <queue>

struct inline_executor {
    template <class F>
    void execute(F&& f) const {
        std::forward<F>(f)();
    }
};

int main() {
    inline_executor ex;

    ex.execute([] {
        std::cout << "run immediately on the current thread\n";
    });
}
```

The important part is not the implementation. It is the interface idea:

the caller submits work to an execution context instead of deciding low-level threading details directly.

## A thread-pool flavored example

Again, not standard library code, but closer to what real usage feels like:

```cpp
class thread_pool_executor {
public:
    template <class F>
    void execute(F&& f) {
        queue_.push(std::function<void()>(std::forward<F>(f)));
    }

    void run_one() {
        if (!queue_.empty()) {
            auto task = std::move(queue_.front());
            queue_.pop();
            task();
        }
    }

private:
    std::queue<std::function<void()>> queue_;
};

int main() {
    thread_pool_executor ex;

    ex.execute([] { std::cout << "task A\n"; });
    ex.execute([] { std::cout << "task B\n"; });

    ex.run_one();
    ex.run_one();
}
```

Now the code that defines the task no longer cares whether the implementation uses one worker, many workers, fibers, or something else.

That is the separation people want from the execution model.

## Where `std::execution` fits into this story

The execution model people have been discussing through **P2300** now maps to the standardized **C++26 `std::execution`** direction.

That means the conversation is no longer just:

> "here is a proposal that might become useful one day"

It is now:

> "here is the execution model the standard library is moving toward"

In that world, the central vocabulary is often **scheduler**, **sender**, **receiver**, and algorithms in **`std::execution`**.

The code ends up looking more like a pipeline.

## A sender/receiver style example

This is intentionally written in a `std::execution`-style shape:

```cpp
namespace ex = std::execution;

auto begin_on_pool = ex::schedule(cpu_scheduler);

auto work = begin_on_pool
    | ex::then([] {
        return load_file("input.txt");
    })
    | ex::then([](std::string text) {
        return parse(text);
    })
    | ex::then([](parsed_data data) {
        return analyze(data);
    });

auto result = ex::sync_wait(std::move(work));
```

What is nice about this model is that the code describes:

1. where execution starts,
2. what transformations happen,
3. and where the final result is consumed.

That is much more composable than manually wiring callbacks and ad-hoc futures everywhere.

## Why this model is attractive

There are three big advantages.

### 1. Scheduling becomes explicit

You can see where work starts and where it moves.

### 2. Algorithms become reusable

The async operation can stay the same even if the execution context changes.

### 3. Composition gets much better

Instead of nesting callbacks, you build pipelines of operations.

## A practical caution

It is easy to read executor discussions and think they are about replacing `std::thread` with a more abstract type.

That is only part of the story.

The real goal is a structured async model that handles:

- oversubscription,
- continuation placement,
- cancellation,
- error propagation,
- and value flow between async steps.

So when people say "executors" in the current standardization context, what they often really mean is:

> the `std::execution` model standardized for C++26, including senders/receivers and schedulers.

## Final thought

Now that `std::execution` is part of the C++26 standard direction, the idea is worth learning not just as theory, but as the model modern C++ concurrency is converging on.

The important lesson is simple:

**stop tying the work itself to the mechanism that schedules it**.

Once execution context becomes an explicit part of the model, concurrent C++ code gets easier to compose, easier to test, and easier to evolve.
