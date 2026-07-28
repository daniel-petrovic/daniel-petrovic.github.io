---
title: "Building a Linux Kernel Module in Pure x86 Assembly"
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

The objective was simple to describe, but less simple to implement:

Create a Linux kernel module in pure x86 assembly, load it into a modern Fedora kernel, and make it print messages when it loads and unloads.

The final result is only a few lines of assembly.

There were a few bumps along the way.

The kernel rejected the module several times, and each failure revealed another hidden rule of kernel development.

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

The initial implementation focused on the minimum required kernel interfaces:

1. Create an assembly file.
2. Export `init_module` and `cleanup_module`.
3. Call `printk` to write messages into the kernel log.
4. Build with kbuild.
5. Insert with `insmod`.

For a deeper look at what happens under the hood when you run `insmod`, see [Module Loading Internals](https://kernel-internals.org/modules/module-loading-internals/).

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

## Problem 1: The Hidden .modinfo Constraint

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

This is a GAS (GNU Assembler) directive that writes the function's size into the ELF symbol table. The expression `.-function_name` subtracts the function's start address (`.` is the current location counter, `function_name` is where the function began). The result is the byte length of the function, which `objtool` and the kernel linker need to know where the function ends.

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

Modern x86 Linux kernels may enable return-thunk based mitigations for [speculative execution vulnerabilities](https://docs.kernel.org/admin-guide/hw-vuln/srso.html). These mitigations change the expected return sequence for kernel code, and `objtool` enforces the generated pattern. The normal `ret` instruction is replaced with a jump to a "safe return" thunk (`__x86_return_thunk`) that forces the CPU to mispredict the return. Any kernel module written in assembly must follow the same convention.

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

The name is `_printk`.

Not:

`printk`

The public kernel API is `printk()`, but the underlying kernel symbol involved in linking is `_printk`. Symbol visibility is controlled separately through kernel exports, so discovering a symbol in `/proc/kallsyms` does not mean it is available to loadable modules.

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

The symbol existed, but it was not available to the module in this configuration.

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

The public kernel API is `printk()`, but the linking symbol is `_printk`. This is the actual exported symbol name visible to modules.

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

Returns through the protected return thunk mandated by the kernel configuration.

### Cleanup Function

The cleanup function is almost identical.

The kernel calls `cleanup_module` when `rmmod asm_module` is executed.

It prints:

```
asm_module: unloaded
```

and returns safely.

## What I learned

Writing this module was less about avoiding C and more about exposing everything C normally hides: ELF metadata, section placement, symbol visibility, calling conventions, and kernel security constraints.

The compiler is not merely translating instructions. It is participating in a contract between your code, the linker, the loader, and the kernel.

Removing that layer makes those contracts visible.

Every problem in this post — the duplicate `.modinfo`, the missing ELF size annotations, the wrong section attributes, the return thunk, the `_printk` symbol — is something a C compiler handles silently. Writing in assembly means handling all of it yourself.

---

*The complete module from this post is 30 lines of assembly. It was validated through five rounds of kernel rejection and careful reading of kernel log messages.*
