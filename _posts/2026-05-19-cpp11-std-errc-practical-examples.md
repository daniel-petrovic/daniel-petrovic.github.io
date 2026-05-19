---
title: Practical C++11 std::errc with real examples
description: A practical C++11 guide to std::errc, std::error_code, and portable error handling with examples for files, validation, retries, and API design.
date: 2026-05-19 10:30:00 +0200
tags:
  - c++
  - error-handling
  - systems
---

In C++11, **`std::errc`** gives you a standard set of error conditions such as:

- `std::errc::invalid_argument`
- `std::errc::no_such_file_or_directory`
- `std::errc::permission_denied`
- `std::errc::timed_out`
- `std::errc::resource_unavailable_try_again`

It matters because it lets you talk about **portable error meaning** instead of comparing platform-specific integer codes directly.

The usual flow is:

1. an operation fails,
2. you store the failure in `std::error_code`,
3. and you compare it against `std::errc`.

## `std::errc` in one sentence

Think of **`std::errc` as a vocabulary of common system-style failures**.

It is not meant to replace every domain-specific error, but it is a very good fit when your code needs to express familiar conditions like:

- missing files,
- bad input,
- timeouts,
- address already in use,
- broken pipes,
- or "try again later".

## The basic pattern

```cpp
#include <system_error>
#include <iostream>

int main() {
    std::error_code ec = std::make_error_code(std::errc::permission_denied);

    if (ec == std::errc::permission_denied) {
        std::cout << "permission problem: " << ec.message() << '\n';
    }
}
```

That comparison works because the standard library knows how to compare an `std::error_code` with an `std::errc` value.

## Example 1: reporting file-open failures cleanly

One practical use case is wrapping file operations and returning an `std::error_code` instead of throwing.

```cpp
#include <cerrno>
#include <cstdio>
#include <string>
#include <system_error>

std::error_code read_config(const std::string& path) {
    FILE* file = std::fopen(path.c_str(), "r");
    if (!file) {
        return std::error_code(errno, std::generic_category());
    }

    std::fclose(file);
    return {};
}
```

Usage:

```cpp
std::error_code ec = read_config("/etc/my-app.conf");

if (ec == std::errc::no_such_file_or_directory) {
    // Use defaults on first startup.
} else if (ec == std::errc::permission_denied) {
    // Tell the user to fix file permissions.
} else if (ec) {
    // Log unexpected I/O problem.
}
```

This is where `std::errc` is genuinely useful:

- your calling code stays readable,
- you avoid magic numbers,
- and you do not hardcode Linux-specific `errno` values into business logic.

## Example 2: validating user input in a parser

`std::errc` is also useful outside OS calls when the failure still matches a standard condition.

```cpp
#include <limits>
#include <string>
#include <system_error>

std::error_code parse_port(const std::string& text, int& port) {
    try {
        size_t pos = 0;
        int value = std::stoi(text, &pos);

        if (pos != text.size()) {
            return std::make_error_code(std::errc::invalid_argument);
        }

        if (value < 1 || value > 65535) {
            return std::make_error_code(std::errc::result_out_of_range);
        }

        port = value;
        return {};
    } catch (const std::invalid_argument&) {
        return std::make_error_code(std::errc::invalid_argument);
    } catch (const std::out_of_range&) {
        return std::make_error_code(std::errc::result_out_of_range);
    }
}
```

Usage:

```cpp
int port = 0;
std::error_code ec = parse_port("70000", port);

if (ec == std::errc::invalid_argument) {
    // Input was not a number at all.
} else if (ec == std::errc::result_out_of_range) {
    // Number existed, but was outside the allowed range.
}
```

This is a good example of using `std::errc` as an **API contract**.

The caller learns what kind of failure happened without needing exceptions or custom enums for very common cases.

## Example 3: retrying temporary failures

Another real use case is retry logic.

Some failures are not final errors. They mean:

> "not now, try again shortly"

That maps nicely to `std::errc::resource_unavailable_try_again`.

```cpp
#include <system_error>

std::error_code try_send_message();

std::error_code send_with_retry() {
    for (int attempt = 0; attempt < 3; ++attempt) {
        std::error_code ec = try_send_message();
        if (!ec) {
            return {};
        }

        if (ec != std::errc::resource_unavailable_try_again) {
            return ec;
        }

        // sleep, backoff, or yield here
    }

    return std::make_error_code(std::errc::resource_unavailable_try_again);
}
```

Typical situations:

- a non-blocking socket would block,
- a queue is temporarily full,
- a lock-free structure asks the caller to retry,
- or a service is momentarily overloaded.

The key benefit is that your retry code depends on **meaning**, not on a specific platform error number.

## Example 4: timeout handling

Timeouts are another case where `std::errc` makes code easier to read.

```cpp
#include <system_error>
#include <iostream>

std::error_code wait_for_reply();

void handle_request() {
    std::error_code ec = wait_for_reply();

    if (ec == std::errc::timed_out) {
        std::cerr << "request timed out\n";
        return;
    }

    if (ec) {
        std::cerr << "request failed: " << ec.message() << '\n';
        return;
    }

    std::cout << "request completed\n";
}
```

That is much more expressive than checking whether `ec.value() == 110` or some other platform-specific number.

## Example 5: custom APIs that still feel standard

A very practical design pattern is:

- return `std::error_code`,
- use `std::errc` for common failures,
- reserve custom error categories only for truly domain-specific cases.

```cpp
#include <system_error>
#include <string>

std::error_code save_user_name(const std::string& name) {
    if (name.empty()) {
        return std::make_error_code(std::errc::invalid_argument);
    }

    if (name.size() > 64) {
        return std::make_error_code(std::errc::result_out_of_range);
    }

    // pretend persistence failed
    bool disk_full = false;
    if (disk_full) {
        return std::make_error_code(std::errc::no_space_on_device);
    }

    return {};
}
```

That gives the caller a familiar, reusable error model:

```cpp
std::error_code ec = save_user_name("");
if (ec == std::errc::invalid_argument) {
    // show validation error in UI
}
```

This is often enough for command-line tools, services, config loaders, and system utilities.

## When `std::errc` is a good choice

Use it when the error is already a well-known low-level condition:

- invalid input,
- file not found,
- permission denied,
- connection refused,
- timeout,
- not enough memory,
- no space left on device.

It works especially well for:

- wrappers around POSIX-style APIs,
- non-throwing utility functions,
- retry loops,
- service boundaries returning `std::error_code`,
- and validation paths that map naturally to standard conditions.

## When `std::errc` is not enough

Do **not** force everything into `std::errc`.

If your domain has errors like:

- `user_already_invited`,
- `subscription_expired`,
- `order_cannot_be_cancelled`,
- `schema_version_mismatch`,

then a custom error category or a domain-specific error type is usually better.

`std::errc` is best for **common infrastructure-level failure meanings**, not for every business rule.

## A small but important detail: use the generic category

When converting `errno`-style values, this is the usual form:

```cpp
std::error_code(errno, std::generic_category())
```

That is important because `std::errc` comparisons are based on **portable generic error conditions**.

If you bypass that mapping carelessly, your comparisons may become less useful across platforms.

## Final thought

The most practical way to think about `std::errc` is this:

**it gives your code a standard language for ordinary failures**.

That makes code easier to read, easier to test, and easier to move between platforms. In real code, its sweet spot is simple and common: file errors, validation failures, retries, timeouts, and API boundaries that return `std::error_code` instead of throwing.
