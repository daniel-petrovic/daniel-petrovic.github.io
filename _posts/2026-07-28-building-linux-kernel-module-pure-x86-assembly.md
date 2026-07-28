---
title: "Building a Linux Kernel Module in Pure x86"
description: An exploration of what happens when the compiler abstraction is removed and a Linux kernel module is written directly in x86-64 assembly.
date: 2026-07-28 10:00:00 +0200
tags:
  - linux
  - kernel-modules
  - x86-assembly
  - kernel
---

Most Linux kernel modules are written in C.

The reasons are obvious:

- The kernel APIs are designed around C.
- Documentation assumes C.
- The build system naturally integrates with C.
- The compiler handles many low-level details for us.

There is another approach: remove the compiler-generated layer and interact with the kernel using only the interfaces visible at the binary level.

What if we remove the compiler-generated machinery and take responsibility for every detail ourselves?

What if the only language between your code and the Linux kernel is x86-64 assembly?

I used GAS (GNU Assembler) for this — the same assembler the kernel build system already uses behind the scenes. The module is built with the kernel's kbuild system, so no external toolchain is needed.

Although this experiment uses x86-64 as its host platform, the core lessons
apply to embedded Linux on ARM64 (AArch64) and RISC-V as well: ELF section
flags, symbol export tables, and build-time validation remain part of the
module contract. The exact `objtool` checks and security-thunk sequences
depend on the target architecture and kernel configuration.

The objective was simple to describe, but less simple to implement:

Create a Linux kernel module in pure x86 assembly, load it into a modern Fedora kernel, and make it print messages when it loads and unloads.

The final assembly implementation is surprisingly small, but the surrounding kernel contracts are where most of the complexity lives.

There were a few bumps along the way.

The kernel rejected several iterations of the module, and each failure revealed another hidden rule of kernel development.

This post documents the investigation process, the failures encountered, and the kernel mechanisms behind them.

Everything in this post was tested on:

<pre><code>$ uname -m
x86_64

$ uname -r
7.1.4-204.fc44.x86_64

$ lsb_release -a
Distributor ID: Fedora
Description:    Fedora Linux 44 (Workstation Edition)
Release:        44
Codename:       n/a

$ as --version | head -1
GNU assembler version 2.46.1-1.fc44

$ gcc --version | head -1
gcc (GCC) 16.1.1 20260515 (Red Hat 16.1.1-2)</code></pre>

---

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

- TOC
{:toc}

</nav>

## The First Attempt: A Simple Assembly Module

The initial implementation focused on the minimum required kernel interfaces:

1. Create an assembly file.
2. Export entry and exit points.
3. Call `printk` to write messages into the kernel log.
4. Build with kbuild.
5. Insert with `insmod`.

For a deeper look at what happens under the hood when you run `insmod`, see [Module Loading Internals](https://kernel-internals.org/modules/module-loading-internals/).

A kernel module is organized into ELF sections. The ones that matter for a minimal module:

| Section | Purpose |
|---------|---------|
| `.modinfo` | Null-separated key=value strings: `license`, `author`, `description`, `vermagic` |
| `.init.text` | Init code — freed after `mod->init()` returns |
| `.exit.text` | Cleanup code — kept until unload |

The first version looked like this:

```asm
.intel_syntax noprefix

.extern printk

.section .modinfo               # Module metadata
.asciz "license=GPL"
.asciz "description=Minimal assembly Linux kernel module"
.asciz "author=Daniel Petrovic"

.section .init.text

.globl init_module
.type init_module, @function
init_module:
    lea rdi, [rip + msg_load]  # RIP-relative: kernel modules are position-independent
    xor eax, eax
    call printk
    xor eax, eax
    ret

.globl cleanup_module
.type cleanup_module, @function
cleanup_module:
    lea rdi, [rip + msg_unload]
    xor eax, eax
    call printk
    ret

.section .rodata
msg_load:
    .asciz "asm_module: loaded\n"
msg_unload:
    .asciz "asm_module: unloaded\n"
```

Save the assembly as `asm_module.S` and place this `Makefile` beside it:

```make
obj-m += asm_module.o

KDIR := /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
```

The code was simple.

The kernel was not impressed.

The build succeeded, but loading failed:

```sh
insmod: ERROR: could not insert module asm_module.ko: Invalid module format
```

Something was wrong inside the module.

Time to investigate.

## Problem 1: How .modinfo Was Duplicated

The first clue appeared in the kernel log:

```
Only one .modinfo section must exist.
```

This was not because assembly modules must never define `.modinfo`. A pure
assembly module normally supplies its own metadata:

```asm
.section .modinfo
```

A C module usually produces the same kind of metadata through macros:

```c
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Example module");
MODULE_AUTHOR("Author");
```

Those macros emit `.modinfo` entries; kbuild does not automatically create
them for every assembly source file. It can, however, generate additional
module metadata such as `vermagic`.

In this build, the generated metadata and the assembly-supplied metadata did
not merge. The assembly section had no flags, while the generated section was
allocatable, so the final module contained two separate sections with the same
name:

The kernel saw:

```
.modinfo
.modinfo
```

and refused to load it.

The fix was to mark the assembly section allocatable so it was compatible with
the generated metadata and the linker combined the entries into one section:

```asm
.section .modinfo,"a"

.asciz "license=GPL"
.asciz "description=Minimal assembly Linux kernel module"
.asciz "author=Daniel Petrovic"
```

The `"a"` flag marks the section as allocatable, meaning it occupies memory in
the loaded object.

## Problem 2: The Kernel Wants ELF Information

After fixing `.modinfo`, the build continued but `objtool` complained:

```
init_module() is missing an ELF size annotation
cleanup_module() is missing an ELF size annotation
```

In normal assembly, this is perfectly valid:

```asm
function:
    mov eax, 1
    ret
```

The CPU understands it.

But the Linux kernel does more than execute code.

It analyzes code.

Tools like `objtool` inspect functions for:

- stack correctness
- security issues
- control flow problems

`objtool` relies on ELF symbol information to understand function boundaries.
Without size annotations, assembly-written functions may not contain enough
metadata for its analysis.

The missing piece was:

```asm
.size function_name, .-function_name
```

This is a GAS (GNU Assembler) directive that writes the function's size into
the ELF symbol table. The expression `.-function_name` subtracts the
function's start address (`.` is the current location counter,
`function_name` is where the function began). The result is the byte length
of the function, allowing `objtool` to determine its boundary.

Example:

```asm
.globl init_module
.type init_module,@function

init_module:
    xor eax,eax
    ret

.size init_module,.-init_module
```

Now the ELF metadata correctly describes the function.

## Problem 3: Wrong Section Attributes

The next warning:

```
unexpected non-allocatable section
```

The kernel organizes memory into sections.

Examples:

| Section | Purpose |
|---------|---------|
| `.init.text` | Code used during initialization |
| `.exit.text` | Code used during removal |
| `.rodata` | Read-only data |

Our assembly contained:

```asm
.section .init.text
```

but the assembler did not know it was executable memory.

The correct form:

```asm
.section .init.text,"ax"
```

Meaning:

- `a` = allocatable
- `x` = executable

For exit code:

```asm
.section .exit.text,"ax"
```

## Problem 4: Fedora's Return Protection

The next enemy was not caused by our code.

It came from the kernel configuration.

Fedora enables modern CPU security mitigations, including return thunk protection.

Modern x86 Linux kernels may enable return-thunk based mitigations for [speculative execution vulnerabilities](https://docs.kernel.org/admin-guide/hw-vuln/srso.html). These mitigations change the expected return sequence for kernel code, and `objtool` enforces the generated pattern. When they are enabled, kernel-generated code uses return thunks instead of direct `ret` instructions. The thunk provides the mitigation sequence required by the kernel configuration. Any kernel module written in assembly must follow the same convention.

`objtool` warned:

```
'naked' return found in MITIGATION_RETHUNK build
```

The normal assembly return:

```asm
ret
```

is not what the kernel expects anymore.

Instead, protected kernels use a return thunk:

```asm
jmp __x86_return_thunk
```

So the module imports it:

```asm
.extern __x86_return_thunk
```

and returns through it:

```asm
jmp __x86_return_thunk
```

Now the module follows the kernel's security model.

## Problem 5: The printk Mystery

The goal was to print:

```
asm_module: loaded
asm_module: unloaded
```

The first attempt assumed that the C-level API name `printk` was also the
link-visible symbol name:

```asm
.extern printk
```

and:

```asm
call printk
```

This was the natural choice.

Kernel code uses the `printk()` interface.

But the module build failed:

```
ERROR: "printk" [asm_module.ko] undefined!
```

This was confusing.

The interface exists.

The kernel uses it.

Why can the module not call it?

### Looking Inside the Running Kernel

The first thing to check was whether the symbol existed.

Linux exposes kernel symbols through:

```sh
cat /proc/kallsyms
```

Searching:

```sh
grep printk /proc/kallsyms | head
```

gave:

```
0000000000000000 t umip_printk.cold
0000000000000000 t printk_prot.cold
0000000000000000 t __warn_printk.cold
0000000000000000 t printk_store_execution_ctx.cold
0000000000000000 T __pfx__printk
0000000000000000 T _printk
0000000000000000 t __pfx_printk_kthreads_check_locked
0000000000000000 t printk_kthreads_check_locked
0000000000000000 T __pfx__printk_deferred
0000000000000000 T _printk_deferred
```

This answered one question:

On this kernel, the implementation symbol is `_printk`.

Not:

`printk`

`printk()` is a C function or macro interface, while `_printk` is an
implementation symbol. Normal external C modules should use `printk()` or
`pr_info()`, rather than call `_printk` directly. This pure-assembly
experiment has no C macro layer, so the implementation had to investigate the
underlying link-visible symbol. Whether it can be used still depends on kernel
exports.

On this kernel, `include/linux/printk.h` declares `_printk()` and defines
`printk` as a macro that ultimately calls it. Depending on the kernel
configuration, the macro may call `_printk` directly or wrap it with
additional indexing logic. Assembly does not run that C preprocessor mapping,
so it must use the symbol resolved for the target kernel.

The relevant definition is:

<pre><code>/*
 * See the vsnprintf() documentation for format string extensions over C99.
 */
#define printk(fmt, ...) printk_index_wrap(_printk, fmt, ##__VA_ARGS__)</code></pre>

### Existing Symbol vs Exported Symbol

Kernel modules cannot call every function inside the kernel.

There is a difference between:

- function **exists** in the kernel
- function is **available** to modules

The kernel source may expose a C-level interface, but modules can only use
symbols exported with:

```c
EXPORT_SYMBOL()
```

or:

```c
EXPORT_SYMBOL_GPL()
```

The module build system checks exported symbols during `modpost`.

So the chain is:

```
Assembly
    |
    v
referenced symbol
    |
    v
modpost checks exports
    |
    v
Module.symvers
    |
    v
Allowed or rejected
```

The assembly implementation had to target an exported kernel symbol rather
than the C source-level API. Seeing a symbol in `/proc/kallsyms` alone does not
establish that it is available to a module.

### Discovering Kernel Symbols

The debugging lesson was important.

When writing kernel assembly, do not guess symbols.

Investigate.

Useful commands:

```sh
grep function_name /proc/kallsyms
```

Shows whether the running kernel knows the symbol.

For module exports:

```sh
grep function_name /lib/modules/$(uname -r)/build/Module.symvers
```

Shows whether modules can use it.

The kernel itself is the source of truth.

## The Final Pure Assembly Module

After fixing the metadata, ELF information, sections, and return mechanism, the final structure looked like this:

Before calling `_printk`, `xor eax,eax` sets `AL` to zero. Under the x86-64
System V ABI, `AL` records the number of vector registers used for a variadic
call; this module passes none, so the required value is zero.

```asm
.intel_syntax noprefix

.extern _printk                     # Kernel symbol resolved from the running kernel
.extern __x86_return_thunk          # Return thunk selected by the kernel configuration

.section .modinfo,"a"               # "a" = allocatable
.asciz "license=GPL"
.asciz "description=Minimal assembly Linux kernel module"
.asciz "author=Daniel Petrovic"

.section .init.text,"ax"            # "ax" = allocatable + executable; kernel frees this after init
.globl init_module
.type init_module,@function
init_module:
    lea rdi,[rip + msg_load]        # RIP-relative: kernel modules are position-independent
    xor eax,eax                    # Required by x86-64 SysV ABI before variadic calls
    call _printk
    xor eax,eax                    # Return 0
    jmp __x86_return_thunk         # Protected return instead of bare ret
.size init_module,.-init_module

.section .exit.text,"ax"           # Exit code — called on rmmod
.globl cleanup_module
.type cleanup_module,@function
cleanup_module:
    lea rdi,[rip + msg_unload]
    xor eax,eax
    call _printk
    jmp __x86_return_thunk
.size cleanup_module,.-cleanup_module

.section .rodata,"a"
msg_load:
    .asciz "asm_module: loaded\n"
msg_unload:
    .asciz "asm_module: unloaded\n"
```

## Build, Load, and Verify

From the directory containing `asm_module.S` and the `Makefile`:

<pre><code>$ make
$ sudo insmod asm_module.ko
$ sudo dmesg | tail -n 1
[...] asm_module: loaded

$ sudo rmmod asm_module
$ sudo dmesg | tail -n 1
[...] asm_module: unloaded</code></pre>

`rmmod` takes the loaded module name, so omit the `.ko` suffix.

## The takeaway

Writing this module was less about avoiding C and more about exposing everything C normally hides: ELF metadata, section placement, symbol visibility, calling conventions, and kernel security constraints.

The compiler is not merely translating instructions. It is participating in a contract between your code, the linker, the loader, and the kernel.

Removing that layer makes those contracts visible.

Every problem in this post — the duplicate `.modinfo`, the missing ELF size annotations, the wrong section attributes, the return thunk, the `_printk` symbol — is something conventional C source and the kernel build system handle silently. Writing in assembly means handling all of it yourself.

---

*The complete module from this post is 30 lines of assembly. It was validated through five rounds of kernel rejection and careful reading of kernel log messages.*
