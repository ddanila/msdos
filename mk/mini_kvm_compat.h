
#ifndef MINI_KVM_H
#define MINI_KVM_H

#include <stdint.h>

/* Linux defines __u64 as unsigned long long, unlike portable uint64_t on x86-64. */
typedef unsigned char  __u8;
typedef unsigned short __u16;
typedef unsigned int   __u32;
typedef unsigned long long __u64;

#define KVM_NR_INTERRUPTS 256


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

__extension__ struct kvm_run {
	__u8 request_interrupt_window;
	__u8 immediate_exit;
	__u8 padding1[6];

	__u32 exit_reason;
	__u8 ready_for_interrupt_injection;
	__u8 if_flag;
	__u16 flags;

	__u64 cr8;
	__u64 apic_base;

	union {
		struct {
			__u64 hardware_exit_reason;
		} hw;
		struct {
			__u64 hardware_entry_failure_reason;
		} fail_entry;
		struct {
			__u32 exception;
			__u32 error_code;
		} ex;
		struct {
#define KVM_EXIT_IO_IN  0
#define KVM_EXIT_IO_OUT 1
			__u8 direction;
			__u8 size;
			__u16 port;
			__u32 count;
			__u64 data_offset;
		} io;
		struct {
			__u64 phys_addr;
			__u8  data[8];
			__u32 len;
			__u8  is_write;
		} mmio;
		struct {
			__u64 nr;
			__u64 args[6];
			__u64 ret;
			__u32 longmode;
			__u32 pad;
		} hypercall;
		struct {
			__u64 rip;
			__u32 is_write;
			__u32 pad;
		} tpr_access;
		struct {
			__u8 icptcode;
			__u16 ipa;
			__u32 ipb;
		} s390_sieic;
		__u64 s390_reset_flags;
		struct {
			__u64 trans_exc_code;
			__u32 pgm_code;
		} s390_ucontrol;
		struct {
			__u32 dcrn;
			__u32 data;
			__u8  is_write;
		} dcr;
		struct {
			__u32 suberror;
			__u32 ndata;
			__u64 data[16];
		} internal;
		struct {
			__u64 gprs[32];
		} osi;
		struct {
			__u64 nr;
			__u64 ret;
			__u64 args[9];
		} papr_hcall;
		struct {
			__u16 subchannel_id;
			__u16 subchannel_nr;
			__u32 io_int_parm;
			__u32 io_int_word;
			__u32 ipb;
			__u8 dequeued;
		} s390_tsch;
		struct {
			__u32 epr;
		} epr;
		struct {
#define KVM_SYSTEM_EVENT_SHUTDOWN       1
#define KVM_SYSTEM_EVENT_RESET          2
#define KVM_SYSTEM_EVENT_CRASH          3
			__u32 type;
			__u64 flags;
		} system_event;
		struct {
			__u64 addr;
			__u8 ar;
			__u8 reserved;
			__u8 fc;
			__u8 sel1;
			__u16 sel2;
		} s390_stsi;
		struct {
			__u8 vector;
		} eoi;
		char padding[256];
	};

	__u64 kvm_valid_regs;
	__u64 kvm_dirty_regs;
	union {
		char padding[2048];
	} s;
};


#define KVM_EXIT_IO               2
#define KVM_EXIT_HLT              5
#define KVM_EXIT_MMIO             6
#define KVM_EXIT_SHUTDOWN         8
#define KVM_EXIT_INTERNAL_ERROR   17


#endif
