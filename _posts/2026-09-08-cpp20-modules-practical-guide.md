---
title: "C++20 Modules in Practice: From Header Hell to Modular Architecture"
description: A hands-on walkthrough of C++20 Modules—building a small library from scratch with CMake and Ninja, separating interfaces from implementations, exploring partitions, and understanding what works today.
date: 2026-09-08 10:00:00 +0200
tags:
  - c++
  - c++20
  - modules
  - cmake
  - build-systems
---

C++20 Modules replace C++'s traditional textual inclusion model with a compiled module interface. Instead of repeatedly preprocessing the same headers in every translation unit, consumers explicitly `import` the interface they depend on. No more header guards, no more include-ordering surprises, no more accidentally pulling in transitive dependencies through a chain of `#include` directives.

But the gap between understanding the idea and actually using modules in a project is significant. Build-system support differs between generators, compilers and standard libraries move at different paces, and partitions have sharp edges that only appear when you build. This post walks through building a small C++ library and application using C++20 Modules, progressively evolving the project to cover the concepts you need in practice.

Everything below was built and run with the toolchain on my machine as of September 2026: **GCC 16.2.1, CMake 4.3.0, Ninja 1.13.2** on Linux. Each example that is claimed to work was actually compiled, linked, and executed.

---

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

* TOC
{:toc}
</nav>

For the full language specification, see the [C++ modules reference on cppreference](https://en.cppreference.com/w/cpp/language/modules) and [Microsoft's modules documentation](https://learn.microsoft.com/en-us/cpp/cpp/modules-cpp).

## Mental Model: The Key Declarations

Before diving in, here is the vocabulary you will need. Each keyword has a precise meaning, and conflating them is the source of most confusion around modules.

| Declaration | What it means | Visible to importers? |
|---|---|---|
| `export module math;` | Defines the **module interface unit** for named module `math` | Yes (exported entities) |
| `module math;` | Declares this translation unit as a **module implementation unit** belonging to `math` | No |
| `import math;` | **Imports** the named module `math`, making its exported names visible | — |
| `module;` | Opens the **global module fragment** (for legacy preprocessing, before the module declaration) | No |
| `export module math:addition;` | Defines a **partition interface unit** of `math` | Yes (if re-exported via `export import`) |
| `module math:addition;` | Defines a **partition implementation unit** of `math` (name must not duplicate an existing interface partition) | Internal to module only |
| `import <vector>;` | Imports a **header unit** (a header compiled as a unit, not a named module) | — |

Note especially the difference between two *import*-sounding declarations: `import math;` means "make this named module's exports available to me", while `module math;` means "this translation unit is part of the implementation of module `math`". They do opposite things, and beginners routinely confuse them.

## What a Named Module Actually Is

A **named module** is a logical entity consisting of one or more **module units**. Three kinds of units matter for this article:

- A **module interface unit** — a translation unit that begins with `export module <name>;` and provides the module's exported interface.
- A **module implementation unit** — a translation unit that begins with `module <name>;`, belongs to the module, but does not itself export anything.
- A **module partition** — a translation unit whose name includes a `:` (e.g. `export module math:addition;`); partitions are always part of a named module.

Conflating "a module" with "a .cppm file" is a common mistake. A module is the *set* of units sharing the module name; the interface unit is just one of them, and the exported names are only the ones marked `export`.

Unlike a header, a module interface is compiled as a translation unit, and consumers read the compiler's compiled representation of that interface rather than repeatedly preprocessing the same header text.

```cpp
// math.cppm — module interface unit
export module math;

export int add(int a, int b) {
    return a + b;
}
```

```cpp
// main.cpp — consumer translation unit
import math;

int main() {
    return add(1, 2);
}
```

That is the simplest possible module. Interface in one file, consumer in another, no headers in sight.

## Building Modules with CMake and Ninja

CMake's module story has evolved rapidly—see [Kitware's overview of the journey from experimental flags to the file-set API](https://www.kitware.com/import-cmake-the-experiment-is-over/) and the [CMake Discourse thread on C++20 modules progress](https://discourse.cmake.org/t/c-20-modules-update/7330) for background on where things stand. There are two important prerequisites before any of this builds:

1. **The generator matters.** CMake's C++ module dependency scanning (checking which units produce which interface files, and ordering compilation so interfaces build before their importers) is supported by the **Ninja**, **Ninja Multi-Config**, and **Visual Studio 17 2022** generators. It is *not* supported by the Unix Makefiles generator. On Linux, CMake picks Unix Makefiles by default, so you must request Ninja explicitly:

   ```sh
   cmake -S . -B build -G Ninja
   ```

   > **Tip for IDE users:** If you are using CLion, VS Code with CMake Tools, or another IDE, check your CMake generator settings. Many still default to Unix Makefiles on Linux. Explicitly set `-G Ninja` in your CMake configuration (e.g., CLion's *Toolchains > CMake options*, or VS Code's `cmake.generator` setting) to avoid silent module-scanning failures.

2. **Module interface files must be declared as a `CXX_MODULES` file set.** Declaring `math.cppm` the way you would list a plain source does not work in modern CMake. I verified this: with CMake 4.3, listing the file directly in `add_executable()` fails with

   ```
   CMake Error: Output CMakeFiles/app.dir/math.cppm.o provides the `math` module
   but it is not found in a `FILE_SET` of type `CXX_MODULES`
   ```

   C++ modules need their own file-set type, which CMake introduced for modules in 3.28:

```cmake
cmake_minimum_required(VERSION 3.30)
project(MathLib LANGUAGES CXX)

add_executable(app main.cpp)

target_sources(app PRIVATE
    FILE_SET CXX_MODULES
    FILES math.cppm
)

target_compile_features(app PRIVATE cxx_std_20)
```

```sh
cmake -S . -B build -G Ninja
cmake --build build
./build/app
```

CMake analyzes the module dependency graph and compiles `math` before `main.cpp`, even if `math.cppm` is listed after it in the file set.

A few CMake version notes:

- CMake 3.28 introduced both the `CXX_MODULES` file set and initial experimental module support.
- The `CMAKE_EXPERIMENTAL_CXX_MODULE_CMAKE_API` flag is no longer needed when using the file-set approach on recent toolchains; CMake enables module dependency scanning automatically with a supported generator.
- If you are on an older CMake than 3.30, expect version-specific behaviour. Module support has changed in every release since 3.28, and the examples here were tested with CMake 4.3.0.

## Interface vs. Implementation Units

A module interface file can contain both declarations and definitions. But in practice, you want to separate them—just like you would with headers and source files.

Consider a math library with an `add` function:

```cpp
// math.cppm — interface unit
export module math;

export int add(int a, int b);
```

```cpp
// math.cpp — implementation unit
module math;

int add(int a, int b) {
    return a + b;
}
```

Notice the difference: the interface unit uses `export module math;`, while the implementation unit uses just `module math;`. The `export` keyword on `add` in the interface makes it visible to consumers. The implementation file provides the body.

The module's exported interface defines what names are intentionally made available. Declarations that are not exported are not reachable by importers through normal means.

### Implementation units do not map one-to-one to declarations

An implementation unit does not have to correspond one-to-one with an exported declaration. A single implementation unit can define several exported functions, an exported function can be defined directly in the interface unit, and multiple implementation units can contribute to the same module. The split is an engineering choice, not a language requirement.

For example, everything in the interface:

```cpp
// math.cppm — everything in the interface unit
export module math;

export int add(int a, int b) {
    return a + b;
}
```

Or definitions spread across implementation units:

```cpp
// math.cppm
export module math;

export int add(int a, int b);
export int multiply(int a, int b);
```

```cpp
// math.cpp — implementation unit
module math;

int add(int a, int b) {
    return a + b;
}

int multiply(int a, int b) {
    return a * b;
}
```

Neither form is "more correct". What matters is that the exported names are declared with `export` in the interface unit.

## Splitting Implementation Across Files

As your library grows, you can split implementation code across multiple `.cpp` files. Each file that begins with `module math;` is an implementation unit of `math`, and the compiler and linker combine them.

```
math-modules/
├── CMakeLists.txt
├── math.cppm
├── math_add.cpp
├── math_multiply.cpp
└── main.cpp
```

```cpp
// math.cppm — interface unit
export module math;

export int add(int a, int b);
export int multiply(int a, int b);
```

```cpp
// math_add.cpp — implementation unit
module math;

int add(int a, int b) {
    return a + b;
}
```

```cpp
// math_multiply.cpp — implementation unit
module math;

int multiply(int a, int b) {
    return a * b;
}
```

Crucially, **implementation units are not module files** in the `CXX_MODULES` sense. They are ordinary sources that happen to declare `module math;`. I verified that listing `math_add.cpp` and `math_multiply.cpp` inside `FILE_SET CXX_MODULES` fails with:

```
CMake Error: Output CMakeFiles/app.dir/math_add.cpp.o is of type `CXX_MODULES`
but does not provide a module interface unit or partition
```

The correct representation:

```cmake
cmake_minimum_required(VERSION 3.30)
project(MathLib LANGUAGES CXX)

add_executable(app main.cpp)

target_sources(app PRIVATE
    FILE_SET CXX_MODULES
    FILES math.cppm
)
target_sources(app PRIVATE
    math_add.cpp
    math_multiply.cpp
)

target_compile_features(app PRIVATE cxx_std_20)
```

```sh
cmake -S . -B build -G Ninja
cmake --build build
./build/app
```

All three module units—`math.cppm`, `math_add.cpp`, and `math_multiply.cpp`—belong to the named module `math`. CMake compiles them separately and links them together.

An incremental rebuild after changing `main.cpp` recompiles only the consumer and relinks; the module interface is not rebuilt. I verified this with `ninja: no work to do` on an unchanged tree, and a two-step rebuild after touching `main.cpp`.

### A library, not just an executable

Once you want to share the module, the same structure applies to a library target. Implementation units are plain private sources; the interface file is a public `CXX_MODULES` file set, which CMake can later install as a compiled module interface:

```cmake
cmake_minimum_required(VERSION 3.30)
project(MathLib LANGUAGES CXX)

add_library(math
    math_add.cpp
    math_multiply.cpp
)

target_sources(math
    PUBLIC
        FILE_SET CXX_MODULES
        FILES math.cppm
)

target_compile_features(math PUBLIC cxx_std_20)

add_executable(app main.cpp)
target_link_libraries(app PRIVATE math)
```

## Modules and Legacy Headers

Real projects do not start from scratch. You will have existing header-based libraries, system headers, and third-party dependencies. C++20 gives you three distinct ways for a module to interact with legacy textual headers, and it's worth keeping them clearly separated:

1. **`#include` in the global module fragment** — for headers processed before the module purview begins.
2. **`#include` in the module purview** — possible for headers you need to parse, but with real costs.
3. **`import` of a header unit** — a header compiled as a unit rather than textually included.

The common mistake is reaching straight for mechanism 2 because it looks like a plain include.

### `#include` in the module purview

A module interface unit can contain `#include` directives. However, declarations introduced by those headers are **not automatically exported** merely because they were included. `export module strings;` followed by `#include <string>` is not the same as `export import <string>;`.

```cpp
// strings.cppm — interface unit
export module strings;

#include <string>

export std::string concatenate(const std::string& a, const std::string& b);
```

The `std::string` declarations are needed to parse the exported function signature, but they are not part of the module's exported interface. Yet the header still has an effect: its declarations become part of the module's semantic dependencies, and including large or implementation-oriented headers here increases coupling and complicates portability.

The deeper risk is **module attachment**. When you `#include` a header inside the module purview, the declarations from that header become *attached* to the named module. Entities acquired through module attachment acquire **module linkage**—they are internal to the module's linkage domain. If another translation unit—outside any named module—also `#include`s the same header in the traditional way, the same declarations acquire **external linkage** instead. You now have two different linkage contexts for what looks like the same entity. This can cause subtle **One Definition Rule (ODR)** violations or symbol conflicts at link time, because the compiler treats the module-attached copy and the traditionally-included copy as distinct. The symptoms range from mysterious linker errors to silent undefined behaviour at runtime.

So: including headers in the module purview is *possible*, but it is not harmless, and cppreference's guidance is to avoid it in the module interface when you can. Prefer the global module fragment (below) when textual inclusion is genuinely needed.

### The global module fragment

The global module fragment exists precisely for the case where textual inclusion is needed. It lets preprocessing directives—especially legacy includes and configuration macros—be processed before the module purview begins.

```cpp
// legacy_wrapper.cppm
module;

// Processed in the global module, before the module purview.
#include "legacy_header.h"

export module legacy_wrapper;

export void wrapper_function() {
    legacy_function();  // from legacy_header.h
}
```

The `module;` declaration at the top opens the global module fragment; everything between `module;` and `export module legacy_wrapper;` is processed in the global module. After the `export module` line, the purview begins.

The standard is strict about what the GMF may contain: **only preprocessor directives** (`#include`, `#define`, `#ifdef`, etc.). You cannot write raw C++ declarations or definitions inside the GMF—anything that is not a preprocessor directive is ill-formed there. Any declarations you need must come from headers included within the fragment, not from hand-written code.

This is not a bulletproof "safe zone": its purpose is to apply legacy textual inclusion semantics before the module machinery starts. Some legacy headers can still cause problems here. But for headers that need to be textually present—particularly those with configuration macros—the global module fragment is the intended mechanism.

Note the distinction: a regular `.cpp` source without any module declaration is an ordinary non-module translation unit. It is *not* a "global module fragment" and does not belong to any named module. The `module;` declaration must be written explicitly.

### Header units

C++20 also defines **header units**, which allow a header to be imported rather than textually included:

```cpp
import <vector>;
import "my_legacy_header.h";
```

Header units behave differently from named modules: they preserve much more of the header's semantics (they are, essentially, the header compiled as a unit), and they are primarily a migration and interoperability mechanism. A header processed as a header unit is not a named module and does not get `export` semantics. Importing a header unit also requires explicit compiler flags and build-system support to generate a BMI for every header you want to import, which is one reason `import std;` (C++23) superseded header units for standard-library usage: it provides a single, curated module instead of requiring per-header BMI generation. Support for header units is uneven across compilers, which is why this article focuses on named modules—but you should know the distinction exists, because `import` alone does not always mean "named module".

## Migrating a Header-Based Library

Migrating an existing `include/` + `src/` library to modules is not a mechanical one-to-one conversion. But the general mapping is:

| Traditional | Possible module equivalent |
|---|---|
| Public header (`include/lib/foo.h`) | Module interface unit (`foo.cppm`) |
| Source file (`src/foo.cpp`) | Module implementation unit (`foo.cpp`, `module foo;`) |
| Private header (`include/lib/detail/bar.h`) | Header included by an implementation unit, or a module partition when appropriate |
| Header-only component | Interface unit, or an interface partition, depending on design |

The key insight: headers that were previously available to anyone who included the public header become invisible to importers unless explicitly exported. This is the explicit boundary that modules enforce.

```cpp
// foo.cppm — the public interface (replaces include/lib/foo.h)
export module foo;

export void public_function();
```

```cpp
// foo.cpp — implementation unit (replaces src/foo.cpp)
module foo;

#include "detail/helpers.h"   // private header included here, not exported

void public_function() {
    internal_helper();
}
```

The private header is included only in the implementation unit. Its contents are not visible to importers of `foo`.

## Partitions

**Partitions** let you split a module into multiple logical units. There are two kinds, and they serve different purposes:

- An **interface partition** begins with `export module math:addition;`. It can contain exported declarations, and can be re-exported from the primary module interface with `export import :addition;`, making its exports visible to consumers of `math`.
- An **implementation partition** begins with `module math:addition;`—without the `export` on the declaration. It cannot export names; it exists only for module-internal organization, often to split a large implementation across files without exposing those boundaries.

The interface-partition arrangement, with definitions written directly in the partition interfaces:

```cpp
// math.cppm — primary interface
export module math;

export import :addition;
export import :multiplication;
```

```cpp
// math.addition.cppm — interface partition
export module math:addition;

export int add(int a, int b) { return a + b; }
```

```cpp
// math.multiplication.cppm — interface partition
export module math:multiplication;

export int multiply(int a, int b) { return a * b; }
```

```cpp
// main.cpp
import math;

int main() { return multiply(add(1, 2), 3); }
```

```cmake
cmake_minimum_required(VERSION 3.30)
project(MathLib LANGUAGES CXX)

add_executable(app main.cpp)

target_sources(app PRIVATE
    FILE_SET CXX_MODULES
    FILES
        math.cppm
        math.addition.cppm
        math.multiplication.cppm
)

target_compile_features(app PRIVATE cxx_std_20)
```

I compiled and ran this exact arrangement on the toolchain described above; it builds and runs.

### A sharp edge: implementation partitions

In C++20, the declaration `module math:addition;` is ambiguous—it can mean two distinct things:

1. **The implementation unit for an existing interface partition.** You have already defined `export module math:addition;` in a `.cppm` file, and this `.cpp` file provides its definitions.
2. **An internal implementation partition.** A partition that is *not* exported to module consumers, but is imported by the primary module (or another partition) via `import :addition;`. This partition is internal to the module's build, not part of its public interface.

This is not merely a toolchain quirk—it reflects a **C++20 standard constraint**: partition names must be unique within a named module. A module can have one primary interface unit (`export module math;`) and multiple primary implementation units (`module math;`), but each partition name designates a *single, distinct* translation unit. You cannot have both an interface partition and a separate implementation file sharing the partition name `:addition`.

In practice, this means `math.addition.cppm` with `export module math:addition;` and `math.add_impl.cpp` with `module math:addition;` both target the same partition name, and GCC's build model tries to emit a compiled module interface (`.gcm` / BMI) for both. The BMI output is named after the *partition name* (`math-addition.gcm`), not the source file, so the build fails with:

```
ninja: build stopped: multiple rules generate CMakeFiles/app.dir/math-addition.gcm.
```

Renaming the files does not help—the collision follows the partition name, not the filename. If you want to separate implementation details into an internal partition, it must use a **unique partition name** (e.g., `module math:addition_impl;`), or the definitions should be placed in a standard module implementation unit (`module math;`). On the toolchain tested here, the standard-constraint collision manifests as a build failure; the language rule is clear, and the build system is correctly enforcing it.

## The `std` Module (C++23)

The `std` module deserves its own section because it combines a genuinely useful idea with a lot of ecosystem caveats.

First, the distinction the article's title implies: **modules are C++20, but `import std;` is C++23.** The standard-library module is standardized in C++23 and tracked by the `__cpp_lib_modules` feature-test macro. A `std`-module is not the same as the C++20 named-module machinery—it builds on it, but requires a compiler *and* standard-library implementation that support it.

```cpp
// main.cpp
import std;

int main() {
    std::vector<int> v = {1, 2, 3};
    std::ranges::sort(v);
    std::cout << v[0] << '\n';
}
```

`import std;` can substantially reduce repeated parsing of standard-library headers in some projects, but the actual build-time improvement depends heavily on the compiler, standard library, and project. Do not expect a fixed percentage; measure it on your own tree.

The practical situation deserves precision:

- **Compilers do not ship `import std;` as a free lunch.** On my machine, GCC's libstdc++ provides `bits/std.cc` and a `libstdc++.modules.json`, but `import std;` still fails out of the box with `unknown compiled module interface: no such module` until the standard library module has been built and its interface made available.
- **CMake's support has been experimental throughout the 3.28–4.x era.** CMake 3.30 introduced `CMAKE_CXX_MODULE_STD` and `CMAKE_CXX_COMPILER_IMPORT_STD`, gated behind experimental `import std` support; the gating mechanism itself has changed between CMake versions. On CMake 4.3.0 I could not get `import std;` building out of the box with the straightforward experimental flags.
- **Support is layered.** A compiler may support named modules while its standard library and build system still have incomplete or experimental support for the standard-library module.

The useful practical takeaway: treat `import std;` as a separate concern from ordinary C++20 named-module support. A toolchain can be fully capable of named modules and still not support `import std;` yet. Check the documentation for your exact compiler *and* standard-library versions before relying on it.

For new projects, `import std;` is worth experimenting with if your toolchain supports it. For existing projects, it can be adopted incrementally, one module at a time.

## Compiler, CMake, and IDE Compatibility

There are several separate questions when evaluating module readiness, and a "yes" on one does not imply "yes" on all:

- Does the compiler implement C++20 named modules?
- Does its standard library work well with modules (and with `import std;`)?
- Does the compiler support the specific module features you want (partitions, header units)?
- Does the build system (CMake *and* the chosen generator) support dependency scanning for your compiler?
- Does your IDE's language server understand module imports and rebuild dependencies?

The examples in this article were tested on my machine with the versions shown, using the Ninja generator, with a clean build and an incremental rebuild:

| Toolchain | Tested | Basic named modules | Interface partitions | `import std` |
|---|---|---|---|---|
| GCC + CMake + Ninja | 16.2.1 / 4.3.0 / 1.13.2 | Yes | Yes | Experimental / not working out of box |
| Clang + CMake + Ninja | not tested here | — | — | — |

Notes on the methodology, so the table means what it appears to mean:

- "Basic named modules" = a primary interface unit, a consumer, and—separately—a consumer with implementation units. Both built clean and incrementally.
- "Interface partitions" = interface partitions with inline definitions, re-exported via `export import` from the primary interface. Built clean and incremental.
- "Implementation partitions" are **not** listed as working—they fail due to the partition name uniqueness constraint (see the sharp-edge section above).
- `import std;` is marked experimental: libstdc++ ships the std module source, but it does not build out of the box with the tested CMake version.

Other ecosystem considerations:

- **IDE support** continues to vary. Language servers generally understand named modules now, but completion, navigation, and refactoring across module boundaries may lag behind their header-based equivalents.
- **Third-party libraries** are mostly header-based. Using modules with them requires a wrapper module or the global module fragment.
- **Package managers** are adding module support, but it is not the default.
- GCC's own documentation notes that its C++20 module implementation is still incomplete in places. The status improves with every release—check the release notes for your exact version rather than assuming support from the version number.

Modules can be a practical choice for greenfield projects when you control the compiler, standard library, build system, and IDE versions. For large existing codebases, gradual migration is usually more realistic.

## What Modules Do Not Solve

Modules are not a universal fix for C++ project complexity. A few things to keep in mind:

- **Build times can go either way.** For small projects, module compilation may be slower than header inclusion because the compiler must first produce a compiled module interface and the build system must manage a dependency graph. The potential benefit comes from avoiding repeated parsing and preprocessing of the same declarations across many translation units; how large the improvement is depends heavily on the dependency graph, compiler, and build structure. Measure it.
- **Macros are a different story.** Macros defined in traditional headers remain governed by the preprocessor and can still pollute any translation unit that includes those headers. In contrast, macros defined *inside a named module* are not exported to importers. Modules therefore significantly reduce macro leakage from your own module code, but they cannot make legacy headers' macros disappear.
- **Binary compatibility does not change.** Modules affect how you organize source code and what each translation unit sees, not the ABI. Shipping a shared library built with modules looks the same at the binary level as one built with headers.
- **You still need a build system that understands modules.** Modules require the build system to know the dependency graph between interface units, implementation units, partitions, and consumers—a harder problem than the header model, where each translation unit independently resolves its own includes. That is why generator support (Ninja, Visual Studio) and the `CXX_MODULES` file set matter.

## Takeaway

C++20 Modules replace the textual inclusion model with a compiled interface model. The concepts that matter in practice:

- An **interface unit** (`export module math;`) defines the public API; only `export`ed names are visible to importers.
- **Implementation units** (`module math;`) provide definitions and internal details; they are ordinary sources, not `CXX_MODULES` file-set entries.
- The **global module fragment** (`module;`) handles legacy includes and configuration preprocessing before the module purview.
- Legacy headers participate through one of three mechanisms: `#include` in the global module fragment, `#include` in the purview, or header-unit `import`.
- **Interface partitions** (`export module math:addition;`) organize a module's public interface; **implementation partitions** (`module math:addition;`) must use a unique partition name that does not duplicate an existing interface partition—otherwise the build fails due to a C++20 standard constraint.
- `import std;` is C++23, experimental across the ecosystem, and should be evaluated separately from named-module support.

The practical workflow: start with a single `.cppm` file in a `CXX_MODULES` file set, put accompanying implementation units in plain sources, use the **Ninja** generator, and let CMake handle the compilation ordering. Introduce partitions only once the interface genuinely needs them, and test them on your exact toolchain first.

Modules do not solve every problem—macros in legacy headers, binary compatibility, and build tools are still part of the picture. But where you control the toolchain, the explicit boundary between interface and implementation is a real improvement over the header model.

## Further Reading

- [C++20 Modules on cppreference](https://en.cppreference.com/w/cpp/language/modules) — the authoritative language reference for module declarations, partitions, and header units.
- [Modules in C++ (Microsoft docs)](https://learn.microsoft.com/en-us/cpp/cpp/modules-cpp) — practical guide from the MSVC team covering module design, build integration, and migration patterns.
- [Import CMake: The Experiment Is Over](https://www.kitware.com/import-cmake-the-experiment-is-over/) — Kitware's account of how CMake's module support evolved from experimental flags to the `CXX_MODULES` file set.
- [C++20 Modules in CMake with Visual Studio](https://devblogs.microsoft.com/cppblog/cpp20-modules-in-cmake-with-vs/) — Microsoft's walkthrough of module builds with CMake and MSVC.
- [CMake Discourse: C++20 Modules Update](https://discourse.cmake.org/t/c-20-modules-update/7330) — community discussion on the current state of CMake module support.
- [A First C++20 Module (Modernes C++)](https://www.modernescpp.com/index.php/cpp20-a-first-module/) — introductory tutorial walking through creating and using a named module.
- [A Short Tour of C++ Modules (video)](https://www.youtube.com/watch?v=nP8QcvPpGeM) — Daniela Engert's concise video tour of C++ module concepts and tooling.

*The complete project from this guide evolves a single module from a minimal setup to interface partitions and a library target with CMake and Ninja. Every example was compiled, linked, and run on GCC 16.2.1 / CMake 4.3.0 / Ninja 1.13.2.*