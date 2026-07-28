---
title: "Building a Linux Kernel Module in Pure x86 Assembly"
description: A small journey into writing a Linux kernel module entirely in x86-64 assembly, from first failed attempts to a working module on a modern Fedora kernel.
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

But there is another way.

What if we remove the compiler's help and write the entire module ourselves?

What if the only language between our code and the Linux kernel is x86-64 assembly?

We use the GNU assembler (GAS) for this — the same assembler the kernel build system already uses behind the scenes. The module is built with the kernel's kbuild system, so no external toolchain is needed.

That was a small challenge:

Create a Linux kernel module in pure x86 assembly, load it into a modern Fedora kernel, and make it print messages when it loads and unloads.

The final result is only a few lines of assembly.

There were a few bumps along the way.

The kernel rejected our module several times, and each failure revealed another hidden rule of kernel development.

This is a short story of every problem, every error message, and every lesson learned.

Everything in this post was tested on:

```
$ uname -r
7.1.4-204.fc44.x86_64

$ lsb_release -a
Distributor ID: Fedora
Description:    Fedora Linux 44 (Workstation Edition)
Release:        44
Codename:       n/a
```

---

<nav class="table-of-contents" markdown="1">
## Table of contents
{:.no_toc}

- TOC
{:toc}

</nav>

## The First Attempt: A Simple Assembly Module

The first idea was straightforward:

1. Create an assembly file.
2. Export `init_module` and `cleanup_module`.
3. Call `printk` to write messages into the kernel log.
4. Build with kbuild.
5. Insert with `insmod`.

The first version looked like this:

```asm
.intel_syntax noprefix

.extern printk

.section .modinfo
.asciz "license=GPL"
.asciz "description=Minimal assembly Linux kernel module"
.asciz "author=Daniel Petrovic"

.text

.globl asm_init
.type asm_init, @function

asm_init:
    lea rdi, [rip + msg_load]
    xor eax, eax
    call printk

    xor eax, eax
    ret
```

The code was simple.

The kernel was not impressed.

The build succeeded, but loading failed:

```sh
insmod: ERROR: could not insert module asm_module.ko: Invalid module format
```

Something was wrong inside the module.

Time to investigate.

## Problem 1: The .modinfo Disaster

The first clue appeared in the kernel log:

```
Only one .modinfo section must exist.
```

The problem was this:

```asm
.section .modinfo
```

A kernel module already receives metadata from the build system.

Normally, a C module does this:

```c
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Example module");
MODULE_AUTHOR("Author");
```

The kernel build system converts those macros into a `.modinfo` section automatically.

Our assembly module created another one.

The kernel saw:

```
.modinfo
.modinfo
```

and refused to load it.

The fix was to create exactly one metadata section:

```asm
.section .modinfo,"a"

.asciz "license=GPL"
.asciz "description=Minimal assembly Linux kernel module"
.asciz "author=Daniel Petrovic"
```

The `"a"` flag tells the assembler:

"This section contains allocated data."

## Problem 2: The Kernel Wants ELF Information

After fixing `.modinfo`, the build continued but `objtool` complained:

```
asm_init() is missing an ELF size annotation
asm_exit() is missing an ELF size annotation
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

For that, the ELF file needs to describe where functions start and end.

The missing piece was:

```asm
.size function_name, .-function_name
```

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

In short: certain AMD CPUs are vulnerable to [Speculative Return Stack Overflow (SRSO)](https://docs.kernel.org/admin-guide/hw-vuln/srso.html), where an attacker can poison the CPU's return address predictor to make the kernel leak data across privilege boundaries. The mitigation replaces every `ret` instruction with a jump to a "safe return" thunk (`__x86_return_thunk`) that forces the CPU to mispredict the return, neutralizing the attack. If you write kernel code in assembly, you must use the thunk too.

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

Now our module follows Fedora's security model.

## Problem 5: The printk Mystery

The goal was to print:

```
asm_module: loaded
asm_module: unloaded
```

The first attempt used:

```asm
.extern printk
```

and:

```asm
call printk
```

This was the natural choice.

Linux kernel code uses `printk()` everywhere.

But the module build failed:

```
ERROR: "printk" [asm_module.ko] undefined!
```

This was confusing.

The function exists.

The kernel uses it.

Why can our module not call it?

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

The name is `_printk`.

Not:

`printk`

The kernel prefixes many symbols with an underscore for assembly and linker-level callers. The first guess was simply using the wrong symbol name.

### Existing Symbol vs Exported Symbol

Kernel modules cannot call every function inside the kernel.

There is a difference between:

- function **exists** in the kernel
- function is **available** to modules

The kernel source may contain:

```c
void printk(...)
{
}
```

but modules can only use symbols exported with:

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
extern _printk
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

The symbol existed, but it was not available to our module in this configuration.

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

```asm
.intel_syntax noprefix

.extern _printk
.extern __x86_return_thunk


.section .modinfo,"a"

.asciz "license=GPL"
.asciz "description=Minimal assembly Linux kernel module"
.asciz "author=Daniel Petrovic"


.section .init.text,"ax"

.globl init_module
.type init_module,@function

init_module:

    lea rdi,[rip + msg_load]
    xor eax,eax
    call _printk

    xor eax,eax
    jmp __x86_return_thunk

.size init_module,.-init_module


.section .exit.text,"ax"

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

## Understanding the Final Code

### Selecting Intel Syntax

```asm
.intel_syntax noprefix
```

The GNU assembler normally uses AT&T syntax.

This switches to Intel style:

```asm
mov rax, rbx
```

instead of:

```asm
mov %rbx,%rax
```

### External Symbols

```asm
.extern __x86_return_thunk
```

Tells the assembler:

"This symbol exists somewhere else."

The kernel provides it.

```asm
.extern _printk
```

Requests the kernel logging function. Note the underscore prefix — this is the actual exported symbol name visible to modules.

### Module Metadata

```asm
.section .modinfo,"a"
```

Creates module information.

The kernel reads this when loading the module.

```asm
.asciz "license=GPL"
```

Adds a null-terminated string.

The kernel uses this to determine module licensing.

### Initialization Function

```asm
.section .init.text,"ax"
```

Places the initialization code into the init section.

After initialization, the kernel can free this memory.

```asm
.globl init_module
```

Makes the entry point visible.

```asm
.type init_module,@function
```

Marks the ELF symbol as a function.

```asm
lea rdi,[rip + msg_load]
```

Loads the message address into the first argument register.

The x86-64 calling convention passes the first argument in `rdi`.

```asm
xor eax,eax
```

Required before calling variadic functions like `_printk`.

```asm
call _printk
```

Writes the message into the kernel log.

```asm
jmp __x86_return_thunk
```

Returns using Fedora's protected return mechanism.

### Cleanup Function

The cleanup function is almost identical.

The kernel calls `cleanup_module` when `rmmod asm_module` is executed.

It prints:

```
asm_module: unloaded
```

and returns safely.

## What I learned

Writing a kernel module in pure assembly sounds like a small project. It is not.

Every step revealed something hidden about how the kernel actually works. The `.modinfo` section is not just metadata — it is a contract with the build system. The ELF size annotations are not optional — `objtool` needs them to verify stack correctness. The section attributes are not decorative — they tell the kernel how to map memory. And the return thunk is not a quirk — it is a security boundary that Fedora enforces.

The most humbling lesson was the `printk` mystery. The symbol exists. The kernel uses it. But modules cannot call it unless it is explicitly exported. And even then, the symbol name is `_printk`, not `printk`. This is the kind of detail that separates "I wrote some assembly" from "I wrote a kernel module."

If you want to understand how the Linux kernel really works, try writing a module without a compiler. You will fail. And in failing, you will learn more about kernel internals than any documentation could teach you.

---

*The complete module from this post is only 30 lines of assembly. Getting there took five rounds of kernel rejection and a lot of reading kernel log messages.*
