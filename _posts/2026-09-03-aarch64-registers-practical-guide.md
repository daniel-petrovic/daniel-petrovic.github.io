---
title: "AArch64 Register Conventions: What Survives a Function Call—and Why"
description: A practical guide to caller-saved and callee-saved registers, argument passing, X30/LR, SIMD registers, and what the ABI—not the CPU—actually guarantees across a function call.
date: 2026-09-03 10:00:00 +0200
tags:
  - aarch64
  - arm
  - assembly
  - embedded
  - performance
---

What happens to a register when you call a function?

On AArch64, the answer isn't "the CPU saves it." When you call a function, the CPU doesn't look at a register table and decide what to preserve. `BL` doesn't know about caller-saved or callee-saved registers. Those are ABI rules imposed on software, not behavior baked into the hardware.

Once you understand that distinction, the rest of the calling convention becomes much easier to reason about: the ABI tells the caller and callee who is responsible for preserving what. That's why some registers are caller-saved, some are callee-saved, and why a register's ABI category says nothing about how long a particular value will live.

When you write C++ code, the compiler decides whether a value lives in a register, on the stack, or nowhere at all after optimization. But under the hood, most scalar arithmetic and logical operations operate on register operands - and understanding the calling convention can make the difference between code that runs and code that *performs*.

If you've ever looked at compiler output for AArch64 and wondered why the compiler chose specific registers for specific values, this post is for you.

## AArch64 vs ARM64: what's in a name?

**AArch64** is Arm's official name for the 64-bit execution state and instruction set architecture introduced with Armv8-A. **ARM64** is the colloquial term used in operating systems, toolchains, and developer communities (Linux refers to it as `aarch64` in kernel sources, Apple calls it `arm64`). They refer to the same thing. This post uses AArch64 to match the official architecture documentation, but you'll encounter both names in the wild.

## The big picture

AArch64 has 31 general-purpose registers (X0–X30), plus the special-purpose stack pointer SP and 32 128-bit SIMD/floating-point registers. That's a lot of registers - and beginners often see "32" in architecture documentation, so it's worth clarifying up front: there are 31 general-purpose registers, plus SP, which is a special-purpose register rather than an ordinary GPR (more on that later).

But not all registers are created equal. The calling convention - the set of rules that govern how functions pass arguments and return values - assigns specific roles to specific registers. Understanding this convention requires a key distinction that underpins everything else.

## Caller-saved vs callee-saved: the conceptual key

The ABI divides registers into two categories based on what happens across a function call:

- **Caller-saved** (also called *caller-clobbered*): The caller cannot assume these registers survive a call. If the caller needs a value in one of these registers after a call, it must save the value before the call and restore it afterward. The called function is free to overwrite them.

- **Callee-saved**: If the callee modifies one of these registers, it must save the original value and restore it before returning. The caller can safely assume these registers are preserved across the call.

Keep these names in mind as obligations, not characteristics:

- "Caller-saved" means the caller must protect a value if it needs it after a call.
- "Callee-saved" means the callee must restore the incoming value before returning if it modifies the register.

**Caller-saved and callee-saved are ABI properties, not hardware properties.** The processor does not enforce these conventions; they are rules that separately compiled functions agree to follow. The CPU is perfectly happy to let any function overwrite X19 - it's the calling convention that says "if you modify it, you must restore it before returning."

### A common misconception

A callee-saved register isn't inherently a "long-lived register." It is simply a register whose incoming value must survive a call if the callee modifies it. The compiler can put a short-lived value in X19, and it can put a long-lived value in X9 if that value doesn't cross a call. Register allocation is driven by liveness, register pressure, call boundaries, and cost models - not by which category a register falls into.

To make this precise, keep three separate concepts in mind:

- **Register volatility**: what happens to the register across a call (caller-clobbered vs callee-saved).
- **Value liveness**: whether a particular value is needed again later in the code.
- **Register allocation**: which physical register the compiler chooses for a value.

These are three different concepts. A register can be caller-clobbered while holding a long-lived value, provided no call occurs while that value is live. A callee-saved register can hold a short-lived value. "Callee-saved" describes the register's contract, not the lifetime of the value stored in it.

## Scope: what this article covers

This article focuses on the core AArch64 GPR and SIMD/FP register conventions used in ordinary AAPCS64 code. The current AAPCS64 also defines calling conventions for SVE and SME state - the Z0–Z31 scalable vector registers, P0–P15 predicate registers, the FFR, and the SME ZA/ZT0/FPMR state. These are outside the scope of this introduction.

## The calling-convention register map

Here's the calling-convention register map as a quick overview. We'll walk through each group in detail below - remember, the full reference table lives in the [cheat sheet](#practical-cheat-sheet) at the end:

- **X0–X7** — Caller-clobbered: integer/pointer arguments and results
- **X8** — Caller-clobbered: indirect result location
- **X9–X15** — Caller-clobbered: temporary/scratch
- **X16–X17** — Caller-clobbered: IP0/IP1, linker/veneer scratch
- **X18** — Platform-dependent: platform register or caller-clobbered
- **X19–X28** — Callee-saved: general-purpose preserved state
- **X29** — Callee-saved: frame pointer / general-purpose register
- **X30** — Special: link register
- **SP** — Callee-saved / special: stack pointer
- **V0–V7** — Caller-clobbered: FP/SIMD args and results
- **V8–V15** — Callee-saved, low 64 bits only: preserved FP/SIMD state
- **V16–V31** — Caller-clobbered: temporary FP/SIMD state
- **NZCV** — Undefined: condition flags

## X0–X7: arguments and results

X0–X7 are the primary general-purpose argument and result registers. For integer, pointer, and other appropriately classified arguments, the first eight argument-register slots use X0–X7 - note that "eight registers" does not necessarily mean "eight source-level arguments," because the AAPCS64 argument classification rules can cause arguments to be packed or passed differently. Floating-point and vector arguments normally go in V0–V7 instead, and aggregates can have more complex treatment depending on the ABI and argument types.

These registers are *caller-saved* (caller-clobbered). If a function wants to preserve their values across a call, it must save them itself. They aren't just arguments - they can also hold intermediate values between calls.

The following example is deliberately simplified to illustrate the calling convention; real compiler output will look different, but the register assignment principle is the same:

```asm
// Simplified illustration of argument passing
MOV     X0, #42        // first integer argument
MOV     X1, #100       // second integer argument
BL      my_function    // call - X0-X7 may be modified
// X0 contains the return value
```

This convention means that short, simple functions can be very efficient - no need to save and restore registers if you're just doing a quick computation.

## X8: indirect results

X8 is not an ordinary ninth argument register. It is specifically used by AAPCS64 to carry the address of caller-allocated storage when a function result is returned indirectly. For example, a result that cannot be returned in the normal result registers may use indirect result return — the caller allocates the result memory and passes its address in X8. There is no requirement for the callee to preserve X8, and X8 is not part of the normal argument sequence.

The caller never passes X8 as an explicit argument in source code - the compiler handles it automatically when the return type requires it:

```asm
// Simplified illustration of indirect result
// Caller has allocated storage for the result.
// X8 points to that storage.
BL      get_large_struct
// The result has been written to the caller-provided storage.
```

## X9–X15: caller-clobbered scratch registers

These are caller-clobbered registers available for any intermediate use. The important nuance: "caller-saved" doesn't mean "temporary" in the sense that they can only hold short-lived values. It means the caller cannot *assume* their values survive a call. A compiler may allocate a long-lived value to X9 if it can prove that no call occurs before the value is consumed - there's nothing in the ABI that prevents it.

```asm
// Simplified illustration of scratch register use
ADD     X9, X0, X1     // intermediate result
LSL     X10, X9, #3    // another intermediate
// X9 and X10 are caller-clobbered - a called function may overwrite them
```

## X16–X17: IP0/IP1 and linker scratch

X16 and X17 are known as IP0 and IP1 - intra-procedure-call scratch registers. They have a special relationship with the linker and dynamic loader. The current AAPCS64 explicitly says X16/X17 can be used by call veneers and PLT code.

The important consequence is that X16 and X17 are not safe places to keep values across calls. A linker-generated veneer or PLT sequence may use them even when the source-level callee doesn't. If you're writing hand-written assembly that calls external functions, treat these registers as clobbered.

## X18: platform register

X18 is the platform register. Its preservation and usage rules are defined by the platform ABI rather than by the base AAPCS64.

AAPCS64 says that a platform may reserve X18 for interprocedural state such as thread context. If the platform has no such requirement, X18 is an additional caller-saved register. Arm advises that platform-independent developers avoid X18 if possible.

For example, Windows reserves X18 for the Thread Environment Block (TEB), and in user mode it points to the TEB. Android reserves X18 for the Shadow Call Stack (SCS) pointer in hardened binaries - a security mechanism that keeps return addresses on a separate, protected shadow stack. Apple platforms assign their own role to X18 as well. Other platforms have their own rules, so don't assume X18 is freely available without checking the target ABI.

**Portable assembly rule**: don't use X18 unless you know the target platform ABI.

## X19–X28: callee-saved registers

These registers are *callee-saved* - if a function modifies any of them, it must save their original values and restore them before returning. This is the opposite of the caller-saved convention.

The nuance: "callee-saved" doesn't mean the callee *must* use these registers. It means if it *does* use them, it must preserve them. The compiler decides whether to allocate a value to a callee-saved register based on liveness analysis, register pressure, and cost models - not because the ABI mandates it.

If a function keeps a value live across calls, the compiler may choose a callee-saved register. The called function is then required to preserve that register, so the caller doesn't need to save the value around every individual call. The trade-off is that the callee may need to save and restore it in its own prologue and epilogue:

```asm
// One possible prologue/epilogue pattern; real compiler-generated
// prologues vary with frame layout, optimization level, unwind
// requirements, and security features.
my_function:
    STP     X29, X30, [SP, #-16]!    // save frame pointer and link register
    STP     X19, X20, [SP, #-16]!    // save callee-saved registers we'll use

    // Because this function modifies X19/X20,
    // it must restore their incoming values before returning.
    MOV     X19, X0                   // preserve first argument across calls
    MOV     X20, X1                   // preserve second argument across calls

    BL      some_other_function       // X19 and X20 survive this call
    // ...

    LDP     X19, X20, [SP], #16      // restore callee-saved registers
    LDP     X29, X30, [SP], #16      // restore frame pointer and link register
    RET
```

To see why this matters, compare the two paths for a value you need again after a call:

- Using caller-saved X9 means you must explicitly save the value before the call and restore it afterward.
- Using callee-saved X19 means the responsibility moves into the callee: if the current function itself needs to use X19, it saves it once in its prologue. But any function you call must also preserve X19, so your value survives.

That distinction is the heart of why the ABI has both classes. Values that remain live across calls are often good candidates for callee-saved registers, but the compiler may instead spill, recompute, or otherwise transform the value depending on its cost model.

## X29 and X30: frame pointer and link register

### X29: frame pointer

X29 is conventionally used as the frame pointer (FP) when a frame pointer is maintained. Optimized code may omit the frame pointer and use X29 as a general-purpose callee-saved register instead - this depends on compiler options (`-fno-omit-frame-pointer`), debugging and unwinding requirements, and platform rules.

### X30: link register

X30 is the link register (LR), and it gets a special role rather than a simple caller/callee classification. When `BL` (branch with link) executes, the CPU writes the return address into X30 before branching to the target. When the function returns with `RET`, it jumps to the address in X30.

The practical rule: a function that needs its incoming LR after making another call must preserve that LR. If a function makes another call, that call overwrites X30, so the function must save its incoming return address somewhere else - typically on the stack - if it still needs it to return.

A leaf function that makes no calls can often leave X30 untouched and return directly with `RET`, avoiding an LR save/restore.

When a frame pointer is used, X29 and X30 are commonly saved together.

### Pointer Authentication and X30 security

In modern AArch64 environments (iOS, macOS, and hardened Linux builds), you will often see X30 handled with two additional instructions: `PACIASP` and `AUTIASP`. These are part of Armv8.3-A Pointer Authentication (PAC), a hardware security feature designed to prevent Return-Oriented Programming (ROP) and stack-smashing attacks.

Because X30 holds the return address, an attacker who overwrites the saved X30 on the stack can hijack execution when the function returns. PAC solves this by signing the pointer in X30 using a secret key and the current stack pointer (SP) as context before pushing it to memory:

```asm
my_function:
    PACIASP                         // Sign X30 using A-key and SP
    STP     X29, X30, [SP, #-16]!   // Push frame pointer and signed X30

    // ... function body ...

    LDP     X29, X30, [SP], #16     // Restore signed X30 from stack
    AUTIASP                         // Authenticate X30 against SP
    RET                             // Return to verified address
```

- **`PACIASP` (prologue)**: Computes a cryptographic signature from the value in X30 and SP, inserting it into the normally-unused upper bits of X30.
- **`AUTIASP` (epilogue)**: Re-computes the signature using the current SP and validates X30. If the stack was corrupted and the saved X30 was modified, `AUTIASP` replaces the signature with an invalid address pattern. When `RET` then attempts to execute, the CPU triggers an immediate translation fault rather than jumping to malicious code.

Crucially for backward compatibility, `PACIASP` and `AUTIASP` execute as NOP instructions on legacy Armv8.0 hardware, so binaries built with PAC enabled can still run safely on older AArch64 processors.

## SP, XZR, and W registers

### SP: stack pointer

SP is a special architectural register rather than an ordinary GPR, and it is not interchangeable with X0–X30. The AAPCS64 requires the stack pointer to be 16-byte aligned at public interfaces, and also requires alignment whenever memory is accessed via SP. AArch64 imposes additional restrictions on how SP can be used by instructions.

Importantly, this 16-byte SP alignment isn't only an ABI convention. The CPU itself enforces an architectural SP Alignment Check whenever SP is used as the base register in a load or store: if SP isn't 16-byte aligned at such an access, the hardware raises an alignment fault regardless of what the ABI says. The ABI rule and the architectural rule work together - the calling convention keeps SP aligned so the hardware check never trips on ordinary code.

AAPCS64 groups SP with the callee-saved registers, but that doesn't mean the callee must restore the exact incoming SP value instruction-for-instruction. The useful rule is: a function must restore SP to the required value before returning, and SP must remain properly aligned.

### XZR: the zero register

XZR is the architectural zero register. Reads return zero; writes are discarded. Many instructions use register encoding 31 to mean either SP or XZR, depending on the instruction class: data-processing instructions treat encoding 31 as XZR, while memory instructions and branches treat it as SP.

There is therefore no X31 register you can use like X0–X30; encoding 31 is interpreted as SP or XZR depending on the instruction. This eliminates a common beginner question - there is no architectural X31 general-purpose register.

### W registers: the 32-bit view

Each X register also has a 32-bit W-register view. For example, W0 refers to the low 32 bits of X0.

A key AArch64 rule is that writing a W register zeroes the upper 32 bits of the corresponding X register:

```asm
MOV     W0, #42
// X0 is now 0x000000000000002A
```

This is worth remembering when reading compiler output: W0 and X0 aren't separate physical registers. You'll encounter `w0`, `w1`, and so on constantly in disassembly.

## SIMD and floating-point registers

The V0-V31 registers are 128-bit SIMD/vector registers that also serve as floating-point registers. The calling convention divides them similarly to the general-purpose registers.

Each V register has several aliases depending on the width you're accessing:

- **V0**: Full 128-bit register
- **Q0**: Same 128 bits (quadword)
- **D0**: Low 64 bits (doubleword)
- **S0**: Low 32 bits (singleword)
- **H0**: Low 16 bits (halfword)
- **B0**: Low 8 bits (byte)

### V0–V7: argument and return registers

These are the primary SIMD/floating-point argument and return registers. Like their general-purpose counterparts, they're *caller-clobbered*.

```asm
// Simplified illustration: assume S0 and S1 already contain the arguments
BL      my_float_func
// S0 (low 32 bits of V0) contains the return value
```

### V8–V15: partially preserved

Only the low 64 bits of V8–V15 (D8–D15) are callee-saved. That means: if a function modifies the bottom 64 bits of one of these registers, it must restore them before returning; larger values are the caller's responsibility. If you need a full 128-bit value to survive a call, you can't simply put it in V8–V15 and rely on the ABI - you must preserve the upper 64 bits yourself.

### V16–V31: temporary registers

These are fully caller-clobbered, like the general-purpose scratch registers. Use them for intermediate SIMD computations that don't need to survive function calls.

## Condition flags: NZCV

**NZCV** is the condition flags register. It holds four single-bit flags:

- **N** (Negative): Set to 1 if the result of the last operation was negative
- **Z** (Zero): Set to 1 if the result was zero
- **C** (Carry): Set to 1 if the last operation produced a carry out
- **V** (Overflow): Set to 1 if the last operation produced a signed overflow

NZCV is modified by flag-setting instructions such as `ADDS`, `SUBS`, `ANDS`, and by comparison instructions such as `CMP`, `CMN`, and `TST`. Ordinary arithmetic instructions such as `ADD` and `SUB` do not modify NZCV - you must explicitly use the flag-setting variant.

NZCV is not preserved across a function call; its values are undefined at a public interface. It's also ordinary scratch state within a function: any flag-setting instruction can replace the previous condition flags.

This matters for inline assembly: if your inline assembly modifies condition flags in a way the compiler must not assume is preserved, declare the appropriate `"cc"` clobber (in GCC/Clang extended inline assembly). Conversely, if your assembly reads condition flags, you need to ensure they've been set appropriately before your block.

```asm
// Simplified illustration of NZCV in inline asm
CMP     X0, #0          // flag-setting comparison: sets NZCV
B.NE    is_nonzero       // conditional branch based on Z flag
// ...
```

## What this looks like in compiler output

When you examine compiler output, these conventions explain the register allocation patterns you see. Compilers often use caller-clobbered registers for values that don't need to survive a call, because doing so avoids unnecessary save/restore work. Values that are live across call boundaries may end up in callee-saved registers, but the compiler may instead spill to the stack, recompute the value, or transform the code entirely - register allocation is driven by a cost model, not a simple rule.

Consider a concrete example:

```cpp
int bar(int);

int foo(int a, int b) {
    int x = a + b;
    return bar(x) + x;
}
```

`x` is live across the call to `bar()` - it's used again afterward. Therefore, the compiler needs some way to preserve its value across the call. It might use a callee-saved register, spill it to the stack, recompute it, or transform the expression. So conceptually:

- `a`, `b` → `x0`, `x1`
- `x` → may move to `x19`, because `x` is live across the call to `bar()`

A complete, valid implementation using a callee-saved register would also have to preserve the caller's incoming X19 in its prologue:

```asm
foo:
    STP     X19, X30, [SP, #-16]!     // preserve caller's X19 and our LR

    ADD     W19, W0, W1               // x = a + b, kept in W19
    MOV     W0, W19                   // pass x as the argument
    BL      bar                       // call - x survives in W19
    ADD     W0, W0, W19               // result + x

    LDP     X19, X30, [SP], #16       // restore X19 and LR
    RET
```

Note what this makes explicit: using a callee-saved register doesn't make the register free. It transfers the preservation responsibility to the current function, which must save and restore X19 around its own body. That's the heart of the distinction between the two classes.

Also notice how the stack is managed: `STP X19, X30, [SP, #-16]!` pushes *two* 64-bit registers at once (16 bytes total, hence the `#-16` offset), and `LDP` pops them back together. Storing registers in pairs of 64-bit registers is the standard AArch64 idiom - it's precisely how the code keeps SP moving in 16-byte units, maintaining the required alignment without extra padding. Because the pair takes exactly 16 bytes, the compiler never has to insert alignment holes.

The compiler can also use caller-saved registers for long-lived values when it can prove no call intervenes. "Caller-saved" describes what happens across calls, not how long a value lives.

## Writing inline assembly

With GCC/Clang-style extended inline assembly, ABI rules are only part of the contract. You must also tell the compiler which registers, memory, and condition flags your assembly modifies. An instruction sequence can obey the AArch64 ABI and still be invalid inline assembly if its clobbers and operands are incorrectly declared.

> **Important distinction**: in inline assembly the compiler - not your assembly code - is responsible for allocating registers around the asm block. This is fundamentally different from standalone assembly, where you own every register decision.

Specifically:

- Describe inputs, outputs, and clobbers using operands and constraints, allowing the compiler to allocate registers unless a specific register is genuinely required.
- Use the `"cc"` clobber if your assembly modifies condition flags.
- List any registers your assembly clobbers, or let the compiler allocate them via operand constraints.
- Declare memory effects if your assembly accesses memory the compiler doesn't know about.

Don't manually save a caller-saved register in inline asm just because it is caller-saved. Your job is to describe the inputs, outputs, and clobbers accurately. If you need a particular register preserved, model that requirement through operands/constraints rather than silently saving and restoring arbitrary registers.

If your asm modifies a register that the compiler has allocated for something else and you don't tell the compiler, you can break the program even though you didn't violate the ABI. This is the key distinction between standalone assembly and inline assembly embedded in compiler-generated code.

## AAPCS64 vs platform ABI

The register conventions described above come from the **Arm Procedure Call Standard for AArch64** (AAPCS64), which defines the core calling convention. But AAPCS64 is the base layer - not the whole story. The hierarchy looks like this:

```
AArch64 architecture
        ↓
    AAPCS64
        ↓
    platform ABI
        ↓
language/runtime/toolchain conventions
```

Every platform builds on AAPCS64 with its own **platform ABI** that adds rules specific to the operating system or runtime:

- **Linux / ELF**: AArch64 Linux user-space ABIs generally build on AAPCS64, with additional ELF and platform conventions. The exact ABI also depends on the toolchain and ABI variant being used.
- **Windows on AArch64**: Defines additional ABI rules, including reserving X18 for platform use and requiring specific unwind information.
- **Apple platforms**: Apple platforms build on AAPCS64 with additional platform and toolchain conventions. Apple platforms may also add security-related conventions such as pointer authentication, depending on the target and execution environment. If you're writing hand-written assembly, consult the ABI documentation for the specific Apple target rather than assuming that base AAPCS64 is the entire contract.

Beyond the platform ABI, C++ adds additional ABI requirements beyond plain C argument passing, and things like exception handling, TLS, unwind information, and toolchain-specific conventions can introduce further platform-specific rules.

The practical consequence: when writing hand-written assembly or inline assembly, you need to know not just the AAPCS64 register rules, but also the platform-specific additions. Code that works on one platform may break on another if platform-specific register conventions are violated.

## Practical cheat sheet

Here's the compact cheat sheet - the part you'll want to bookmark:

| Register | Across a call | Main purpose |
|----------|---------------|--------------|
| X0–X7 | ❌ | Arguments/results |
| X8 | ❌ | Indirect result address |
| X9–X15 | ❌ | Scratch |
| X16–X17 | ❌ | Linker/veneer scratch |
| X18 | Platform-dependent | Platform register or caller-clobbered |
| X19–X28 | ✅ | Callee-saved |
| X29 | ✅ | Frame pointer / callee-saved GPR |
| X30 | Special | Link register |
| SP | ✅ (special) | Stack pointer |
| V0–V7 | ❌ | FP/SIMD args/results |
| V8–V15 | ⚠️ | Low 64 bits callee-saved |
| V16–V31 | ❌ | FP/SIMD scratch |
| NZCV | ❌ | Condition flags; values are undefined across public interfaces |

## Conclusion

So what survives a function call?

- **X19–X29 survive**, because the callee must preserve them.
- **Only the low 64 bits of V8–V15 are guaranteed to survive.**
- **X0–X17 and V0–V7/V16–V31 are generally caller-clobbered.**
- **X30 must be preserved by a non-leaf function** if it needs its incoming return address.
- **NZCV is not something you can carry across a public call** - its values are undefined there.

But the deeper lesson is that the ABI describes register obligations, not value lifetimes. The compiler decides where a live value actually goes, choosing between callee-saved registers, spilling, or recomputation based on a cost model. And none of this is enforced by the hardware - it's a contract between separately compiled functions.

Next time you look at compiler output for AArch64, you'll know why certain registers are chosen and what happens to them across function boundaries.

## Official documentation and further reading

The ABI specification is a moving target - the current AAPCS64 is the 2025Q4 release, issued in January 2026. Link to the current Arm ABI repository rather than an old developer.arm.com PDF:

- [Arm ABI repository — AAPCS64](https://github.com/ARM-software/abi-aa) - The authoritative home of the current AAPCS64 and other Arm ABIs
- [Arm Architecture Reference Manual for AArch64](https://developer.arm.com/documentation/ddi0602/latest) - The authoritative source for the instruction set and register definitions
- [Arm System V ABI for AArch64](https://github.com/ARM-software/abi-aa/blob/main/sysvabi64/sysvabi64.rst) - The ELF/generic System V conventions that build on AAPCS64
- [Microsoft ARM64 ABI conventions](https://learn.microsoft.com/en-us/cpp/build/arm64-windows-abi-conventions) - Microsoft's platform-specific conventions, including X18 and unwind requirements
- [Apple Platform ABI for AArch64](https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms) - Apple's platform-specific conventions
- [Linux kernel AArch64 architecture](https://docs.kernel.org/arch/arm64/index.html) - Platform-specific details for Linux on AArch64
