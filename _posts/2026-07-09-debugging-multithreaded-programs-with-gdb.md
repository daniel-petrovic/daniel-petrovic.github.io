---
title: Debugging multithreaded programs with GDB
description: A practical GDB workflow for multithreaded programs, with emphasis on thread apply all and on commands that GDB can run automatically for you.
date: 2026-07-09 08:00:00 +0200
tags:
  - gdb
  - debugging
  - c++
  - linux
  - threads
---

Debugging a single-threaded program is usually a matter of following one control flow. Debugging a multithreaded program is different: the bug may depend on timing, one thread may be blocked while another caused the real problem, and the thread where GDB stops is often not the most interesting one.

That is why a good multithreaded GDB workflow is less about stepping line by line and more about getting a quick whole-process view. The two features I reach for first are:

- `thread apply all`, to inspect every thread at once
- automatically executed GDB commands, so the debugger prints useful context without manual repetition

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

* TOC
{:toc}
</nav>

## Start with a debugger-friendly build

Before opening GDB, make sure the binary has debug information:

```sh
g++ -g -O0 -pthread main.cpp -o app
```

For real projects, `-Og` is often a better compromise than `-O0`, because it keeps debugging reasonable while preserving some optimization behavior:

```sh
g++ -g -Og -pthread main.cpp -o app
```

Then start GDB:

```sh
gdb ./app
```

If the program already runs and reproducing the issue takes time, attaching to a live process is often more practical:

```sh
gdb -p <pid>
```

## First commands I use in a threaded program

These are the basic commands that help you orient yourself:

```gdb
info threads
thread 3
bt
frame 0
up
down
```

- `info threads` shows all threads known to GDB.
- `thread 3` switches context to thread 3.
- `bt` prints the current thread's backtrace.

That is the normal per-thread workflow. The problem is that it does not scale well when ten or fifty threads are involved. That is where `thread apply all` becomes the high-value command.

## `thread apply all`: the fastest way to see the whole process

The single most useful command in multithreaded debugging is:

```gdb
thread apply all bt
```

This tells GDB:

1. iterate over every thread
2. make that thread current
3. run `bt`

The result is a backtrace for the entire process. When a program is hung, deadlocked, or "doing nothing", this is usually the first output worth looking at.

Typical uses:

```gdb
thread apply all bt
thread apply all bt full
thread apply all info locals
```

What these are good for:

- `thread apply all bt` gives a concise stack snapshot of every thread.
- `thread apply all bt full` also prints arguments and local variables for each frame, which is heavier but often useful once you have narrowed the issue down.
- `thread apply all info locals` is handy when every thread is stopped in roughly the same function and you want to compare local state.

If you suspect a deadlock, `thread apply all bt` often tells the story immediately:

- one thread is waiting in `pthread_mutex_lock`
- another thread holds the mutex and is blocked somewhere else
- worker threads are asleep on a condition variable
- the main thread is waiting in `join()`

That is much faster than manually switching thread by thread.

## A simple deadlock-oriented workflow

When a program appears frozen, a practical sequence is:

```gdb
set pagination off
info threads
thread apply all bt
```

Then look for patterns:

- several threads waiting on the same mutex or condition variable
- a thread stuck in I/O while others wait for it
- lock ordering issues, where thread A waits for a lock held by thread B while thread B waits for something thread A owns

If the backtraces are too short, rerun with:

```gdb
thread apply all bt full
```

## Automatically executed commands: let GDB do the repetitive work

In multithreaded debugging, manual repetition is expensive. You stop, type `info threads`, type `bt`, switch threads, and do it again. GDB can automate a lot of that.

There are a few mechanisms worth knowing.

## Breakpoint command lists

You can attach commands to a breakpoint so they run automatically whenever the breakpoint is hit.

Example:

```gdb
break work_queue.cpp:87
commands
  silent
  printf "queue state breakpoint hit\n"
  thread apply all bt 3
  continue
end
```

This creates a breakpoint that:

1. does not print the normal stop message because of `silent`
2. prints a short marker
3. shows a short backtrace for every thread
4. continues automatically

That is useful for intermittent timing bugs where you want a snapshot each time a hot path is reached, but you do not want to manually inspect the program every time.

You can also use breakpoint command lists without `continue`, which turns them into an automatic "print context when stopped here" mechanism.

## `hook-stop`: run commands every time execution stops

GDB supports user-defined hooks. One of the most useful is `hook-stop`, which runs whenever the inferior stops.

Example:

```gdb
define hook-stop
  echo \n--- stop ---\n
  info threads
  bt 5
end
```

Now every stop prints:

- a marker
- the thread list
- a short backtrace for the current thread

This is convenient when you are stepping through a race or when the program stops for many different reasons and you always want immediate context.

Be careful with this in large threaded programs: a very noisy `hook-stop` can flood the terminal quickly. Keep it short.

## Define your own commands

If you repeat the same multi-command sequence, wrap it in a custom GDB command:

```gdb
define tbt
  thread apply all bt
end

document tbt
Print a backtrace for all threads.
end
```

Now you can just run:

```gdb
tbt
```

This is especially nice for team debugging, because you can put shared helper commands in a GDB script and reuse them across sessions.

A slightly richer example:

```gdb
define snapshot
  echo \n=== thread snapshot ===\n
  info threads
  thread apply all bt 4
end
```

## Put reusable automation in a GDB script

If you want these commands every time, store them in a script file, for example `gdb-threads.gdb`:

```gdb
set pagination off
set print thread-events on

define tbt
  thread apply all bt
end

define snapshot
  echo \n=== thread snapshot ===\n
  info threads
  thread apply all bt 4
end

define hook-stop
  echo \n--- stop ---\n
  bt 3
end
```

Then load it with:

```sh
gdb -x gdb-threads.gdb ./app
```

This is often better than rebuilding your session by hand every time.

You can also place commands in `.gdbinit`, but I usually prefer an explicit project-local script for anything non-trivial because it is easier to version, share, and review.

## Log GDB output to a file

When you use commands such as `thread apply all bt full`, the output can be too large to inspect comfortably in the terminal. It is often better to log it to a file and read it afterward.

The basic commands are:

```gdb
set logging file gdb.log
set logging enabled on
thread apply all bt full
set logging enabled off
```

This tells GDB to write its command output to `gdb.log` instead of only showing it in the terminal.

A few related commands are useful:

```gdb
set logging overwrite on
set logging redirect on
show logging
```

- `set logging overwrite on` replaces the log file instead of appending to an old one.
- `set logging redirect on` sends output only to the file, which is useful when terminal noise gets in the way.
- `show logging` prints the current logging configuration.

For multithreaded debugging, a practical pattern is:

```gdb
set logging file thread-snapshot.log
set logging overwrite on
set logging redirect on
set logging enabled on
info threads
thread apply all bt full
set logging enabled off
```

That gives you a clean snapshot you can inspect in an editor, attach to a bug report, or compare with later runs.

You can combine logging with automated commands too. For example, in a GDB script:

```gdb
set logging file gdb.log
set logging overwrite on

define snapshot_to_file
  set logging enabled on
  echo \n=== thread snapshot ===\n
  info threads
  thread apply all bt 4
  set logging enabled off
end
```

Then a single `snapshot_to_file` command captures the current process state into a file without flooding the interactive session.

## One practical pattern: automatic snapshots on suspicious code

Suppose you suspect a race around a queue, a state machine, or a shared cache. You can combine a breakpoint command list with `thread apply all`:

```gdb
break queue.cpp:120
commands
  silent
  echo \n=== queue breakpoint ===\n
  thread apply all bt 2
  continue
end
```

This gives you repeated low-noise snapshots of all threads at exactly the point where shared state is touched.

That is often more useful than stopping once and then trying to reconstruct what happened earlier.

## A small command set worth memorizing

If I had to keep only a few threaded-debugging commands in muscle memory, they would be these:

```gdb
info threads
thread apply all bt
thread apply all bt full
set pagination off
define tbt
  thread apply all bt
end
```

And for automation:

```gdb
commands
  silent
  thread apply all bt 3
  continue
end
```

plus:

```gdb
define hook-stop
  info threads
  bt 5
end
```

## Final thought

When a multithreaded bug shows up, the hardest part is usually not "how do I inspect this one frame?" but "how do I get a useful whole-program picture quickly?" In GDB, `thread apply all` is the shortest path to that picture.

Once you pair it with automatically executed commands such as breakpoint command lists, `hook-stop`, and small custom commands, GDB becomes much better at capturing the state you actually care about instead of making you type the same inspection sequence over and over.
