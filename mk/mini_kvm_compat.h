/*
 * mk/mini_kvm_compat.h: drop-in replacement for kvikdos/mini_kvm.h when
 * building kvikdos-soft (software CPU, -U__linux__) on a Linux host.
 *
 * Problem: mini_kvm.h's non-Linux path does
 *   typedef uint64_t __u64;
 * but on x86-64 Linux, uint64_t = unsigned long while Linux kernel headers
 * (pulled in transitively by <sys/stat.h>) define __u64 = unsigned long long.
 * That mismatch causes a "conflicting types" error.
 *
 * Fix: use concrete integer types matching the Linux kernel definitions.
 * This file is injected via -include before any source, and its MINI_KVM_H
 * guard prevents the real mini_kvm.h from being included again.
 */

#ifndef MINI_KVM_H
#define MINI_KVM_H

#include <stdint.h>

/* Use Linux kernel-compatible concrete types (no uint64_t alias). */
typedef unsigned char  __u8;
typedef unsigned short __u16;
typedef unsigned int   __u32;
typedef unsigned long long __u64;  /* matches linux/types.h on all arches */

/* Architectural interrupt line count. */
#define KVM_NR_INTERRUPTS 256

/* --- Struct definitions (portable, used by both KVM and software CPU) --- */

struct kvm_regs {
        __u64 rax, rbx, rcx, rdx;
        __u64 rsi, rdi, rsp, rbp;
        __u64 r8,  r9,  r10, r11;
        __u64 r12, r13, r14, r15;
        __u64 rip, rflags;
};

struct kvm_segment {
        __u64 base;
        __u32 limit;
        __u16 selector;
        __u8  type;
        __u8  present, dpl, db, s, l, g, avl;
        __u8  unusable;
        __u8  padding;
};

struct kvm_dtable {
        __u64 base;
        __u16 limit;
        __u16 padding[3];
};

struct kvm_sregs {
        struct kvm_segment cs, ds, es, fs, gs, ss;
        struct kvm_segment tr, ldt;
        struct kvm_dtable gdt, idt;
        __u64 cr0, cr2, cr3, cr4, cr8;
        __u64 efer;
        __u64 apic_base;
        __u64 interrupt_bitmap[(KVM_NR_INTERRUPTS + 63) / 64];
};

/* for KVM_RUN, returned by mmap(vcpu_fd, offset=0) on Linux.
 * On non-Linux, allocated as a plain struct for software CPU exit info. */
__extension__ struct kvm_run {
	/* in */
	__u8 request_interrupt_window;
	__u8 immediate_exit;
	__u8 padding1[6];

	/* out */
	__u32 exit_reason;
	__u8 ready_for_interrupt_injection;
	__u8 if_flag;
	__u16 flags;

	/* in (pre_kvm_run), out (post_kvm_run) */
	__u64 cr8;
	__u64 apic_base;

	union {
		/* KVM_EXIT_UNKNOWN */
		struct {
			__u64 hardware_exit_reason;
		} hw;
		/* KVM_EXIT_FAIL_ENTRY */
		struct {
			__u64 hardware_entry_failure_reason;
		} fail_entry;
		/* KVM_EXIT_EXCEPTION */
		struct {
			__u32 exception;
			__u32 error_code;
		} ex;
		/* KVM_EXIT_IO */
		struct {
#define KVM_EXIT_IO_IN  0
#define KVM_EXIT_IO_OUT 1
			__u8 direction;
			__u8 size; /* bytes */
			__u16 port;
			__u32 count;
			__u64 data_offset; /* relative to kvm_run start */
		} io;
		/* KVM_EXIT_MMIO */
		struct {
			__u64 phys_addr;
			__u8  data[8];
			__u32 len;
			__u8  is_write;
		} mmio;
		/* KVM_EXIT_HYPERCALL */
		struct {
			__u64 nr;
			__u64 args[6];
			__u64 ret;
			__u32 longmode;
			__u32 pad;
		} hypercall;
		/* KVM_EXIT_TPR_ACCESS */
		struct {
			__u64 rip;
			__u32 is_write;
			__u32 pad;
		} tpr_access;
		/* KVM_EXIT_S390_SIEIC */
		struct {
			__u8 icptcode;
			__u16 ipa;
			__u32 ipb;
		} s390_sieic;
		/* KVM_EXIT_S390_RESET */
		__u64 s390_reset_flags;
		/* KVM_EXIT_S390_UCONTROL */
		struct {
			__u64 trans_exc_code;
			__u32 pgm_code;
		} s390_ucontrol;
		/* KVM_EXIT_DCR (deprecated) */
		struct {
			__u32 dcrn;
			__u32 data;
			__u8  is_write;
		} dcr;
		/* KVM_EXIT_INTERNAL_ERROR */
		struct {
			__u32 suberror;
			__u32 ndata;
			__u64 data[16];
		} internal;
		/* KVM_EXIT_OSI */
		struct {
			__u64 gprs[32];
		} osi;
		/* KVM_EXIT_PAPR_HCALL */
		struct {
			__u64 nr;
			__u64 ret;
			__u64 args[9];
		} papr_hcall;
		/* KVM_EXIT_S390_TSCH */
		struct {
			__u16 subchannel_id;
			__u16 subchannel_nr;
			__u32 io_int_parm;
			__u32 io_int_word;
			__u32 ipb;
			__u8 dequeued;
		} s390_tsch;
		/* KVM_EXIT_EPR */
		struct {
			__u32 epr;
		} epr;
		/* KVM_EXIT_SYSTEM_EVENT */
		struct {
#define KVM_SYSTEM_EVENT_SHUTDOWN       1
#define KVM_SYSTEM_EVENT_RESET          2
#define KVM_SYSTEM_EVENT_CRASH          3
			__u32 type;
			__u64 flags;
		} system_event;
		/* KVM_EXIT_S390_STSI */
		struct {
			__u64 addr;
			__u8 ar;
			__u8 reserved;
			__u8 fc;
			__u8 sel1;
			__u16 sel2;
		} s390_stsi;
		/* KVM_EXIT_IOAPIC_EOI */
		struct {
			__u8 vector;
		} eoi;
		/* Fix the size of the union. */
		char padding[256];
	};

	__u64 kvm_valid_regs;
	__u64 kvm_dirty_regs;
	union {
		char padding[2048];
	} s;
};

/* --- Exit reason constants (portable, used by both backends) --- */

#define KVM_EXIT_IO               2
#define KVM_EXIT_HLT              5
#define KVM_EXIT_MMIO             6
#define KVM_EXIT_SHUTDOWN         8
#define KVM_EXIT_INTERNAL_ERROR   17

/* KVM ioctl constants omitted: not used by software CPU backend. */

#endif /* MINI_KVM_H */
