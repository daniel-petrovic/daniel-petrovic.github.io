---
title: Memory types and their support in Linux
description: A practical overview of raw and managed flash memory technologies and how Linux handles each of them through the MTD and block subsystems.
date: 2026-05-18 10:00:00 +0200
tags:
  - linux
  - embedded
  - storage
  - memory
  - kernel
---

Linux supports a wide range of non-volatile memory technologies because they differ significantly in how data is stored, accessed, and managed. The main distinction is between raw flash memory and managed flash memory.

| Memory Type | Management | Random Access | Typical Uses | Linux Support |
|---|---|---|---|---|
| Raw NOR Flash | None | Excellent | Boot firmware, BIOS/UEFI, embedded code | MTD subsystem |
| Raw NAND Flash | None | Limited | Embedded storage, routers, IoT devices | MTD + UBI + UBIFS |
| SD Card | Internal controller | Good | Cameras, Raspberry Pi, removable storage | Block device (`/dev/mmcblk*`) |
| eMMC | Internal controller | Good | Phones, tablets, embedded Linux systems | Block device (`/dev/mmcblk*`) |
| USB Flash Drive | Internal controller | Good | Portable storage | Block device (`/dev/sd*`) |
| SSD (SATA/NVMe) | Internal controller | Excellent | PCs, servers | Block device (`/dev/sd*`, `/dev/nvme*`) |

## Raw NOR Flash

NOR flash memory cells can be read like ordinary memory (random access). Read performance is excellent, but write and erase operations are slow. Erases happen in sectors (e.g., 64 KB). NOR is relatively expensive per GB, offers lower storage density than NAND, and is very reliable for storing executable code.

**Advantages:** CPU can execute programs directly from flash (XIP: Execute In Place), simple architecture, high read reliability.

**Disadvantages:** Small capacities, high cost, slow writing.

**Typical use cases:** Bootloaders, firmware, BIOS/UEFI, automotive ECUs, industrial controllers.

```
CPU
 │
NOR Flash
 ├── Bootloader
 ├── Linux kernel
 └── Recovery firmware
```

Linux usually accesses raw NOR via the MTD (Memory Technology Device) subsystem.

## Raw NAND Flash

NAND flash is designed for maximum storage density. It is cheap, offers large capacity, but cannot randomly overwrite data. Pages must be erased in blocks. NAND chips contain bad blocks from manufacturing and wear out after many erase cycles.

Typical geometry: page size of 2–16 KB, block size of 128–512 pages.

```
Block
 ├─ Page 0
 ├─ Page 1
 ├─ Page 2
 └─ ...
```

**Advantages:** Very inexpensive, huge capacities, good sequential throughput.

**Disadvantages:** Needs software to handle bad block management, wear leveling, ECC (Error Correcting Codes), and garbage collection.

Linux therefore uses:

```
Applications
      ↓
 UBIFS
      ↓
 UBI
      ↓
 MTD
      ↓
 NAND Flash
```

**Typical use cases:** Routers, embedded Linux boards, IoT gateways, consumer electronics, smart TVs.

**Why NAND needs special software.** Suppose block 100 becomes defective. Without management, writing to block 100 fails. With Linux UBI, the system detects the bad block and uses block 278 instead. Applications never notice.

## SD Cards

An SD card is not raw flash. Inside the plastic package is NAND flash with a controller that handles wear leveling, ECC, and bad block management. The controller hides all flash complexity. Linux simply sees `/dev/mmcblk0` like a normal disk.

**Characteristics:** Removable, cheap, controller handles flash maintenance, uses FAT, ext4, etc.

**Typical use cases:** Cameras, Raspberry Pi, drones, portable devices.

## eMMC

eMMC is essentially an SD card permanently soldered onto a circuit board. Internally it is a controller with NAND flash. Linux still sees a normal block device: `/dev/mmcblk0`.

**Advantages:** Reliable, compact, no removable connector, low cost.

**Typical use cases:** Smartphones, tablets, embedded Linux boards, industrial computers.

## USB Flash Drives

USB flash drives also contain a controller paired with NAND flash. Linux detects them as `/dev/sda` or `/dev/sdb`.

**Characteristics:** Portable, plug-and-play, managed internally.

**Typical use cases:** File transfer, bootable Linux installers, backups.

## SSDs (SATA/NVMe)

An SSD is also managed flash. The controller performs wear leveling, ECC, garbage collection, bad block replacement, TRIM support, and over-provisioning. Linux simply uses ordinary file systems like ext4, XFS, or Btrfs.

**Typical use cases:** Desktop operating systems, databases, servers, virtual machines.

## Raw Flash vs Managed Flash

The key difference is where flash management happens.

**Raw flash** — Linux is responsible for wear leveling, ECC, bad block management, and garbage collection. Used in embedded systems.

**Managed flash** — The controller is responsible. Linux simply reads and writes sectors, just like with a hard disk.

```
Linux
 │
Filesystem
 │
Block device
 │
Controller
 │
Flash chips
```

## Why Linux Has Two Different Storage Subsystems

Raw flash behaves fundamentally differently from a traditional disk, which is why Linux has two separate storage subsystems.

**MTD subsystem** — used for raw flash devices (NOR, NAND). Provides direct access to erase blocks and flash-specific operations.

**Block subsystem** — used for managed flash devices (SD cards, eMMC, USB flash drives, SSDs). These devices emulate a conventional block storage device, so Linux interacts with them through the standard block layer.

## Summary

- **Raw NOR Flash:** Fast random reads, supports execute-in-place, ideal for boot firmware and embedded code; Linux uses the MTD subsystem.
- **Raw NAND Flash:** High-capacity and low-cost storage, but requires software for wear leveling, bad block management, and error correction; Linux commonly uses MTD together with UBI and UBIFS.
- **SD Cards:** Removable managed flash with an onboard controller; widely used in cameras and development boards such as the Raspberry Pi; exposed as block devices.
- **eMMC:** Soldered managed flash with an onboard controller; common in phones and embedded systems; exposed as block devices.
- **USB Flash Drives:** Portable managed flash storage connected via USB; appear as standard block devices.
- **SSDs:** High-performance managed flash with sophisticated controllers for wear leveling and garbage collection; used in PCs and servers and accessed through the standard block storage interface.

The essential distinction is that raw flash requires the operating system to manage the physical characteristics of flash memory, whereas managed flash contains an embedded controller that hides those details and presents the device as a conventional disk.
