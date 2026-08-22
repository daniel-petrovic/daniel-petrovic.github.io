---
title: "Implementing a std::vector-style container in C99"
description: Building a typed, growable contiguous array in C99 with macros, realloc, and a deliberately small API inspired by std::vector.
date: 2026-08-21 12:45:00 +0200
tags:
  - c
  - c99
  - stl
  - memory-management
---

`std::vector` is one of those C++ facilities that feels obvious until you try to rebuild its useful core without templates, constructors, or destructors.

The implementation in my [linux-system-playground](https://codeberg.org/daniel-petrovic/linux-system-playground/src/branch/main/stl/std_vector.h) is a small C99-style, typed dynamic array. It is not an STL implementation--and it does not try to be one. Its purpose is to expose the machinery that makes a vector useful: contiguous storage, a logical size, allocated capacity, and controlled reallocation.

I first looked what is available out there and found [Gena library](https://github.com/cher-nov/Gena). Although it looks very advanced, I don't quite like its cumbersome interface and macro-meta-setup machinery needed. I rather prefer simplistic design (for simple use cases) and tried to build up the simplest possible working solution. Something the kind of a 2 step approach:

- Declare
- Use

---

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

- TOC
{:toc}

</nav>

## The three pieces of state

A vector needs to distinguish how many elements it contains from how much storage it owns:

```c
type *data_;
size_t size_;
size_t capacity_;
```

`data_` points to one contiguous allocation. `size_` is the number of elements the caller may read. `capacity_` is the number of elements that fit before the allocation must grow.

That distinction is the whole reason a vector can append efficiently. Allocating exactly enough storage on every growth operation would turn repeated appends into repeated copies. Instead, the container allocates some spare room and reuses it until it fills up.

## Replacing templates with macros

C has no templates, so a generic `vector<T>` has to choose a different trade-off. This implementation uses macros to generate a concrete vector type and its operations for each element type:

```c
std_vector_define(int);

int main(void)
{
    std_vector(values, int);

    values.resize(&values, 3);
    *values.at(&values, 0) = 10;
    *values.at(&values, 1) = 20;
    *values.at(&values, 2) = 30;

    values.clear(&values);
}
```

`std_vector_define(int)` expands into a `std_vector_int` structure plus functions such as `std_vector_int_resize`. `std_vector(values, int)` declares a `std_vector_int` named `values` and initializes it.

The generated structure stores function pointers as well:

```c
typedef struct std_vector_int {
    int *data_;
    size_t size_;
    size_t capacity_;

    size_t (*size)(struct std_vector_int *vec);
    size_t (*capacity)(struct std_vector_int *vec);
    bool (*reserve)(struct std_vector_int *vec, size_t new_capacity);
    int *(*data)(struct std_vector_int *vec);
    void (*resize)(struct std_vector_int *vec, size_t new_size);
    int *(*at)(struct std_vector_int *vec, size_t index);
    void (*clear)(struct std_vector_int *vec);
} std_vector_int;
```

This gives the call site an object-like spelling--`values.resize(&values, 3)`--rather than requiring callers to spell the generated free-function name. The cost is one function-pointer indirection and a larger vector object. In ordinary C I would often prefer direct functions, but here the indirection makes the experiment easier to read.

## Starting empty

An empty vector owns no allocation:

```c
void std_vector_int_init(struct std_vector_int *vec)
{
    vec->data_ = NULL;
    vec->size_ = 0;
    vec->capacity_ = 0;

    vec->size = std_vector_int_size;
    vec->capacity = std_vector_int_capacity;
    vec->reserve = std_vector_int_reserve;
    vec->data = std_vector_int_data;
    vec->resize = std_vector_int_resize;
    vec->at = std_vector_int_at;
    vec->clear = std_vector_int_clear;
}
```

`NULL` is a valid value to pass to `realloc`, so the first allocation does not need a special allocator path. The zero capacity also gives `resize` a clean base case: the first requested element grows the allocation to one element.

## Reserving storage

`reserve` is the non-destructive allocation primitive. It grows only when the requested capacity exceeds the capacity already owned:

```c
bool std_vector_int_reserve(struct std_vector_int *vec,
                            size_t new_capacity)
{
    if (new_capacity > vec->capacity_) {
        int *new_data = realloc(vec->data_,
                                new_capacity * sizeof(int));
        if (!new_data) {
            return false;
        }

        vec->data_ = new_data;
        vec->capacity_ = new_capacity;
    }

    return true;
}
```

The temporary `new_data` matters. If `realloc` fails, it returns `NULL` and leaves the old allocation valid. Assigning its result directly to `vec->data_` would lose the only pointer to that allocation.

Notice that `reserve` does not change `size_`: it creates room, not elements. That is also the important semantic distinction in C++.

## Growing geometrically

`resize` changes the logical number of elements. When it needs more room, it doubles the capacity until the requested size fits:

```c
void std_vector_int_resize(struct std_vector_int *vec, size_t new_size)
{
    if (new_size > vec->capacity_) {
        size_t new_capacity = vec->capacity_ == 0
                                  ? 1
                                  : vec->capacity_ * 2;

        while (new_capacity < new_size) {
            new_capacity *= 2;
        }

        int *new_data = realloc(vec->data_,
                                new_capacity * sizeof(int));
        if (!new_data) {
            fprintf(stderr, "Memory allocation failed\n");
            exit(EXIT_FAILURE);
        }

        vec->data_ = new_data;
        vec->capacity_ = new_capacity;
    }

    vec->size_ = new_size;
}
```

For one growth from 0 to 1, then 1 to 2, 2 to 4, and so on, a resize that requires storage occasionally moves the whole array. But it does not move it on every call. Across many one-element growth operations, the total copying work is linear, so each growth is **amortized O(1)**.

There is an intentional policy difference between the two allocation APIs. `reserve` returns `false`, letting its caller decide how to recover. `resize` treats allocation failure as fatal and terminates. A production container should normally choose one consistent error model; this split makes the two possible C interfaces visible.

## Accessing the contiguous array

The `data` operation exposes the underlying array directly:

```c
int *std_vector_int_data(struct std_vector_int *vec)
{
    return vec->data_;
}
```

That makes the vector compatible with APIs that accept a pointer and length:

```c
consume(values.data(&values), values.size(&values));
```

`at` adds a bounds check:

```c
int *std_vector_int_at(struct std_vector_int *vec, size_t index)
{
    if (index >= vec->size_) {
        return NULL;
    }

    return &vec->data_[index];
}
```

Returning a pointer lets the caller both read and write an element. It also gives an explicit out-of-range result, unlike `operator[]` in C++ or raw array indexing.

## Releasing the allocation

The final operation is simple, but it is the one callers must not forget:

```c
void std_vector_int_clear(struct std_vector_int *vec)
{
    free(vec->data_);
    vec->data_ = NULL;
    vec->size_ = 0;
    vec->capacity_ = 0;
}
```

`free(NULL)` is defined to do nothing, so this is safe on an empty vector. Resetting all three fields makes `clear` idempotent and leaves the object in the same usable state as after initialization.

This is closer to destroying a C++ vector than to `std::vector::clear()`: the latter keeps its allocation and merely destroys its elements. The naming is convenient for the experiment, but the ownership behavior is worth calling out.

## Where the analogy ends

The implementation is intentionally small, which means it has constraints that a real reusable container must address:

| Concern | This implementation |
|---|---|
| Element lifetime | Appropriate for plain values such as `int`; it cannot construct, copy, or destroy resource-owning elements. |
| Initialization | Growing `size_` does not initialize new storage. Callers must write every newly exposed element before reading it. |
| Pointer stability | A successful `realloc` may move the allocation, invalidating pointers returned by `data` or `at`. |
| Integer overflow | `new_capacity * sizeof(type)` and repeated doubling need checked arithmetic in production code. |
| `realloc(..., 0)` | The implementation avoids it through its growth path, but a general-purpose reserve API should define its zero-capacity behavior deliberately. |
| Header linkage | Macro-generated function definitions belong in one translation unit per generated type, or should be made `static`, to avoid multiple definitions. |

There is also no `push_back`, but it falls directly out of the existing API:

```c
size_t next = values.size(&values);
values.resize(&values, next + 1);
*values.at(&values, next) = 42;
```

That sequence exposes the real primitive behind a vector append: ensure capacity, extend the valid range, then place the new value into contiguous storage.

## Takeaway

The C99 version is small because a dynamic array is fundamentally small. The interesting parts are not the syntax borrowed from `std::vector`; they are the invariants:

- `0 <= size_ <= capacity_`
- `data_` points to storage for `capacity_` elements, or is `NULL` when capacity is zero
- only the first `size_` elements are valid for callers to read
- any operation that can move storage invalidates derived pointers

C++ templates, allocators, iterators, exception guarantees, and object lifetime rules turn those ideas into a complete standard-library container. Stripping them away in C makes the underlying model much easier to see--and makes it equally clear why the complete version is substantially more complicated.
