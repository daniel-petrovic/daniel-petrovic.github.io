---
title: "Destructor trap"
description: Why skipping a virtual destructor silently breaks unique_ptr<Base> but not shared_ptr<Base>, and what the constructor/destructor output tells you.
date: 2026-05-20 08:00:00 +0200
tags:
  - c++
  - smart-pointers
  - memory
---

Consider this small hierarchy:

```cpp
#include <iostream>
#include <memory>
using namespace std;

struct A {
    A()  { cout << "A"; }
    ~A() { cout << "B"; }
};

struct B : A {
    B()  { cout << "C"; }
    ~B() { cout << "D"; }
};
```

Construction order is always base-first, then derived. Destruction is the reverse: derived-first, then base. If everything goes right, creating and destroying a `B` object should print `AC` then `DB`.

The question is: does it? It depends entirely on *how* you manage the object.

## The raw pointer case

```cpp
A* obj = new B();
delete obj;
```

Output: `ACB`

`B` is constructed correctly (`AC`). But `delete obj` calls `~A` directly because `obj` is of static type `A*` and `~A` is not virtual. `~B` is **never called**. This is undefined behaviour.

Any resource `B` owns — file handles, memory, locks — leaks silently.

## The unique_ptr case

```cpp
unique_ptr<A> p = make_unique<B>();
```

Output: `ACB`

Same result. The default deleter for `unique_ptr<A>` calls `delete` on an `A*`. Without a virtual destructor the outcome is identical to the raw pointer case: `~B` is skipped, and the behaviour is undefined.

This surprises people because smart pointers are supposed to handle cleanup for you. They do — but they can only call the destructor that the *pointer type* resolves to. `unique_ptr<A>` does not remember that it was constructed from a `B*`.

## The shared_ptr case

```cpp
shared_ptr<A> p = make_shared<B>();
```

Output: `ACDB`

Both destructors run in the correct order. Why does this work without a virtual destructor?

`shared_ptr` stores a **type-erased deleter** in its control block at construction time. When you write `make_shared<B>()`, the control block captures a deleter that knows the concrete type is `B*` and will call `delete (B*)ptr` when the reference count reaches zero. The static type of the pointer (`A*`) is never consulted at destruction time.

This is sometimes called the *shared_ptr virtual destructor trick*, but it is really just a consequence of how `shared_ptr` is designed. `unique_ptr` does not carry a control block and therefore cannot do the same thing by default.

## Fixing the root cause: virtual destructor

The correct fix for polymorphic base classes is to declare the destructor virtual:

```cpp
struct A {
    A()          { cout << "A"; }
    virtual ~A() { cout << "B"; }
};
```

Now `delete obj`, `unique_ptr<A>`, and `shared_ptr<A>` all produce `ACDB`. The virtual dispatch resolves to `~B` first, which chains up to `~A`.

This is the rule stated in the C++ Core Guidelines and in Effective C++ (Item 7):

> Make destructors virtual in polymorphic base classes.

## Comparing the three cases side by side

| Usage | Output | `~B` called? | Notes |
|---|---|---|---|
| `A* obj = new B(); delete obj;` | `ACB` | No | Undefined behaviour |
| `unique_ptr<A> p = make_unique<B>();` | `ACB` | No | Undefined behaviour |
| `shared_ptr<A> p = make_shared<B>();` | `ACDB` | Yes | Works via type-erased deleter |
| Any of the above with `virtual ~A()` | `ACDB` | Yes | Correct in all cases |

## Giving unique_ptr the right deleter

If you cannot add a virtual destructor and still want `unique_ptr`, you can supply a custom deleter:

```cpp
auto deleter = [](A* p) { delete static_cast<B*>(p); };
unique_ptr<A, decltype(deleter)> p(new B(), deleter);
```

Output: `ACDB`

This works, but it couples the owner to the concrete type, which defeats most of the purpose of holding a base pointer. It is rarely the right design.

## The practical takeaway

- **Any polymorphic base class should have a virtual destructor.** This is the simple, universal rule.
- `shared_ptr` happens to handle the case safely through type erasure, but relying on that instead of declaring `virtual ~Base()` is obscure and fragile.
- `unique_ptr` does *not* protect you. It behaves exactly like a raw pointer in this regard.
- The compiler gives no warning for missing virtual destructors in many default configurations. The bug is silent.

If a class has at least one virtual function, add `virtual ~ClassName() = default;` and move on. The cost is one pointer per object for the vtable — almost always irrelevant. The cost of forgetting is undefined behaviour and resource leaks that are very hard to diagnose.
