---
title: "Decoupled CRTP in C++: classic CRTP, OpenJDK-style decoupling, and the C++23 mixin style"
description: What classic CRTP is, what decoupled CRTP means in the OpenJDK-style design, and how C++23 explicit object parameters relate to both.
date: 2026-05-21 07:40:00 +0200
tags:
  - c++
  - templates
  - c++23
  - crtp
---

When people say **CRTP**, they usually mean the classic pattern:

```cpp
template <class Derived>
struct Base {
    void interface() {
        static_cast<Derived&>(*this).implementation();
    }
};

struct Widget : Base<Widget> {
    void implementation() {
        // ...
    }
};
```

The base takes the derived type as a template parameter and calls into it with `static_cast<Derived&>(*this)`.

That gives you **static polymorphism**:

- no `virtual`,
- no vtable lookup,
- and the compiler can often inline through the whole call chain.

But **decoupled CRTP** usually means something more specific than "CRTP with less boilerplate". In the OpenJDK-style design, it means:

1. the **outer base class is not templated**,
2. the CRTP connection is moved into **nested templated helper layers**,
3. and a **runtime-selected function pointer** is resolved once and reused on the hot path.

The usage here follows Shubhankar Gambhir's article
["Four ways to dispatch a runtime-selected strategy in C++"](https://shubhankar-gambhir.github.io/posts/four-ways-to-dispatch-a-runtime-selected-strategy-in-cpp/),
which uses the term for an OpenJDK-inspired runtime-dispatch design rather than for C++23 mixin syntax.

That is different from the C++23 `this auto&` / explicit-object-parameter feature. C++23 is related and useful, but it is **not** what that article means by decoupled CRTP.

## Classic CRTP in one minute

Here is the standard reusable-base pattern:

```cpp
#include <iostream>

template <class Derived>
struct Printable {
    void print() const {
        auto const& self = static_cast<Derived const&>(*this);
        std::cout << self.to_string() << '\n';
    }
};

struct User : Printable<User> {
    std::string to_string() const {
        return "User{name=Daniel}";
    }
};
```

This is useful because the base can provide reusable logic while the derived class provides the customization point.

That is the classic CRTP story:

- `Printable<User>` provides `print()`,
- `User` provides `to_string()`,
- and dispatch is resolved at compile time.

## Where classic CRTP breaks down

Classic CRTP couples the base to the derived type:

```cpp
struct User   : Printable<User>   {};
struct File   : Printable<File>   {};
struct Order  : Printable<Order>  {};
```

That is usually fine when everything is compile-time and local.

But imagine a different problem:

- you have several strategies,
- the user chooses one at startup,
- and then a tiny operation is called millions of times.

For example:

- a garbage-collector barrier,
- a logging strategy,
- a packet-processing hook,
- a storage write policy.

Now classic CRTP runs into a structural problem:

```cpp
template <class Derived>
class BarrierSet {
public:
    void store(int* addr, int value) {
        static_cast<Derived*>(this)->do_store(addr, value);
    }
};
```

If the active implementation is selected **at runtime**, what is `Derived` supposed to be?

You cannot write:

```cpp
BarrierSet<???>* current;
```

That is the core limitation. Conventional CRTP wants the derived type baked into the base type, but runtime strategy selection wants a single non-templated handle.

## What decoupled CRTP means

The trick is to **flip the relationship**.

Instead of this:

```cpp
template <class Derived>
class BarrierSet { ... };
```

you make the outer base non-templated:

```cpp
class BarrierSet { ... };
```

and move the CRTP-style connection into a nested helper:

```cpp
struct BarrierSet {
    template <class BarrierSetT>
    struct Access {
        static void store(int* addr, int value) {
            static_cast<BarrierSetT*>(current())->do_store(addr, value);
        }
    };

    static BarrierSet* current();
};
```

Now the outer type `BarrierSet` exists independently of any concrete derived class, which means you can keep a runtime-selected singleton or pointer of type `BarrierSet*`.

The template parameter lives only in the nested access layer.

That is the "decoupled" part.

## Why this matters

This solves two problems at once.

First, you can keep a non-templated runtime handle:

```cpp
BarrierSet* active_barrier_set;
```

Second, you still generate compile-time-specialized code for each concrete implementation:

- `G1BarrierSet::Access<G1BarrierSet>::store`
- `SerialBarrierSet::Access<SerialBarrierSet>::store`
- `EpsilonBarrierSet::Access<EpsilonBarrierSet>::store`

So the runtime system can choose **which precompiled static path** to use.

## Layering behavior instead of duplicating it

The pattern gets more interesting when you compose behavior in layers.

Here is the simplified OpenJDK-style idea.

### Layer 0: raw write

```cpp
struct BarrierSet {
    template <class BarrierSetT>
    struct Access {
        static void store(int* addr, int value) {
            *addr = value;
        }
    };

    static BarrierSet* current();
};
```

### Layer 1: add a post-barrier

```cpp
struct CardTableBarrierSet : BarrierSet {
    template <class BarrierSetT>
    struct Access : BarrierSet::Access<BarrierSetT> {
        static void store(int* addr, int value) {
            BarrierSet::Access<BarrierSetT>::store(addr, value);
            record_modified_region(addr);
        }
    };

    static void record_modified_region(int* addr);
};
```

### Layer 2: add a pre-barrier

```cpp
struct G1BarrierSet : CardTableBarrierSet {
    template <class BarrierSetT>
    struct Access : CardTableBarrierSet::Access<BarrierSetT> {
        static void store(int* addr, int value) {
            save_old_value(addr);
            CardTableBarrierSet::Access<BarrierSetT>::store(addr, value);
        }
    };

    static void save_old_value(int* addr);
};
```

That gives a clean layering model:

- `BarrierSet` = raw store
- `CardTableBarrierSet` = raw store + post-barrier
- `G1BarrierSet` = pre-barrier + raw store + post-barrier

Each layer adds one concern and delegates to the parent layer.

That is the main benefit over hand-written function-pointer implementations where every strategy often duplicates the full logic.

## Lazy resolution: resolve once, dispatch forever

Decoupled CRTP is usually paired with **lazy resolution**.

The idea is simple:

1. at startup or first use, inspect the selected runtime strategy,
2. choose the correct precompiled access function,
3. cache it in a function pointer,
4. call that pointer on the hot path forever after.

Conceptually:

```cpp
struct RuntimeDispatch {
    using StoreFn = void(*)(int*, int);

    static inline StoreFn store_fn = &store_init;

    static void store_init(int* addr, int value) {
        switch (BarrierSet::current()->kind()) {
            case Kind::g1:
                store_fn = &G1BarrierSet::Access<G1BarrierSet>::store;
                break;
            case Kind::serial:
                store_fn = &CardTableBarrierSet::Access<CardTableBarrierSet>::store;
                break;
            case Kind::epsilon:
                store_fn = &BarrierSet::Access<BarrierSet>::store;
                break;
        }

        store_fn(addr, value);
    }

    static void store(int* addr, int value) {
        store_fn(addr, value);
    }
};
```

After the first call, there is no switch anymore. The hot path is just an indirect function call to the already-resolved implementation.

That is why this pattern is attractive in performance-sensitive runtime systems.

## Why conventional CRTP is not enough here

Classic CRTP gives compile-time dispatch, but it assumes the concrete type is known when you write the base:

```cpp
template <class Derived>
struct Base { ... };
```

Decoupled CRTP changes the shape so that:

- the **outer runtime-facing type** is non-templated,
- the **compile-time specialization** lives in nested access layers,
- and the final implementation can still be selected dynamically once.

So this is not just "CRTP but cleaner". It is a structural change that makes CRTP-style composition usable in a runtime-selected system.

## The important caveat

This pattern is powerful, but there is a sharp edge.

In classic CRTP, `static_cast<Derived*>(this)` is safe because `this` really is the derived object by construction.

In decoupled CRTP, the cast often targets a global or singleton base pointer:

```cpp
static_cast<G1BarrierSet*>(BarrierSet::current())
```

That means the runtime resolution logic must pair:

- the correct concrete object,
- with the correct concrete `Access<...>` instantiation.

If those do not match, you have undefined behavior.

So the design is fast, but it relies on disciplined initialization and correct type selection.

## Where C++23 fits in

C++23 explicit object parameters are a **different** improvement.

They let you write CRTP-like reusable mixins without spelling `Base<Derived>`:

```cpp
struct Printable {
    void print(this auto const& self) {
        std::cout << self.to_string() << '\n';
    }
};

struct User : Printable {
    std::string to_string() const {
        return "User{name=Daniel}";
    }
};
```

This is great for many day-to-day CRTP-style use cases because it removes a lot of boilerplate.

But it does **not** by itself solve the decoupled-CRTP runtime-selection problem above.

So the right comparison is:

- **classic CRTP** = `Base<Derived>`
- **decoupled CRTP** = non-templated outer base + nested templated access layers + runtime lazy resolution
- **C++23 explicit object parameter style** = a cleaner way to write many static-mixin patterns, but not the same runtime architecture

## Old and new side by side

### Classic CRTP

```cpp
template <class Derived>
struct Equality {
    bool equal(Derived const& other) const {
        auto const& self = static_cast<Derived const&>(*this);
        return self.key() == other.key();
    }
};
```

### C++23 mixin style

```cpp
struct Equality {
    bool equal(this auto const& self, auto const& other) {
        return self.key() == other.key();
    }
};
```

These two are close in spirit.

Decoupled CRTP is different: it is about keeping the outer runtime-facing interface non-templated while still using compile-time layering internally.

## When to use what

Use **classic CRTP** when:

- the problem is compile-time only,
- the type is known statically,
- and `Base<Derived>` is not a burden.

Use **C++23 explicit object parameters** when:

- you want CRTP-like mixins,
- you have a modern toolchain,
- and you want less boilerplate for static polymorphism.

Use **decoupled CRTP** when:

- the concrete strategy is selected at runtime,
- the hot path is performance-sensitive,
- you want compile-time composition of layered behavior,
- and a non-templated runtime-facing base is important.

## Final thought

The easiest way to remember the distinction is:

- **classic CRTP** says: "the base knows the derived type"
- **decoupled CRTP** says: "the outer base does not know the derived type, but nested access layers do"
- **C++23 mixin style** says: "many classic CRTP mixins no longer need `Base<Derived>` at all"

That is why the OpenJDK-style pattern is interesting. It is not just prettier CRTP. It is a way to keep **runtime flexibility** and **compile-time composition** at the same time.
