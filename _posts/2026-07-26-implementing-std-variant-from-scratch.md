---
title: "Implementing std::variant from scratch"
description: A step-by-step journey through building your own std::variant, then peeking under the hood of libstdc++ and libc++ to see how the real thing works.
date: 2026-07-26 10:00:00 +0200
tags:
  - c++
  - variant
  - template-metaprogramming
  - stl
---

I have used `std::variant` in production code. I have read cppreference pages about it. I have even debugged a `std::bad_variant_access` or two. But there is a difference between *using* something and *understanding* it.

So I decided to build one.

Not a complete one. Not a safe one. Just enough to hit every interesting problem along the way and come out the other side knowing what the real implementation is actually doing. This is that journey.

---

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

* TOC
{:toc}
</nav>

## Step 1: Just declare it

The simplest possible starting point. I want this to compile:

```cpp
MyVariant<int, double> v;
```

That is it. No assignment, no getters, just the template declaration and some storage. Here is everything we need:

```cpp
#include <algorithm>
#include <type_traits>

template <typename... T>
struct MyVariant {
    static constexpr auto storage_size = std::max({sizeof(T)...});

    alignas(storage_size) char storage[storage_size];
};
```

And that compiles. `MyVariant<int, double> v;` creates an object with 8 bytes of storage (the size of a `double`, which is the larger of the two), properly aligned.

Let us break down what just happened:

- `typename... T` is a **variadic template parameter pack**. It accepts zero or more type arguments.
- `sizeof(T)...` is a **pack expansion**. It expands to `sizeof(int), sizeof(double)`, i.e. `4, 8`.
- `std::max({4, 8})` gives us `8`.
- `alignas(storage_size)` ensures the storage is aligned to at least 8 bytes, so we can later reinterpret it as any of the alternatives.

At this point, `v` is just a bag of bytes. We have no idea what it holds, and it holds nothing meaningful. But the foundation is there. The storage is big enough for any alternative, and it is properly aligned.

This is the ugly truth about `std::variant` at its core: it is a `char` array with a type system layered on top.

## Step 2: Assign a value (but not safely)

Now I want `v = 42;` and `v = 3.8;` to work. The idea is simple: write a templated constructor and assignment operator that take any type `U`, and copy the bytes into storage.

```cpp
template <typename... T>
struct MyVariant {
    static constexpr auto storage_size = std::max({sizeof(T)...});

    template <typename U>
    MyVariant(U u) {
        inplace(&u, sizeof(u));
    }

    template <typename U>
    MyVariant& operator=(U u) {
        inplace(&u, sizeof(u));
        return *this;
    }

    alignas(storage_size) char storage[storage_size];

private:
    void inplace(void* p, size_t sz) {
        std::memcpy(storage, p, sz);
    }
};
```

Now this works:

```cpp
MyVariant<int, double> v = 42;   // stores int 42
v = 3.8;                         // stores double 3.8
```

The `memcpy` is doing all the heavy lifting. We take the address of the incoming value, treat it as raw bytes, and overwrite whatever was in storage before. No type tracking. No destruction of the previous value. Just raw bytes in, raw bytes out.

This is, of course, horrifying. If you store a `double` and then store an `int`, the first 4 bytes of the `double` are overwritten with the `int` value, and the remaining 4 bytes of the old `double` are still sitting there. But for POD types of the same or smaller size, the `memcpy` completely overwrites the previous content, so it happens to work.

The important thing is the *pattern*: a templated constructor and assignment operator that accept any type `U`, do type-erased work, and leave the actual type information implicit. That is exactly how the real `std::variant` works — except it tracks which type is active and does not use `memcpy`.

Notice one more thing: `U u` in the constructor takes the value **by value**. For small types like `int` and `double` this is fine. For larger types you would want `const U&` or `U&&`, but let us not get ahead of ourselves. We are building a toy, and the toy works.

## Step 3: The getter — and why we need `NthType`

Now I want `v.get<0>()` to return the `int` and `v.get<1>()` to return the `double`. The problem is immediately obvious: given `N`, how do we get the Nth type from the parameter pack `T...`?

We need a helper. This is where template metaprogramming enters the picture.

```cpp
template <size_t N, typename... T>
struct NthType;
```

This is a recursive type trait. The base case handles `N = 0`:

```cpp
template <typename Head, typename... Tail>
struct NthType<0, Head, Tail...> {
    using type = Head;
};
```

When `N` is 0, the answer is simply `Head` — the first type in the pack. The `type` alias is the result.

The recursive case peels off one type and decrements `N`:

```cpp
template <size_t N, typename Head, typename... Tail>
struct NthType<N, Head, Tail...> {
    using type = typename NthType<N - 1, Tail...>::type;
};
```

So `NthType<1, int, double>::type` becomes `NthType<0, double>::type`, which is `double`. The recursion bottoms out at the base case.

Now the getter writes itself:

```cpp
template <size_t N>
constexpr auto get() {
    return *(typename NthType<N, T...>::type*)(storage);
}
```

We cast `storage` (a `char*`) to a pointer of the Nth type, dereference it, and return the value. The `NthType` resolves at compile time — the compiler generates a `static_cast` to the correct type. No runtime overhead at all.

```cpp
MyVariant<int, double> v = 42;
v = 3.8;

std::cout << v.get<0>() << std::endl;  // 3.8 (the double, NOT the int!)
std::cout << v.get<1>() << std::endl;  // 3.8
```

Wait. What?

`v.get<0>()` prints `3.8` and so does `v.get<1>()`. That is because we have no idea which type is active. After `v = 3.8`, the storage contains a `double`. `get<0>()` casts the storage to `int*` and reads 8 bytes through a 4-byte type — undefined behavior. `get<1>()` casts to `double*` and reads the actual value correctly.

Both compile. Both run. One of them is UB. And we have no way to tell which one is which at runtime because **we never tracked the active type**.

This is the fundamental gap. Our toy variant is missing an index.

## Step 4: What our toy variant is missing

Let us be honest about the gap between our 40-line implementation and the real `std::variant`. Here is what we are missing:

1. **Type index tracking.** The real variant stores an `index()` telling you which alternative is active. Without it, every `get<>` is a coin flip between correct behavior and undefined behavior.

2. **Destruction.** If a variant holds a `std::string` and you assign an `int` to it, the `std::string` needs to be destroyed. Our `memcpy`-based assignment just overwrites the bytes. For non-trivial types, that is a resource leak at best and a use-after-free at worst.

3. **Copy and move semantics.** Copy-constructing a variant that holds a `std::string` needs to copy-construct the `std::string`. Our copy constructor would just `memcpy` the string's internal pointers.

4. **Exception safety (`valueless_by_exception`).** If assigning type B to a variant that holds type A throws during construction, the variant enters a "valueless" state. The real `std::variant` tracks this with `valueless_by_exception()`. Our variant would just leave garbage in storage.

5. **`std::visit`.** The visitor pattern for type-safe dispatch over all alternatives. This is how you actually use a variant in practice — not with `get<>()`, but with a visitor callable.

6. **Trivial special member function propagation.** If all alternatives are trivially copyable, the variant itself should be trivially copyable. This matters for ABI, performance, and `constexpr` support.

Our toy hits exactly one of these: it has storage. That is a start, but only a start.

## Step 5: What real `std::variant` does — the design

The C++17 standard defines `std::variant` as a **discriminated union**. The key invariants:

- It holds **exactly one** value of one of its alternative types at all times (except after a failed assignment, when it is *valueless*).
- It knows **which** alternative is active via `index()`.
- It supports **type-safe access** via `std::get<T>()` or `std::get<N>()`, throwing `std::bad_variant_access` on mismatch.
- It supports **visitation** via `std::visit`, which calls a visitor with a reference to the active alternative.

The assignment from Step 2, `v = 3.8`, in the real variant does roughly:

1. If the variant already holds a `double`, assign to it in place (no destruction/reconstruction needed).
2. If the variant holds something else, destroy the current value, construct a `double` in the storage, and update the index.
3. If the construction throws, the variant becomes `valueless_by_exception()`.

That conditional destruction/reconstruction is the core complexity. Everything else — `visit`, `get`, `holds_alternative` — is bookkeeping.

## Step 6: Compile time vs runtime

This is where `std::variant` gets interesting from an engineering perspective. There is a clean split between what the compiler figures out and what happens at runtime.

### Compile time

**Type resolution.** `NthType`, `std::tuple_element`, `std::holds_alternative` — these are all pure compile-time type computations. The compiler resolves them during template instantiation. Zero runtime cost.

**Storage layout.** `sizeof(std::variant<int, double>)`, `alignof(std::variant<int, double>)`, which alternative fits where — all computed at compile time. The variant's size is `max(sizeof(T)...)` plus the index storage plus any padding. All known before any code runs.

**Trivial special member function detection.** Is the variant trivially copyable? Trivially destructible? The implementation checks each alternative with `std::is_trivially_copyable_v<T>` and `std::is_trivially_destructible_v<T>` using fold expressions. If all alternatives satisfy the trait, the variant inherits the trivial special member. This determines whether the compiler can use `memcpy` for copies or must generate actual copy constructors. All resolved at compile time.

**Visitation table generation.** This is the most interesting one. The real implementations build a `constexpr` array of function pointers at compile time — essentially a vtable for visitation. For `std::variant<A, B, C>` visited with a visitor `F`, the table maps each `(index, index, ...)` combination to a function that extracts the correct alternatives and calls the visitor. The table is generated during template instantiation and stored as a `static constexpr` member. The compiler emits it into the binary at compile time.

**Switch optimization.** When visiting a single variant with a small number of alternatives (libstdc++ uses ≤11 as the threshold), the visitation can be replaced by a `switch` statement instead of a table lookup. The compiler can then optimize the switch into a jump table, a series of branches, or whatever it deems best. The decision of "switch vs table" is made at compile time.

### Runtime

**Index storage and comparison.** The active index is stored as a member variable (typically `unsigned char`, `unsigned short`, or `unsigned int` depending on the number of alternatives). Reading and comparing it happens at runtime.

**Construction and destruction.** When you assign a new value, the variant must potentially destroy the old value and construct the new one. For non-trivial types, this involves placement `new` and explicit destructor calls. These are runtime operations.

**Visitation dispatch.** Once the table is built at compile time, the actual dispatch reads the index at runtime and calls through the function pointer. For the switch optimization, the index is read and used as the switch operand.

**Exception safety.** The `valueless_by_exception()` state and the rollback logic for failed assignments are pure runtime concerns.

The general pattern: the variant's *shape* is determined at compile time, and its *behavior* on any given operation is determined at runtime by the stored index.

## Step 7: How libstdc++ and libc++ actually do it

I spent some time reading the actual source code of both major implementations. They take meaningfully different engineering approaches to the same problem.

### Storage

**libstdc++ (GCC)** uses a recursive variadic union called `_Variadic_union`. Each level wraps one alternative:

```
_Variadic_union<A, B, C>
  = { _Uninitialized<A> _M_first; _Variadic_union<B, C> _M_rest; }
```

Before C++20, the `_Uninitialized` wrapper for non-trivially-destructible types does not use a union member at all — it uses `__gnu_cxx::__aligned_membuf`, an opaque aligned memory buffer. Construction is done with placement `new`. This sidesteps the entire problem of managing union member lifetimes: the union never *has* a member with a non-trivial destructor, so the compiler never generates destructor code for it. All lifetime management is manual.

After C++20, they use a constrained non-trivial destructor inside the union, which became possible after a language change (P2266) simplified implicit special member generation.

**libc++ (Clang)** takes a different approach. It uses a real recursive union with `__alt` wrappers:

```cpp
union __union {
    char __dummy;                        // valueless state
    __alt<0, _Tp> __head;
    __union<1, _Types...> __tail;
};
```

The `char __dummy` member handles the "valueless" state. Destruction behavior is controlled by a `_Trait` parameter with three states: `_TriviallyAvailable` (default the destructor), `_Available` (empty destructor — the outer class handles destruction), and `_Unavailable` (deleted destructor).

The key difference: libstdc++ avoids union lifetime issues with aligned buffers, libc++ uses real unions and controls destruction through a trait-based inheritance chain.

### Index tracking

Both implementations store an index alongside the storage. The interesting part is the *type* of the index:

- **libstdc++** always optimizes: fewer than 256 alternatives → `unsigned char`, fewer than 65536 → `unsigned short`, otherwise `unsigned int`. This saves memory in the common case.
- **libc++** defaults to `unsigned int` regardless of alternative count, with an opt-in optimization behind `_LIBCPP_ABI_VARIANT_INDEX_TYPE_OPTIMIZATION`.

For a `std::variant<int, double>`, libstdc++ uses 1 byte for the index, libc++ uses 4 bytes. Neither is wrong — it depends on whether you prioritize memory layout or ABI stability.

### Visitation: the vtable

This is where the two implementations diverge the most.

**libstdc++** builds a `_Multi_array` — a recursive N-dimensional array of function pointers. For visiting two variants of sizes 3 and 4, it builds a 3×4 array where each cell is a function pointer that extracts the correct pair of alternatives and calls the visitor. The entire array is `static constexpr`, computed during template instantiation.

The clever part: when visiting a **single** variant with **11 or fewer** alternatives, libstdc++ skips the table entirely and emits a `switch` statement. Each case directly invokes the correct instantiation of the visitor call. No function pointer indirection. The compiler can optimize the switch into whatever it deems best.

**libc++** uses a flat `__farray` — a simple array wrapper — with `__dispatcher` structs. Each dispatcher knows how to extract alternatives at a given set of indices and call the visitor. The dispatchers are stored in a constexpr array, and the visit function indexes into the array using the variant indices at runtime.

For the case where all variants have the same number of alternatives, libc++ has a "diagonal" optimization: it builds a 1D array instead of an N-dimensional one, because all index combinations are the same (i, i, ..., i).

### Valueless handling

This is a subtle but important design difference.

**libstdc++** handles the valueless state *inside the vtable*. When a variant can become valueless (i.e., when not all alternatives are small and trivially copyable), an extra slot is added at index 0 of the visitation array. This slot contains a function pointer that handles the valueless case — typically by calling a default visitor or rethrowing. The variant stores `variant_npos` (a sentinel value, typically `-1` cast to the index type) as the index when valueless.

**libc++** takes the simpler approach: `std::visit` checks for valueless variants at the entry point and throws `std::bad_variant_access` immediately. The visitation tables only cover valid indices. No extra slots, no cookie mechanism.

The libstdc++ approach is more flexible (you can design visitors that handle the valueless case explicitly), but the libc++ approach is simpler and generates less code.

### Trivial special member functions

Both implementations need to answer: "Is this variant trivially copyable? Trivially destructible?"

Both use fold expressions over `std::is_trivially_*_v<T>` for each alternative. The difference is in how they propagate the result.

**libstdc++** uses `bool` template parameters across 6 inheritance layers (one for each special member: default construct, copy construct, move construct, copy assign, move assign, destroy). Each layer is either "I am trivial, inherit defaults" or "I am not trivial, here is my implementation."

**libc++** uses a 3-state `_Trait` enum (`_TriviallyAvailable`, `_Available`, `_Unavailable`) across 8 inheritance layers. The extra granularity matters: `_Available` means "I can be generated but am not trivial" (the destructor exists but is not `= default`), while `_TriviallyAvailable` means "I am trivial." This affects code generation in subtle ways.

The practical impact: libstdc++ generates fewer template instantiations per variant type. libc++ generates more but has finer control over which special members are trivial, available, or deleted.

### Other notable details

- **`_Never_valueless_alt` (libstdc++)**: Types that are trivially copyable and at most 256 bytes can always be safely `memcpy`'d into place — the copy cannot throw, so the variant can never become valueless during assignment. If all alternatives satisfy this, the variant skips all valueless-related logic entirely.

- **Narrowing conversion protection (libc++)**: libc++ explicitly detects and rejects narrowing conversions in variant's converting constructor (e.g., `std::variant<int, double>(3.14)` — this would narrow `double` to `int`). libstdc++ relies on the standard's implicit rules.

- **Swap with rollback (libc++)**: When swapping two variants where the alternatives differ, if the move construction throws, libc++ attempts to roll back by moving the temporary back. This provides a stronger exception safety guarantee.

- **`__unchecked_get` (libc++)**: An internal `get` with no bounds checking, used in the visitation path where the index is already known. This avoids redundant checks in the hot path.

## What I learned

Building a toy variant taught me something I did not expect. The storage is the easy part. The `memcpy`, the aligned `char` array, even the `NthType` helper — those are all straightforward once you see the pattern.

The hard part is the **lifecycle**: knowing which type is active, destroying the old value before constructing the new one, handling the case where construction throws, and doing all of this with trivial types where the compiler can elide everything. That is where the real implementations spend most of their complexity budget.

The visitation machinery is the second hard part. Building a `constexpr` table of function pointers that covers every combination of alternatives across multiple variants is genuinely impressive template metaprogramming. And the switch optimization for small variants is the kind of pragmatic engineering that separates library implementations from academic exercises.

If you want to understand `std::variant`, do not just read cppreference. Build one. Start with a `char` array and a `memcpy`. Add `NthType`. Then try to add destruction. That is when you will appreciate what the standard library authors actually built.

The source code for both libstdc++ and libc++ is freely available. Reading it is a masterclass in how to translate type-level constraints into runtime code with minimal overhead. I recommend it.

---

*The complete toy variant from this post is available as a single file. It is not production code — but it is a good learning tool.*
