---
title: "From Templates to Reflection, Part 1: Back to Basics with type_vector in C++17"
description: "Part 1 of From Templates to Reflection: build a C++17 type_vector and explore type sequences, pack expansion, and compile-time algorithms."
date: 2026-09-13 10:00:00 +0200
tags:
  - c++
  - c++17
  - template-metaprogramming
  - compile-time
---

This is the first post in *From Templates to Reflection*, a hands-on series exploring C++ metaprogramming from C++17 through to C++26 reflection. We begin by building `type_vector`: a familiar container interface for working with types. Later posts will explore how newer language features change the way we approach these problems.

When I reach for `std::vector<int>`, I am storing *values*. Backing it, in the type system, is a description of what a bunch of ints looks like. `std::vector` treats that type as an implementation detail.

But what if I flip that around? What if the container itself—and everything inside it—lived entirely in the type system? What if I could "push back" a type, index into a list of types, filter them, transform them, deduplicate them—all without emitting a single runtime instruction?

Our goal is to bring a familiar container interface to template metaprogramming, so we can work with sequences of types using operations we already know from working with values.

That is what we will explore in this post, getting our hands dirty by building a `type_vector` and looking at how it works:

```cpp
using Points = type_vector<int, double, std::string>;
```

A compile-time sequence. A tiny database of types. The compiler is the runtime, and the elements are the arguments to a variadic template.

This post is the full walkthrough: how the container works, how `apply` solves the "unpacking" problem, how the classic `std::vector` vocabulary maps onto type-level operations, and a few real things you can build with it once it exists.

**Inspiration.** Peter Dimov's [Simple C++11 metaprogramming](https://www.boost.org/doc/libs/latest/libs/mp11/doc/html/simple_cxx11_metaprogramming.html) and [Simple C++11 metaprogramming, part 2](https://www.boost.org/doc/libs/latest/libs/mp11/doc/html/simple_cxx11_metaprogramming_2.html) are important inspirations for this exploration. The first develops type-list algorithms using variadic templates and aliases: its `mp_rename`/`mp_apply` unpacking technique and pack-based `mp_transform` connect directly to our `apply` and `transform_t`. The second explores membership testing, deduplication, and indexed access, including the compile-time cost of different implementations, giving useful context for our `contains_v`, `unique_t`, and `at_t`. Dimov's approach works across different type-list templates; ours deliberately focuses on one `type_vector` with a familiar container vocabulary. The foundations are already there in C++11; we use C++17 conveniences such as fold expressions to build this teaching version.

**A word on originality before we start.** Mature libraries already ship this exact vocabulary: [Boost.MPL](https://www.boost.org/doc/libs/release/libs/mpl/doc/refmanual/list.html)'s `mpl::list` and `mpl::vector`, [Boost.MP11](https://www.boost.org/doc/libs/release/libs/mp11/doc/html/mp11.html)'s [`mp_list`](https://www.boost.org/doc/libs/release/libs/mp11/doc/html/mp11.html#mp_list), Brigand, and others all do this—more completely, more carefully, and with far less compiler strain than anything we will write here. This post does not pretend otherwise. The point is not to beat them; it is to **build our own `type_vector` with an adapted interface so we can play and learn**: to peel the technique apart, hit every interesting design decision ourselves, and understand what those libraries are actually doing under the hood. What follows is a teaching exercise with working code, not a claim that hand-rolled beats vendor-hardened.

---

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

* TOC
{:toc}

</nav>

## The one-line idea

Everything here is C++ **except the data**. With `std::vector`, the values you store are real objects in real memory. With `type_vector`, the elements are *types*, and types are data that only the compiler can see:

```text
std::vector<int>                    ints{1, 2, 3};
  runtime:  [ 1 , 2 , 3 ]           <- values

type_vector<int, double, std::string>
  compile-time:  [ int , double , std::string ]   <- types
```

Both are "vectors." One stores objects; the other stores type arguments. And remarkably, the algorithm vocabulary we know and love maps almost one-to-one onto the compile-time version:

| `std::vector` (values)        | `type_vector` (types)                          |
|-------------------------------|------------------------------------------------|
| `v.size()`                    | `TVec::size` (a `static constexpr`)            |
| `v.push_back(x)`              | `push_back_t<TVec, X>` (a new type)            |
| `v[i]`                        | `at_t<I, TVec>`                                |
| `std::find / ==`              | `contains_v<TVec, T>`                          |
| `std::transform`              | `transform_t<TVec, F>`                         |
| `std::copy_if`                | `filter_t<TVec, Pred>`                         |
| deduplicate                   | `unique_t<TVec>`                               |
| appending two vectors         | `concat_t<TVec1, TVec2>`                       |

There is one critical difference, though. Mutating `std::vector` operations change the *same* object. `type_vector` operations are **immutable**: each one produces a brand-new type and leaves its input untouched. There are no aliasing bugs at compile time, only type identities.

---

## The core container

The whole thing starts with a variadic class template. It is barely ten lines:

```cpp
template <typename... Ts>
struct type_vector {
    static constexpr std::size_t size = sizeof...(Ts);

    template <template <typename...> class F>
    using apply = F<Ts...>;
};
```

Two members, both worth unpacking:

* **`size`** is a fold-expression-free elegance trick: `sizeof...(Ts)` counts the pack directly at compile time. `type_vector<int, double>::size` is `2`, no `constexpr` function required.
* **`apply`** is the payload. It feeds the stored pack `Ts...` into *any* variadic template `F`. We will spend a whole section on it, because it is the single most useful member of this entire design.

The emptiness is a feature. A `type_vector` has no storage, no methods, no vtable. It is just a name that happens to *carry* a pack of types around with it. Everything else in this post is machinery that lives around it, keyed off pattern-matching on `type_vector<Ts...>`.

---

## `apply`: don't convert, unpack

The moment you have a type list, the most natural question is: "how do I turn it into a `std::tuple`?" The naive answer—writing a `to_tuple` specialization—works, but it scales terribly:

```cpp
using MyTypes = type_vector<int, double, std::string>;

// The "collection of to_X helpers" approach — do not build this.
template <typename TVec> struct to_tuple;
template <typename... Ts> struct to_tuple<type_vector<Ts...>> { using type = std::tuple<Ts...>; };

template <typename TVec> struct to_variant;
template <typename... Ts> struct to_variant<type_vector<Ts...>> { using type = std::variant<Ts...>; };

// to_my_container, to_something_else, to_...          <-- a growing zoo of helpers
```

Before long you have a museum of `to_x` conversion traits, one per target template. There is a better way, and it comes from a language limitation.

C++ has no way to *spread* a nested pack into a template argument list. You cannot write:

```cpp
std::tuple<MyTypes::...>  // no pack-spreading syntax exists in C++
```

`std::tuple` expects a comma-separated pack, but `MyTypes` is one single type. There is no type-level equivalent of JavaScript's `...myArray`.

So instead of converting the list to a tuple *from outside*, we let the list do the unpacking *from inside*. That is what `apply` is for:

```cpp
using MyTypes = type_vector<int, double, std::string>;

using MyTuple = MyTypes::apply<std::tuple>;              // std::tuple<int, double, std::string>
static_assert(std::is_same_v<MyTuple,
              std::tuple<int, double, std::string>>);

using MyVariant = MyTypes::apply<std::variant>;          // std::variant<int, double, std::string>
```

`apply<std::tuple>` expands to `std::tuple<Ts...>`—exactly as if the pack had been written in place. One mechanism, every variadic template, zero extra traits. And because `apply` returns a real type, you can instantiate it in running code:

```cpp
using Ints = repeat_t<3, int>;              // type_vector<int, int, int>
Ints::apply<std::tuple> t{1, 2, 3};         // std::tuple<int, int, int>

using Appended = push_back_t<Ints, double>;
Appended::apply<std::variant> v = 3.14;     // std::variant<int, int, int, double>
```

The second line is subtle and worth pausing on: assigning `3.14` (a `double`) selects the `double` alternative, because overload resolution prefers the exact-match conversion over the narrowing ones to `int`. The variant you get is exactly the type list you built, made flesh.

`apply` works with your own templates too:

```cpp
template <typename... Ts>
struct event_handler {
    using args = type_vector<Ts...>;  // whatever you need
};

using Handler = MyTypes::apply<event_handler>;
```

The mental model: a `type_vector` is a type-list wrapper that says *"take the types I contain and feed them to any variadic template you like."* One unpacking hook is enough, and its name is `apply`.

---

## Generating vectors: `repeat_t`

A generator is our first real operation. `repeat_t<N, T>` builds `type_vector<T, T, ..., T>` with `N` copies of `T`:

```cpp
namespace detail {
    template <typename T, typename Seq>
    struct repeat_impl;

    template <typename T, std::size_t... Is>
    struct repeat_impl<T, std::index_sequence<Is...>> {
        template <std::size_t> using always_t = T;
        using type = type_vector<always_t<Is>...>;
    };
}

template <std::size_t N, typename T>
using repeat_t = typename detail::repeat_impl<T, std::make_index_sequence<N>>::type;
```

The trick: `std::make_index_sequence<N>` hands us a pack of `N` distinct `std::size_t`s (`0, 1, ..., N-1`). We do not care about their *values*—we only need them to be `N` distinct pack elements, so that `always_t<Is>...` expands to `T` exactly `N` times. `always_t<Is>` ignores its argument and yields `T`; that is the whole "discard the index" idiom.

Why bother? A structure with `N` identical fields—minted from a single repeating pack. Cleanest is `repeat` plus `apply` together:

```cpp
template <std::size_t N>
using ints_tuple = typename repeat_t<N, int>::template apply<std::tuple>;

ints_tuple<4> x{1, 2, 3, 4};   // std::tuple<int, int, int, int>
```

Because `repeat_t<N, int>` depends on `N`, C++17 needs `typename` to identify the resulting type and `template` to identify `apply` as a member template.

Or, more excitingly, a compile-time fixed-size encoding of a record with `N` slots, or a homogeneous pack to seed a more complex algorithm. `repeat_t` is the "zero-fill" of the type world.

---

## Reading: `at_t`

Indexing into a `type_vector` is pure delegation. `std::tuple` already solved this problem, so we reuse it:

```cpp
template <std::size_t I, typename TVec>
struct at;

template <std::size_t I, typename... Ts>
struct at<I, type_vector<Ts...>> {
    using type = std::tuple_element_t<I, std::tuple<Ts...>>;
};

template <std::size_t I, typename TVec>
using at_t = typename at<I, TVec>::type;

using Points = type_vector<int, double, std::string>;
using First  = at_t<0, Points>;   // int
using Third  = at_t<2, Points>;   // std::string
```

Note the pattern that recurs throughout this post: a **primary template** declared with an interface parameter (`TVec`), then a **partial specialization** that binds `TVec` to `type_vector<Ts...>` and re-exposes the pack. The interface never changes; only the implementation pattern-matches on the container shape. `at`'s body is a one-liner because `std::tuple_element_t` is already a compile-time index operation over a variadic list—our list just happens to be a `std::tuple` of the same types.

---

## Growing: `push_back`, `push_front`, `concat`

Mutation is where the immutability message really lands. Each operation returns a *new* vector:

```cpp
template <typename TVec, typename T>
struct push_back;

template <typename... Ts, typename T>
struct push_back<type_vector<Ts...>, T> {
    using type = type_vector<Ts..., T>;
};

template <typename TVec, typename T>
using push_back_t = typename push_back<TVec, T>::type;

template <typename TVec, typename T>
struct push_front;

template <typename... Ts, typename T>
struct push_front<type_vector<Ts...>, T> {
    using type = type_vector<T, Ts...>;
};

template <typename TVec, typename T>
using push_front_t = typename push_front<TVec, T>::type;

template <typename TVec1, typename TVec2>
struct concat;

template <typename... Ts1, typename... Ts2>
struct concat<type_vector<Ts1...>, type_vector<Ts2...>> {
    using type = type_vector<Ts1..., Ts2...>;
};

template <typename TVec1, typename TVec2>
using concat_t = typename concat<TVec1, TVec2>::type;
```

Reading the pattern: `push_back` takes the existing pack, appends `T`, and packs the result into a fresh `type_vector`. `concat` does the same for two packs at once—two parameter packs can both be expanded in a single template argument list, which is exactly how the concatenated pack comes out.

None of this allocates, moves, or copies anything. There is no storage to touch. The cost is entirely a function of the compiler's template instantiation machinery, and the semantics are exactly what you'd hope:

```cpp
using A = type_vector<int, float>;
using B = push_back_t<A, double>;        // type_vector<int, float, double>
using C = push_front_t<B, bool>;         // type_vector<bool, int, float, double>
using D = concat_t<C, A>;                // type_vector<bool, int, float, double, int, float>

static_assert(D::size == 6);
// A is still type_vector<int, float> — nothing was mutated.
```

`concat_t` in particular becomes the primitive that powers the "algorithm" operations below, since it lets us splice a head element onto a recursively-computed result.

---

## Querying: `contains`

The `std::find` of the type world. Fold expressions (C++17) make it a single line:

```cpp
template <typename TVec, typename T>
struct contains;

template <typename... Ts, typename T>
struct contains<type_vector<Ts...>, T>
    : std::bool_constant<(std::is_same_v<T, Ts> || ...)> {};

template <typename TVec, typename T>
inline constexpr bool contains_v = contains<TVec, T>::value;
```

The `(std::is_same_v<T, Ts> || ...)` is a **unary fold**: it ORs `is_same_v<T, Ts>` across every `Ts`, exactly like writing `a || b || c || ...`. Inheriting from `std::bool_constant<...>` is the modern way to give a trait a `.value` (and the `_v` alias below).

```cpp
using Types = type_vector<int, float, double>;

static_assert(contains_v<Types, float>);
static_assert(!contains_v<Types, std::string>);
```

The `_v` variable template closes the ergonomics gap with the standard library's `_v` conventions.

---

## Algorithms: `transform`

Mapping a unary metafunction over the list is the most "std::vector-ish" of the algorithms. The transformation arrives as a *template-template parameter*—`F` is a template invoked with one type to produce a type:

```cpp
template <typename TVec, template <typename> class F>
struct transform;

template <typename... Ts, template <typename> class F>
struct transform<type_vector<Ts...>, F> {
    using type = type_vector<F<Ts>...>;
};

template <typename TVec, template <typename> class F>
using transform_t = typename transform<TVec, F>::type;
```

The pack expansion `F<Ts>...` does all the work: apply `F` to every element, repack. `apply` passes the entire pack to `F<Ts...>`, so its template-template parameter is variadic; `transform` passes one element at a time to `F<T>`, so its slot is unary. This requires `F` to accept one explicit type argument, not necessarily to declare exactly one parameter. One example:

```cpp
using Types = type_vector<int, double, float, char>;
using Pointers = transform_t<Types, std::add_pointer_t>;
// type_vector<int*, double*, float*, char*>
```

Both `std::add_pointer_t` and `std::is_integral` (used with `filter` below) are templates taking exactly one type parameter, so they drop straight into the `template <typename> class F` or `template <typename> class Pred` slots.

There is a real gotcha hiding here: `F<Ts>` only works for templates that can be named with one explicit type argument. Modern C++17 compilers accept `std::vector` here because its allocator parameter has a default:

```cpp
using Vectors = transform_t<Types, std::vector>;   // type_vector<std::vector<int>, ...>
```

But the one-line adapter is still useful when the template needs extra fixed arguments, when older compilers are in play, or when you want to make the intent explicit:

```cpp
template <typename T> using vector_of = std::vector<T>;

using Vectors = transform_t<Types, vector_of>;      // type_vector<std::vector<int>, ...>
```

**Tip:** If you write a metafunction that is "almost right," wrap it as `template <typename T> using ... = ...;` and transform freely.

---

## Algorithms: `filter`

Filtering keeps only the elements satisfying a predicate. This one needs recursion, because a pack cannot be filtered "in place"—we rebuild the result one element at a time:

```cpp
namespace detail {
    template <template <typename> class Pred, typename TVec>
    struct filter_impl;

    template <template <typename> class Pred>
    struct filter_impl<Pred, type_vector<>> {
        using type = type_vector<>;                       // base case
    };

    template <template <typename> class Pred, typename T, typename... Rest>
    struct filter_impl<Pred, type_vector<T, Rest...>> {
        using next = typename filter_impl<Pred, type_vector<Rest...>>::type;
        using type = std::conditional_t<
            Pred<T>::value,
            concat_t<type_vector<T>, next>,
            next
        >;
    };
}
```

Trace it: `filter_impl` takes the head `T` out of the pack, recursively filters the tail, then *keeps* `T` (by concatenating it onto the filtered tail) only if `Pred<T>::value` is true. The recursion bottoms out at the empty vector. It is a straightforward left-to-right scan—like the recursive version of `std::copy_if`.

```cpp
template <typename TVec, template <typename> class Pred>
using filter_t = typename detail::filter_impl<Pred, TVec>::type;

using Types = type_vector<int, double, float, char>;
using IntegralOnly = filter_t<Types, std::is_integral>;
// type_vector<int, char>
```

And the honest limitation: this first-then-rewrite approach instantiates a fresh `type_vector<Rest...>` at every step. For short lists (say, dozens of types), it is completely fine. For thousands of types, the template-instantiation depth becomes the real limit, not your logic—and an accumulation-style rewrite (like the `unique` below) is kinder to the compiler.

---

## Algorithms: `unique`

Deduplication is the accumulation pattern. Instead of processing "rest and remember the result," we thread an **output accumulator** through the recursion:

```cpp
namespace detail {
    template <typename In, typename Out>
    struct unique_impl;

    template <typename Out>
    struct unique_impl<type_vector<>, Out> {
        using type = Out;
    };

    template <typename Head, typename... Tail, typename Out>
    struct unique_impl<type_vector<Head, Tail...>, Out> {
        using next_out = std::conditional_t<
            contains_v<Out, Head>,
            Out,
            push_back_t<Out, Head>
        >;
        using type = typename unique_impl<type_vector<Tail...>, next_out>::type;
    };
}

template <typename TVec>
using unique_t = typename detail::unique_impl<TVec, type_vector<>>::type;
```

Walk through it with `type_vector<int, double, int, float, double, char>`:

1. `Out` starts empty; `Head = int` is not in `Out`, so `Out = [int]`.
2. `Head = double`, not in `Out`, so `Out = [int, double]`.
3. `Head = int` **is** in `Out`, so `Out` stays `[int, double]`—this is the dedup step.
4. And so on: `[int, double, float]`, then `double` skipped, then `char` added.

```cpp
using Mixed = type_vector<int, double, int, float, double, char>;
using Unique = unique_t<Mixed>;
static_assert(std::is_same_v<Unique, type_vector<int, double, float, char>>);
```

Because membership is checked against the already-seen `Out`, all duplicates collapse to first occurrence. It is O(n²) in type identity comparisons—trivial for realistic lists.

---

## Putting it all together

Here is the whole library and a test bed that exercises every operation. It is exactly what we built above, assembled:

```cpp
#include <cstddef>
#include <type_traits>
#include <utility>
#include <tuple>
#include <variant>
#include <string>
#include <iostream>

// 1. Core container
template <typename... Ts>
struct type_vector {
    static constexpr std::size_t size = sizeof...(Ts);

    template <template <typename...> class F>
    using apply = F<Ts...>;
};

// 2. Generators & operations (as built in the sections above)
namespace detail {
    template <typename T, typename Seq>
    struct repeat_impl;

    template <typename T, std::size_t... Is>
    struct repeat_impl<T, std::index_sequence<Is...>> {
        template <std::size_t> using always_t = T;
        using type = type_vector<always_t<Is>...>;
    };
}

template <std::size_t N, typename T>
using repeat_t = typename detail::repeat_impl<T, std::make_index_sequence<N>>::type;

template <std::size_t I, typename TVec>
struct at;

template <std::size_t I, typename... Ts>
struct at<I, type_vector<Ts...>> {
    using type = std::tuple_element_t<I, std::tuple<Ts...>>;
};

template <std::size_t I, typename TVec>
using at_t = typename at<I, TVec>::type;

template <typename TVec, typename T>
struct push_back;

template <typename... Ts, typename T>
struct push_back<type_vector<Ts...>, T> {
    using type = type_vector<Ts..., T>;
};

template <typename TVec, typename T>
using push_back_t = typename push_back<TVec, T>::type;

template <typename TVec, typename T>
struct push_front;

template <typename... Ts, typename T>
struct push_front<type_vector<Ts...>, T> {
    using type = type_vector<T, Ts...>;
};

template <typename TVec, typename T>
using push_front_t = typename push_front<TVec, T>::type;

template <typename TVec1, typename TVec2>
struct concat;

template <typename... Ts1, typename... Ts2>
struct concat<type_vector<Ts1...>, type_vector<Ts2...>> {
    using type = type_vector<Ts1..., Ts2...>;
};

template <typename TVec1, typename TVec2>
using concat_t = typename concat<TVec1, TVec2>::type;

template <typename TVec, typename T>
struct contains;

template <typename... Ts, typename T>
struct contains<type_vector<Ts...>, T>
    : std::bool_constant<(std::is_same_v<T, Ts> || ...)> {};

template <typename TVec, typename T>
inline constexpr bool contains_v = contains<TVec, T>::value;

template <typename TVec, template <typename> class F>
struct transform;

template <typename... Ts, template <typename> class F>
struct transform<type_vector<Ts...>, F> {
    using type = type_vector<F<Ts>...>;
};

template <typename TVec, template <typename> class F>
using transform_t = typename transform<TVec, F>::type;

namespace detail {
    template <template <typename> class Pred, typename TVec>
    struct filter_impl;

    template <template <typename> class Pred>
    struct filter_impl<Pred, type_vector<>> {
        using type = type_vector<>;
    };

    template <template <typename> class Pred, typename T, typename... Rest>
    struct filter_impl<Pred, type_vector<T, Rest...>> {
        using next = typename filter_impl<Pred, type_vector<Rest...>>::type;
        using type = std::conditional_t<Pred<T>::value,
                                        concat_t<type_vector<T>, next>,
                                        next>;
    };
}

template <typename TVec, template <typename> class Pred>
using filter_t = typename detail::filter_impl<Pred, TVec>::type;

namespace detail {
    template <typename In, typename Out>
    struct unique_impl;

    template <typename Out>
    struct unique_impl<type_vector<>, Out> {
        using type = Out;
    };

    template <typename Head, typename... Tail, typename Out>
    struct unique_impl<type_vector<Head, Tail...>, Out> {
        using next_out = std::conditional_t<contains_v<Out, Head>,
                                            Out,
                                            push_back_t<Out, Head>>;
        using type = typename unique_impl<type_vector<Tail...>, next_out>::type;
    };
}

template <typename TVec>
using unique_t = typename detail::unique_impl<TVec, type_vector<>>::type;

// 3. Tests
int main() {
    using IntVec3  = repeat_t<3, int>;                    // [int, int, int]
    using Appended = push_back_t<IntVec3, double>;        // [int, int, int, double]
    using FirstType = at_t<0, Appended>;                  // int
    using SecondType = concat_t<Appended, IntVec3>;       // 4 + 3 = 7 elements

    static_assert(SecondType::size == 7);
    static_assert(std::is_same_v<FirstType, int>);
    static_assert(contains_v<Appended, double>);
    static_assert(!contains_v<Appended, std::string>);

    IntVec3::apply<std::tuple> t1{1, 2, 3};
    Appended::apply<std::variant> v1 = 3.14;

    using Mixed  = type_vector<int, double, int, float, double, char>;
    using Unique = unique_t<Mixed>;
    static_assert(std::is_same_v<Unique, type_vector<int, double, float, char>>);

    using Pointers = transform_t<Unique, std::add_pointer_t>;
    static_assert(std::is_same_v<Pointers, type_vector<int*, double*, float*, char*>>);

    using Integrals = filter_t<Unique, std::is_integral>;
    static_assert(std::is_same_v<Integrals, type_vector<int, char>>);

    std::cout << "All assertions passed!" << std::endl;
}
```

[Try it on Compiler Explorer (Godbolt)](https://godbolt.org/z/d5f5MTrT9), or build it locally:

```sh
g++ -std=c++17 -Wall -Wextra -pedantic type_vector.cpp -o type_vector && ./type_vector
```

Every `static_assert` runs at compile time; the `std::cout` is just proof that the program linked. This needs C++17—the fold expression in `contains` (and the `inline constexpr` variable) are the only strictly-17 bits; swap those for a recursive trait and the whole library compiles as C++14.

---

## What you can actually build with it

A bare container is an answer searching for a question. Here is where it starts paying rent.

### 1. Compile-time function signatures

Describe a signature as data, then introspect it:

```cpp
struct Handler {
    using return_type = int;
    using arguments   = type_vector<float, double, std::string>;
};

static_assert(std::is_same_v<at_t<0, Handler::arguments>, float>);
static_assert(contains_v<Handler::arguments, std::string>);
```

Registration tables, RPC descriptors, and code generators all feed on exactly this shape.

### 2. Size-of metacomputation

A fold expression over the list computes aggregate sizes or offsets at compile time:

```cpp
template <typename TVec>
struct total_size;

template <typename... Ts>
struct total_size<type_vector<Ts...>> {
    static constexpr std::size_t value = (std::size_t{0} + ... + sizeof(Ts));
};

using Packet = type_vector<int, float, double>;
static_assert(total_size<Packet>::value == sizeof(int) + sizeof(float) + sizeof(double));
static_assert(total_size<type_vector<>>::value == 0);
```

The zero seed makes this binary fold valid for an empty vector too.

Swap the fold body for a custom "accumulate" and the same trick becomes serialized-size computation, alignment padding, or generic field-offset math.

### 3. Variant-driven dispatch

The classic: turn a type list into a `std::variant` of handlers and bang on it:

```cpp
using Events = type_vector<KeyDown, KeyUp, MouseMove, Paint>;

using EventVariant = Events::apply<std::variant>;
// std::variant<KeyDown, KeyUp, MouseMove, Paint>

struct Visitor {
    void operator()(KeyDown   const&) const {}
    void operator()(KeyUp     const&) const {}
    void operator()(MouseMove const&) const {}
    void operator()(Paint     const&) const {}
};

EventVariant event = MouseMove{};
std::visit(Visitor{}, event);
```

If a future revision of the system gains a `WindowResize` event, you add it to the `type_vector` once and every dependent type updates by construction. The type list is the *single source of truth*, and `filter`, `transform`, and `concat` all compose to shape it.

### 4. Compile-time pipelines

Stages as types:

```cpp
struct Parse;     struct Validate;
struct Transform; struct Serialize;
struct Log;

using Pipeline = type_vector<Parse, Validate, Transform, Serialize>;
using Extended = push_back_t<Pipeline, Log>;

using First = at_t<0, Extended>;   // Parse
```

A dispatcher can then recursively walk the list—each stage carrying its own `process(...)`—and the pipeline's shape is data you can query, extend, and filter (`filter_t` on a tag-by-stage basis, for example) before it ever becomes a function call.

### 5. Fixed-shape storage from `repeat`

`repeat_t` plus `apply` is a compact way to mint fixed-size structures:

```cpp
template <std::size_t N>
using doubles_tuple = typename repeat_t<N, double>::template apply<std::tuple>;

doubles_tuple<5> samples{1.0, 2.0, 3.0, 4.0, 5.0};   // std::tuple<double, double, double, double, double>
```

It also seeds ECS/SoA layouts: `transform_t<Components, column_of>` where `column_of<T> = std::vector<T>` gives you one parallel array per component type, generated from a single declaration.

---

## Honest limitations

`type_vector` is a workhorse, but it is not magic:

* **Instantiation depth is the real ceiling.** Recursive `filter`/`unique` on a list of ten types is indistinguishable from fast. On a thousands-long list, you are trading template depth for elegance, and the compiler may refuse. Prefer accumulation-style recursion (or a real library, next bullet) past a few hundred elements.
* **The transform slot is unary.** Notice how `transform_t` applies `F<T>` for each element. Templates that need more explicit arguments need a small alias shim, such as `template <typename T> using boxed = Box<T, Policy>;`. If you ever build a version-2 API, this is the argument for accepting metafunction objects as well as alias templates.
* **`std::vector` you can resize at runtime; `type_vector` you cannot.** A `type_vector`'s contents are decided at compile time. That is the point, but it is why `type_vector` complements, rather than replaces, runtime containers.
* **There is no pack-spreading syntax.** That one language gap is the entire reason `apply` exists. If C++ ever gets "typed pack expansion" sugar, `type_vector` could shrink to a pure type-list wrapper, but today `apply` is the cleanest story.

If you want this vocabulary at scale without maintaining it yourself, the ideas here are exactly what mature libraries already ship: [Boost.MPL](https://www.boost.org/doc/libs/release/libs/mpl/doc/refmanual/list.html)'s `mpl::list` and `mpl::vector`, [Boost.MP11](https://www.boost.org/doc/libs/release/libs/mp11/doc/html/mp11.html)'s `mp_list` (which also powers large parts of Boost.Beast and others), Hans-Bernhard Bröker's brigand, and many more. Using one of those in production is the right call, and I would not hand-roll this for shipped code. The value of our `type_vector` is different: it is a readable, dependency-free implementation of the same ideas, built to adopt the interface we like and then pull it apart to understand the trade-offs—which is exactly what playing with a technique is for. And the direction of travel in the standard is complementary: C++26's added reflection (`std::meta`) makes *introspecting real types* easy, while a hand-rolled type list remains the simplest way to *carry* a set of types around as data. The two compose nicely—reflection produces the contents, `type_vector` moves them around.

---

## The mental model

Do not think of `type_vector` as a vector that stores value objects. Think of it as:

> **a compile-time sequence that lets you pass around and transform a set of types.**

```text
using A = type_vector<int, float>;
using B = push_back_t<A, double>;
using C = concat_t<B, type_vector<std::string, bool>>;

A → [int, float]
       │ push_back
B → [int, float, double]
       │ concat
C → [int, float, double, std::string, bool]
```

Then any template can receive `C`, inspect it with `at_t` and `contains_v`, shape it with `filter_t`, `transform_t`, and `unique_t`, and finally unpack it into a concrete `std::tuple` or `std::variant` with `apply`. From the compiler's point of view, you are programming with types as data—and from the runtime's point of view, there is nothing there at all.

That is the whole trick. Everything in this post is ten small templates; the power is entirely in how they compose. The compiler becomes the runtime, the types become the values, and `static_assert` becomes your unit test.

---

## References and further reading

* Peter Dimov, [Simple C++11 metaprogramming](https://www.boost.org/doc/libs/latest/libs/mp11/doc/html/simple_cxx11_metaprogramming.html): inspiration for type lists, unpacking, and transforms.
* Peter Dimov, [Simple C++11 metaprogramming, part 2](https://www.boost.org/doc/libs/latest/libs/mp11/doc/html/simple_cxx11_metaprogramming_2.html): membership, deduplication, indexed access, and compile-time performance.
* [Boost.MPL list reference](https://www.boost.org/doc/libs/release/libs/mpl/doc/refmanual/list.html).
* [Boost.MP11 documentation](https://www.boost.org/doc/libs/release/libs/mp11/doc/html/mp11.html) and its [`mp_list` reference](https://www.boost.org/doc/libs/release/libs/mp11/doc/html/mp11.html#mp_list).
* [C++ working draft: template name resolution](https://eel.is/c++draft/temp.res): dependent names and template disambiguation.
* [C++ working draft: fold expressions](https://eel.is/c++draft/expr.prim.fold): fold semantics, including empty packs.
* [WG21 feature-testing recommendations](https://open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0096r2.html): lists fold expressions among C++17 features.
* [This post's code on Compiler Explorer (Godbolt)](https://godbolt.org/z/d5f5MTrT9).
