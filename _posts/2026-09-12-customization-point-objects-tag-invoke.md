---
title: "C++ Customization Points: Why tag_invoke Was Brilliant—and Why P2300 Moved Away From It"
description: A practical deep dive into C++ Customization Point Objects (CPOs) and tag_invoke (P1895R0)—how CPOs encapsulate dispatch policy, why generic forwarding makes tag_invoke architecturally compelling, real-world adoption in Boost.JSON, why Sender/Receiver moved toward member customization, and what this means for embedded C++.
date: 2026-09-12 10:00:00 +0200
tags:
  - c++
  - c++20
  - metaprogramming
  - boost
  - executors
  - embedded
---

Generic C++ code needs customization points whenever a library wants to operate on types it doesn't own. The problem is deceptively simple: how can a library let users customize an operation without requiring inheritance, runtime dispatch, or modification of the library's source?

C++ has accumulated several answers over the decades—class template specialization, argument-dependent lookup (ADL), and Customization Point Objects (CPOs)—but each leaves important gaps. In 2019, Lewis Baker, Eric Niebler, and Kirk Shoop proposed [P1895R0: tag_invoke — A general pattern for supporting customisable functions](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1895r0.pdf). The core idea was simple: **use one ADL customization name (`tag_invoke`) and encode the operation in the first argument's type**.

This pattern made several architectural techniques considerably easier to express—most notably generic forwarding through wrapper types—and saw adoption in [Boost.JSON](https://www.boost.org/doc/libs/1_86_0/libs/json/doc/html/json/conversion.html) and early sender/receiver execution frameworks. But it also ignited vigorous debate, captured in Barry Revzin's critique, ["Why tag_invoke is not the solution I want"](https://brevzin.github.io/c++/2020/12/01/tag-invoke/).

The central lesson is that **CPOs and `tag_invoke` solve different layers of the customization problem**. A Customization Point Object (CPO) is the user-facing function object that encapsulates an operation's invocation and dispatch policy. `tag_invoke` is a customization protocol that can be used to implement a CPO, or used directly by a library's customization API.

Neither, however, gives C++ a language-level way to declare and verify customization interfaces. Tracing why `tag_invoke` appeared, where it succeeded, and why the Sender/Receiver model eventually moved away from it tells one of the most instructive architectural stories in modern C++.

---

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

* TOC
{:toc}
</nav>

## Crucial Distinction: CPO ≠ tag_invoke

Before digging into mechanics, we should clarify the single most common source of confusion in this area: **a Customization Point Object is not the same thing as `tag_invoke`**.

A Customization Point Object (CPO) is the **user-facing function object** that encapsulates an operation's invocation and dispatch policy. `tag_invoke` is one specific **customization protocol** that a CPO can choose to use under the hood:

```text
Customization Point Object (CPO) [User-facing interface & invocation policy]
        │
        ├── can dispatch via raw ADL (e.g. std::ranges::begin)
        ├── can dispatch via member functions (.begin())
        ├── can dispatch via class template specialization
        └── can dispatch via a tag protocol (e.g. tag_invoke)
```

`tag_invoke` does not replace CPOs; it is a customization protocol that can be used to implement a CPO, or used directly by a library's customization API (as Boost.JSON does).

---

## The Historical Timeline

To follow how modern C++ arrived at its current customization landscape, it helps to keep the timeline in view:

```text
2015   N4381 — Customization Point Objects formalized (Niebler)
   ↓
2019   P1895R0 — tag_invoke proposed (Baker, Niebler, Shoop)
   ↓
2020   Barry Revzin — "Why tag_invoke is not the solution I want"
   ↓
2020   Boost 1.75 — Boost.JSON adopts tag_invoke for conversions
   ↓
2021   P2279R0 — "We need a language mechanism for customization points" (Revzin)
   ↓
2021–23 P2300 — tag_invoke used extensively across early Sender/Receiver (libunifex)
   ↓
2024   P2300R9/R10 — std::execution replaces tag_invoke with member customization + domain dispatch
   ↓
2026   C++26 standard finalized — std::execution standardized as the core asynchronous framework
```

---

## When Is `tag_invoke` a Good Fit?

If you are evaluating customization strategies for your own libraries or application architectures, here is a practical decision guide:

### Prefer `tag_invoke` when:
- Your ecosystem or library already uses it (e.g., writing custom serializers for Boost.JSON).
- You need generic wrappers or adapters that forward unknown customization points to wrapped objects.
- You need a uniform, non-intrusive customization protocol across a large set of operations.
- You want operation identity encoded in a type rather than risking collisions across shared ADL function names.
- You are implementing a type-erased facility around a known set of CPO tags.

### Prefer another mechanism when:
- A named member function (`obj.operation()`) is sufficient and you control or can constrain the participating types.
- The interface should be highly visible and self-documenting in class definitions.
- You want straightforward, localized compiler diagnostics without deep template instantiation cascades.
- There are only one or two simple customization points.
- Your ecosystem does not otherwise use `tag_invoke`.

---

## The Customization Problem & Barry's Criteria

In his 2020 analysis, Barry Revzin laid out six criteria for what constitutes a proper customization mechanism:

1. **Clear interface definition**: You can look at code and immediately see what operations can or must be customized, along with expected signatures and semantics.
2. **Overridable default implementations**: A library can supply a sensible fallback that types can selectively override for efficiency.
3. **Explicit opt-in**: Types intentionally declare that they satisfy the interface rather than accidentally matching loose signatures.
4. **Early failure on incorrect opt-in**: If a type tries to implement an interface with the wrong signature, the compiler rejects it at the point of definition, not miles away at a call site.
5. **Safe and intuitive invocation**: Calling the customized function is simple, and callers cannot accidentally bypass user customizations.
6. **Programmatic interface verification**: Generic code can easily check whether a type satisfies the customization requirements (e.g., via a Concept).

*(Note: While Barry's initial 2020 post framed the discussion around these six points, his subsequent paper [P2279R0](https://wg21.link/p2279) expanded the analysis to additional architectural dimensions, including atomic grouping of operations, associated types, non-intrusive customization, and generic forwarding.)*

In C++, **virtual member functions** satisfy all six criteria cleanly:

```cpp
struct Printable {
    virtual void print() const = 0;              // 1. Clear interface
    virtual void describe() const { print(); }   // 2. Overridable default
};

struct Widget : Printable {
    void print() const override;                 // 3. Explicit opt-in
    // void print(int) override;                 // 4. Compile error at definition!
};
```

Calling `ptr->describe()` dispatches cleanly (Criterion 5), and checking `std::derived_from<T, Printable>` verifies it (Criterion 6).

However, virtual functions are unsuitable for generic programming:

- **Intrusive**: You cannot add a virtual member function to `int`, `std::string`, or a type defined in a third-party library without wrapping it in an adapter.
- **Runtime overhead**: Virtual dispatch introduces an indirect call through a vtable and may inhibit compiler inlining unless the dynamic type can be devirtualized. Polymorphic objects also carry a vptr. (Importantly, virtual dispatch does *not* inherently require heap allocation—polymorphic objects can live on the stack or in static storage—but the indirection remains).
- **Incompatible with generic value semantics**: Virtual methods cannot be function templates, nor can they easily return varying, dependent types tailored to each concrete implementation.

Hence the quest for static customization.

---

## Three Generations of Static Customization

### Generation 1: Class Template Specialization (`std::hash<T>`)

The oldest static technique requires users to specialize a class template owned by the library:

```cpp
namespace std {
    template <>
    struct hash<MyType> {
        size_t operator()(const MyType& x) const noexcept {
            return std::hash<int>{}(x.id);
        }
    };
}
```

This provides explicit opt-in and prevents accidental signature matches. However:
- The customization has to be expressed through a library-owned class template specialization, which makes conditional and composable customization awkward.
- Function-template specializations are not a substitute for overload-based customization because they do not participate in overload resolution in the same way.

### Generation 2: Raw ADL & The "Two-Step Dance" (`swap`)

The classic C++98/11 idiom for customizable algorithms relied on Argument-Dependent Lookup (ADL):

```cpp
template <typename T>
void process(T& a, T& b) {
    // The infamous two-step dance:
    using std::swap;
    swap(a, b); // Finds custom swap via ADL if present, otherwise std::swap
}
```

Types customize `swap` by providing a non-member function in their own namespace (typically as a hidden friend):

```cpp
struct Buffer {
    friend void swap(Buffer& a, Buffer& b) noexcept {
        // optimized pointer swap...
    }
};
```

This is non-intrusive and supports fallbacks, but introduces two notable failure modes:

1. **The "Forgot the `using`" Bug**: Writing `std::swap(a, b)` instead of `using std::swap; swap(a, b);` silently bypasses the user's custom implementation, invoking the generic copy/move fallback.
2. **The ADL Namespace Problem**: ADL searches all namespaces associated with a function's arguments. When multiple independent libraries pick the same common function name—such as `size(x)`—a call on a type that brings both namespaces into scope can result in ambiguous overloads or silent dispatch to an unintended function.

### Generation 3: ADL-based Customization Point Objects (N4381 / Ranges)

In [N4381: Suggested Design for Customization Points](https://wg21.link/n4381), Eric Niebler formalized Customization Point Objects (CPOs), which were standardized in C++20 Ranges (`std::ranges::begin`, `std::ranges::swap`).

A CPO is an ordinary function-object value placed in a specific namespace. Callers invoke the object directly:

```cpp
std::ranges::swap(a, b);
auto it = std::ranges::begin(container);
```

**The caller no longer performs ADL directly.** The CPO owns the dispatch policy, encapsulating internal ADL lookups, member-function checks, and default fallbacks:

```cpp
namespace mylib {
    namespace _detail {
        void foo() = delete; // Poison pill to avoid finding enclosing foo()

        struct foo_fn {
            template <typename T>
                requires requires(T&& x) { foo(std::forward<T>(x)); }
            constexpr auto operator()(T&& x) const
                noexcept(noexcept(foo(std::forward<T>(x))))
                -> decltype(foo(std::forward<T>(x))) {
                return foo(std::forward<T>(x));
            }
        };
    }

    inline namespace _cpos {
        inline constexpr _detail::foo_fn foo{};
    }
}
```

Because the CPO is a first-class function-object value, it can be stored, passed to other algorithms, and composed without losing customization behavior.

#### What ADL-based CPOs Still Struggle With

While CPOs solved the call-site invocation problem, ADL-based CPO conventions still face two architectural friction points:

1. **The ADL Namespace Problem**: An ADL-based CPO convention typically requires a corresponding ADL customization name (e.g., `std::ranges::begin` dispatches to an unqualified ADL `begin(x)`). If every library creates CPOs for dozens of domain algorithms, independent libraries still risk claiming and colliding on the same ADL identifiers.
2. **The Generic Wrapper Problem**: A wrapper cannot generically forward arbitrary ADL customization points because C++ has no mechanism for saying *"for any future function name found by ADL, forward the call to the wrapped object."*

---

## The `tag_invoke` Protocol (P1895R0)

In [P1895R0](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1895r0.pdf), Lewis Baker, Eric Niebler, and Kirk Shoop proposed a uniform protocol:

> Reserve **exactly ONE** global ADL customization name: `tag_invoke`. To specify which operation is being performed, **pass the CPO itself as the first argument (the tag)**.

```text
[Caller: mylib::foo(x)]
         │
         ▼
[CPO: foo_fn::operator()(x)]
         │
         ▼
[tag_invoke(*this, x)] ──(ADL Dispatch)────────┐
                                                ▼
                         ┌──────────────────────────────────────────┐
                         │ tag_invoke(tag_t<foo>, MyType) defined?  │
                         └──────────────────┬───────────────────────┘
                                            │
                           ┌────────────────┴────────────────┐
                           ▼ YES                             ▼ NO
               [Custom Hidden Friend]             [Default Fallback in CPO]
```

### Encoding Operations in Tag Types

Instead of dispatching to an ADL `foo(x)` or `bar(x)`, the CPO dispatches to `tag_invoke(foo, x)` or `tag_invoke(bar, x)`.

Because the operation identity is encoded in the first argument's type, collision risks between independent libraries are greatly reduced:

```cpp
namespace geom {
    struct area_fn { /* ... */ };
    inline constexpr area_fn area{};
}

namespace screen {
    struct area_fn { /* ... */ };
    inline constexpr area_fn area{};
}

class ScreenWindow {
    // Customization for geom::area (tag is geom::area_fn)
    friend double tag_invoke(geom::area_fn, const ScreenWindow& w) {
        return w.physical_width * w.physical_height;
    }

    // Customization for screen::area (tag is screen::area_fn)
    friend int tag_invoke(screen::area_fn, const ScreenWindow& w) {
        return w.pixel_width * w.pixel_height;
    }
};
```

Even though both operations conceptually represent "area", their tag types (`geom::area_fn` and `screen::area_fn`) are distinct C++ types. Both customizations live side-by-side as hidden friends without ambiguity.

`tag_invoke` is still an ADL customization mechanism—it does not eliminate all ADL-related complexity—but it channels lookups through a single identifier differentiated by the tag type.

---

## A Pedagogical `tag_invoke` Dispatcher

Let's build a deliberately simplified `tag_invoke` dispatcher for exposition. Production implementations (such as in `libunifex`, `stdexec`, or Boost) add substantial machinery for return type deduction, noexcept propagation, constraint checking, and error diagnostics.

```cpp
#include <concepts>
#include <type_traits>
#include <utility>

namespace core {

namespace _tag_invoke_detail {
    // Poison pill declaration to ensure ADL occurs cleanly
    void tag_invoke();

    struct _fn {
        template <typename Tag, typename... Args>
            requires requires(Tag&& tag, Args&&... args) {
                tag_invoke(std::forward<Tag>(tag), std::forward<Args>(args)...);
            }
        constexpr decltype(auto) operator()(Tag&& tag, Args&&... args) const
            noexcept(noexcept(tag_invoke(std::forward<Tag>(tag), std::forward<Args>(args)...))) {
            return tag_invoke(std::forward<Tag>(tag), std::forward<Args>(args)...);
        }
    };
}

// The caller-facing dispatcher object
inline namespace _cpos {
    inline constexpr _tag_invoke_detail::_fn tag_invoke{};
}

// Convenience helper to extract the tag type from a CPO variable reference
template <auto& Tag>
using tag_t = std::decay_t<decltype(Tag)>;

// Concepts checking whether a tag can be invoked with given arguments
template <typename Tag, typename... Args>
concept tag_invocable = std::invocable<decltype(tag_invoke), Tag, Args...>;

template <typename Tag, typename... Args>
concept nothrow_tag_invocable =
    tag_invocable<Tag, Args...> &&
    std::is_nothrow_invocable_v<decltype(tag_invoke), Tag, Args...>;

template <typename Tag, typename... Args>
using tag_invoke_result_t = std::invoke_result_t<decltype(tag_invoke), Tag, Args...>;

} // namespace core
```

### Defining a CPO with `tag_invoke`

Writing a CPO in a `tag_invoke`-based ecosystem becomes straightforward:

```cpp
namespace graphics {

inline constexpr struct draw_fn {
    template <typename T>
        requires core::tag_invocable<draw_fn, const T&>
    void operator()(const T& item) const
        noexcept(core::nothrow_tag_invocable<draw_fn, const T&>) {
        core::tag_invoke(*this, item);
    }
} draw{};

} // namespace graphics
```

And user types customize it via a hidden friend:

```cpp
#include <iostream>

struct Circle {
    double radius;

    friend void tag_invoke(core::tag_t<graphics::draw>, const Circle& c) noexcept {
        std::cout << "Drawing a circle with radius " << c.radius << "\n";
    }
};

int main() {
    Circle c{4.5};
    graphics::draw(c); // Prints: Drawing a circle with radius 4.5
}
```

---

## The Killer Feature: Generic Forwarding Through Wrappers

This is the central architectural reason `tag_invoke` gained widespread attention.

Consider an adapter or decorator type—a logging wrapper, a thread-safe synchronized adapter, or a mock wrapper. You want the wrapper to forward customizations to the underlying object:

```cpp
template <typename T>
struct logged {
    T value;
};
```

In an ADL-based CPO world, the wrapper cannot forward unknown operations because C++ has no syntax for: *"for any future function name found by ADL, forward to `value`"*. The wrapper author must manually write a forwarding friend for every single CPO by name.

Because all CPOs in a `tag_invoke`-based ecosystem share the single customization function name `tag_invoke`, the wrapper needs **exactly one templated friend function**:

```cpp
template <typename T>
struct logged {
    T value;

    template <typename Tag, typename... Args>
        requires requires(Tag tag, const T& val, Args&&... args) {
            tag(val, std::forward<Args>(args)...);
        }
    friend decltype(auto) tag_invoke(Tag tag, const logged& w, Args&&... args) {
        std::cout << "[LOG] Intercepted CPO call!\n";
        return tag(w.value, std::forward<Args>(args)...);
    }
};
```

Testing this with our `Circle` and `graphics::draw`:

```cpp
int main() {
    logged<Circle> monitored{Circle{10.0}};

    // graphics::draw does not know about logged<Circle>.
    // logged<Circle> does not hardcode graphics::draw.
    // Yet forwarding works naturally:
    graphics::draw(monitored);
}
```

**Output:**
```text
[LOG] Intercepted CPO call!
Drawing a circle with radius 10
```

### The Caveat: Generic Forwarding Can Be Dangerous

While generic forwarding is powerful, it grants the wrapper broad authority over the customization surface:

1. **CV/Ref Qualification**: The simplified example above takes `const logged&` and forwards to `const T&`. A truly transparent wrapper must preserve the value category and constness (`logged&`, `const logged&`, `logged&&`, `const logged&&`), forwarding mutable and move-only operations correctly.
2. **Greedy Overloads**: A catch-all `tag_invoke` overload is easily matched. If it is not constrained carefully, it can accidentally intercept operations intended specifically for the wrapper itself, introduce unintended recursion, alter exception guarantees (`noexcept`), or silently skew overload resolution.

As Barry Revzin discussed in [P2547R1](https://wg21.link/p2547), generic forwarding is one of `tag_invoke`'s greatest architectural strengths, but it requires rigorous constraints to avoid hijacking operations.

---

## Real-World Adoption: Boost.JSON

[Boost.JSON](https://www.boost.org/doc/libs/1_86_0/libs/json/doc/html/json/conversion.html) (introduced in Boost 1.75) is one of the most prominent production examples of the `tag_invoke` pattern.

Importantly, Boost.JSON uses `tag_invoke` as its customization protocol without requiring `value_from` and `value_to` themselves to be CPO objects. Boost.JSON documents `value_from` and `value_to` as **function templates** whose customization is performed through ADL-discovered `tag_invoke` overloads.

Boost.JSON defines two primary tags in `boost/json/conversion.hpp`:
- `boost::json::value_from_tag`
- `boost::json::value_to_tag<T>`

The `value_to_tag<T>` tag is especially clever: **the target type `T` is encoded as a template parameter of the tag type itself**. This ensures that the user's namespace is automatically included in the associated namespaces for ADL lookup, even when converting from a standard JSON container.

### Practical Boost.JSON Walkthrough

```cpp
#include <boost/json.hpp>
#include <iostream>
#include <string>

struct User {
    int id;
    std::string name;

    // 1. Serialize: User -> boost::json::value
    friend void tag_invoke(boost::json::value_from_tag, boost::json::value& jv, const User& u) {
        jv = {
            {"id", u.id},
            {"name", u.name}
        };
    }

    // 2. Deserialize: boost::json::value -> User
    friend User tag_invoke(boost::json::value_to_tag<User>, const boost::json::value& jv) {
        const auto& obj = jv.as_object();
        return User{
            boost::json::value_to<int>(obj.at("id")),
            boost::json::value_to<std::string>(obj.at("name"))
        };
    }
};

int main() {
    User alice{42, "Alice"};

    // Value -> JSON
    boost::json::value jv = boost::json::value_from(alice);
    std::cout << "Serialized: " << boost::json::serialize(jv) << "\n";

    // JSON -> Value
    User restored = boost::json::value_to<User>(jv);
    std::cout << "Restored: " << restored.id << ", " << restored.name << "\n";
}
```

Notice the engineering benefits:
- The customization functions are hidden friends inside `User`, so they do not pollute the enclosing namespace.
- The user never reopens `namespace boost::json`.
- The user-facing API functions `value_from` and `value_to` provide a clean, type-safe entry point.

---

## Sender/Receiver: Why `tag_invoke` Was Attractive—and Why P2300 Moved Away

Historically, the primary driver for `tag_invoke` was the Sender/Receiver model for asynchronous execution, developed in Meta's [`libunifex`](https://github.com/facebookexperimental/libunifex) and early revisions of [P2300](https://wg21.link/p2300).

An asynchronous runtime involves two layers of operations:
1. **Basis operations**: Primitives that execution contexts must implement (`schedule`, `connect`, `start`, `set_value`, `set_error`, `set_stopped`).
2. **Customizable algorithms**: Generic algorithms with default implementations that can be overridden for specific execution domains (such as `sync_wait`, `then`, or `transfer`).

### The Original Appeal

Early Sender/Receiver designs used `tag_invoke` universally. It solved the namespace pollution problem and allowed platform authors to specialize algorithms:

```cpp
// Illustrative concept in early Sender/Receiver:
friend auto tag_invoke(sync_wait_tag, const cuda_sender& s) {
    // Specialized synchronization tailored to a GPU stream rather than
    // blocking the host thread with a generic mutex/condition_variable
}
```

The tag type also made it possible for a type-erased wrapper to define a vtable for a selected set of CPO tags and implement each entry by invoking the corresponding customization. P2300-era papers explicitly explored this technique for type-erasing senders and receivers.

### The Retreat: Why P2300 Replaced `tag_invoke`

Despite these benefits, practical experience with `tag_invoke` at scale exposed serious pain points:
- **Inscrutable Diagnostics**: When a `tag_invoke` overload fails a concept constraint, compilers emit multi-page template instantiation cascades rather than pinpointing what signature was expected.
- **Overload-Set Bloat**: Every customized operation sharing the single name `tag_invoke` meant that in massive codebases, ADL candidate sets became large, slowing down compilation.
- **Interface Obscurity**: Reading a class definition gave no clear indication of what interface was being fulfilled.

As explicitly documented in [P2300R10](https://wg21.link/p2300), the authors replaced `tag_invoke` with an explicit, multi-tiered customization model:

1. **Receiver and Completion Customizations Moved to Named Members**:
   - `schedule(sch)` → dispatches to member `sch.schedule()`
   - `set_value(rcvr, ...)` → dispatches to member `rcvr.set_value(...)`
   - `set_error(rcvr, ...)` → dispatches to member `rcvr.set_error(...)`
   - `set_stopped(rcvr)` → dispatches to member `rcvr.set_stopped()`
2. **Execution-Domain Dispatch for Algorithms**:
   Sender algorithms like `sync_wait` and `then` now customize via an explicit execution-domain mechanism using `get_domain`, `get_completion_domain`, and `apply_sender`.
3. **Query Customization via Environments**:
   Environment queries use `get_env(obj)` returning queryable environment objects.

This architectural shift is telling:

```text
Raw ADL ──> CPOs ──> tag_invoke ──> Named Member Customization + Domain Dispatch
```

The evolution was not simply "standardizing `tag_invoke`." It was realizing that different customization points have different requirements, and completion operations benefit from explicit member syntax.

---

## Barry Revzin's Critique: `tag_invoke` Is Not a Trait System

In December 2020, Barry Revzin published [Why tag_invoke is not the solution I want](https://brevzin.github.io/c++/2020/12/01/tag-invoke/), followed by [P2279R0: We need a language mechanism for customization points](https://wg21.link/p2279).

Barry framed the central question:

> `tag_invoke` answers: *"How can libraries build a unified, non-intrusive customization mechanism using existing language rules?"*
>
> Barry asks: *"Why should users have to construct this machinery in a library when the language could understand customization interfaces directly?"*

### 1. Inscrutable Interface Definitions

With language-level traits (such as Rust's `PartialEq`), an interface with a mandatory function and an overridable default is concise:

```rust
trait PartialEq {
    fn eq(&self, rhs: &Self) -> bool;
    fn ne(&self, rhs: &Self) -> bool {
        !self.eq(rhs)
    }
}
```

With `tag_invoke`, expressing that same two-function interface requires dozens of lines of template metaprogramming, nested `requires requires` clauses, SFINAE fallbacks, and tag-dispatch helper structs. For an application programmer reading the library header, the actual contractual interface is buried under implementation machinery.

### 2. Lack of Explicit Interface Declarations & Deferred Errors

In a language with native traits (or with `virtual ... override`), a type explicitly states which interface it implements. If the signature is slightly off, the compiler halts immediately at the type definition:

```cpp
struct D : B {
    void f(unsigned int) override; // Compile error at definition!
};
```

In `tag_invoke`:

```cpp
struct Widget {
    int id;

    // Subtle slip: takes Widget& instead of const Widget&
    friend bool tag_invoke(eq_tag, Widget& a, Widget& b) {
        return a.id == b.id;
    }
};
```

This hidden friend does not declare that it is satisfying `eq`. It merely declares an overload that might be found by future ADL lookups. If someone later calls `eq(const_widget1, const_widget2)`, the overload is quietly ignored:
- If a default fallback exists, the compiler silently calls it (possibly producing incorrect runtime results).
- If no fallback exists, the compiler emits a deep template-instantiation error stating that `Widget` does not satisfy `tag_invocable`.

### What `tag_invoke` Deliberately Does Not Solve

It is also worth making clear what `tag_invoke` is not designed to address:

- **Member operator synthesis**: It does not synthesize `operator++`, `operator*`, or `operator[]`.
- **Associated types and typedefs**: It does not define member types like `iterator_category` or `value_type`.
- **Structural interface declarations**: It does not declare class layouts or interface contracts.

For synthesizing class interfaces and operators (such as writing an iterator from minimal primitives), developers still use mixin techniques, CRTP, or C++23 explicit object parameters (`deducing this`).

---

## Compile-Time Cost of Customization: Why ADL Matters

Runtime performance is rarely the only consideration in large C++ projects; compile time is often just as critical.

ADL-based customization has direct compile-time consequences:
1. **Associated Namespace Traversal**: Every ADL lookup must examine every namespace associated with every argument type, including enclosing namespaces, base classes, and template arguments.
2. **Overload-Set Size**: When all customizations share the single identifier `tag_invoke`, every participating type that is reachable contributes candidate overloads to the ADL overload set. The compiler must evaluate SFINAE constraints or concept `requires` clauses on every candidate to determine the best match.
3. **Template Instantiation Depth**: Constraining CPOs with `std::tag_invocable` triggers nested concept evaluations that increase memory consumption and compiler throughput times in translation units with heavy generic code.

Part of the motivation in P2300's shift to named member functions (`sch.schedule()`, `rcvr.set_value(...)`) was to make lookup direct, localized, and fast to compile, bypassing ADL candidate set construction entirely for hot completion paths.

---

## Why This Matters in Embedded C++

For embedded systems and bare-metal programming, customization mechanisms are scrutinized under specific constraints:

1. **Zero Runtime Overhead**: Like CPOs, `tag_invoke` resolves entirely at compile time. Overloads inline aggressively, with no vtable indirection and no heap allocation.
2. **Exception Safety & `noexcept`**: Embedded environments frequently compile with `-fno-exceptions`. A well-designed `tag_invoke` dispatcher enforces `nothrow_tag_invocable`, guaranteeing that customization overloads do not introduce throwing paths.
3. **Adapting Vendor Drivers & HALs Without Modification**:
   In embedded projects, you frequently deal with vendor-provided Hardware Abstraction Layers (HALs) that you cannot modify. With `tag_invoke`, you can customize higher-level protocols for vendor structs non-intrusively:

```cpp
// Vendor HAL type (unmodified)
namespace vendor_hal {
    struct stm32_spi_bus { /* hardware registers... */ };
}

// Our application customization
namespace embedded {
    inline constexpr struct transfer_fn {
        template <typename Device, typename Buffer>
            requires core::tag_invocable<transfer_fn, Device&, Buffer&>
        void operator()(Device& dev, Buffer& buf) const noexcept {
            core::tag_invoke(*this, dev, buf);
        }
    } transfer{};
}

// Customize vendor_hal::stm32_spi_bus for embedded::transfer
// without touching vendor headers!
namespace vendor_hal {
    inline void tag_invoke(core::tag_t<embedded::transfer>,
                           stm32_spi_bus& bus,
                           std::span<uint8_t>& data) noexcept {
        // low-level register writes...
    }
}
```

Now, generic decorators like `dma_device<T>`, `logged_device<T>`, or `mock_device<T>` can forward `embedded::transfer` generically across different MCU targets.

---

## Comparison Matrix

| Feature | Raw ADL (`swap`) | ADL-based CPO (Ranges) | `tag_invoke` Protocol |
|---|---|---|---|
| **Call syntax** | Unqualified + `using` | Qualified (`ranges::swap`) | Qualified (`lib::foo`) |
| **Caller controls dispatch** | Easily bypassed (forgotten `using`) | CPO controls it | CPO controls it |
| **Passable as function object** | No | Yes | Yes |
| **Operation-specific dispatch** | Via function name | Via function name / CPO | Via tag type |
| **Name collision risk** | Possible and potentially serious | Possible (ADL name shared) | Greatly reduced (encoded in tag) |
| **Generic wrapper forwarding** | Very difficult | Very difficult | Natural (single catch-all overload) |
| **Definition-time interface checking** | No | Usually no | No |

---

## Summary and Key Takeaways

1. **CPO ≠ `tag_invoke`**: A Customization Point Object is a caller-facing function object that encapsulates dispatch policy; `tag_invoke` is a tag-dispatch customization protocol.
2. **CPOs Fix Invocation**: By moving the dispatch decision from the call site into a library-owned object, CPOs eliminate the fragile two-step ADL dance.
3. **`tag_invoke`'s Core Strength Is Generic Forwarding**: By routing customizations through a single ADL name differentiated by tag type, wrappers can forward arbitrary CPOs without hardcoding their names.
4. **Boost.JSON Proves Its Value for Conversions**: Boost.JSON demonstrates that `tag_invoke` is a proven, highly effective pattern for decoupled domain conversions where types should not depend on JSON headers.
5. **The Lesson of P2300**: `tag_invoke` was not a failed idea—it solved real problems that earlier CPOs handled poorly. Its retreat from P2300 was a pragmatic recognition that completion operations benefit from explicit member syntax, cleaner diagnostics, and faster compile times, while complex algorithms benefit from domain-based dispatch.

Until C++ gains native language support for customization points, `tag_invoke` remains one of the most clever, powerful, and architecturally instructive patterns in modern C++ generic library design.

---

### References & Further Reading

- [P1895R0: tag_invoke — A general pattern for supporting customisable functions](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1895r0.pdf) — Lewis Baker, Eric Niebler, Kirk Shoop (2019)
- [Why tag_invoke is not the solution I want](https://brevzin.github.io/c++/2020/12/01/tag-invoke/) — Barry Revzin (2020)
- [N4381: Suggested Design for Customization Points](https://wg21.link/n4381) — Eric Niebler (2015)
- [P2279R0: We need a language mechanism for customization points](https://wg21.link/p2279) — Barry Revzin (2021)
- [P2547R1: Language Support for Customisable Functions](https://wg21.link/p2547) — Barry Revzin (2022)
- [P1292R0: Customization Point Functions](https://wg21.link/p1292) — Matt Calabrese (2018)
- [P2300R10: std::execution](https://wg21.link/p2300) — Michal Dominiak, Lewis Baker, Lee Howes, Eric Niebler, Kirk Shoop, et al. (2024)
- [Boost.JSON Value Conversion & Custom Conversions Documentation](https://www.boost.org/doc/libs/1_86_0/libs/json/doc/html/json/conversion/custom_conversions.html) — Vinnie Falco, Kary Pardy
- [Boost.JSON GitHub Repository](https://github.com/boostorg/json)

---
license: CC BY 4.0
