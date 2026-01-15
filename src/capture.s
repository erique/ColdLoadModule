*
* capture.s - ColdCapture handler for SINGLETASK module injection
*             CoolCapture handler for COLDSTART module injection
*
* *** EXPERIMENTAL DEVELOPMENT TOOL ***
* This code is completely position-independent and will be copied to CHIP RAM
* before installing the ColdCapture hook.
*
* This is a research/development tool and NOT intended for production use.
*
* How it works:
* - Called via ColdCapture during system boot (earliest hook point)
* - Uses TRACE mode to step through execution until InitCode(RTF_SINGLETASK)
* - Patches ResModules to inject our module's RomTag before InitCode runs
*

	include	"exec/types.i"
	include	"exec/execbase.i"
	include	"exec/resident.i"
	include	"exec/memory.i"
	include	"lvo/exec_lib.i"

	include "module.i"

; Exception vectors
ILLEGAL_VECTOR	EQU	$10
TRACE_VECTOR	EQU	$24
FLINE_VECTOR 	EQU	$2c

	XDEF	_capture_start
	XDEF	_capture_end
	XDEF	_cool_capture
	XDEF	_cold_capture
	XDEF	_modinfo_ptr

*
* Start marker for PIC code block
* C code will copy from coldcapture_start to coldcapture_end into CHIP RAM
*
_capture_start:

	include "kprintf.i"



*
* ColdCapture handler entry point
*
* Called during coldstart with:
*   A6 = (fake) ExecBase
*   A5 = return address
*
* We set up TRACE mode to monitor execution until InitCode is called
*
_cold_capture:

	; Re-install ColdCapture for next reboot
	move.l	_modinfo_ptr(pc),a0
	lea	mi_ColdCapture(a0),a1
	move.l	a1,ColdCapture(a6)

	; FIRST: Check if we're early enough to patch
	; If A6 == address 4: called from exec.lib (early, before SINGLETASK)
	; If A6 != address 4: called from expansion (too late, during SINGLETASK)
	cmp.l	4.w,a6
	beq	.early_boot

.too_late:
	; Called from expansion - too late (during SINGLETASK)
	; Check ModuleInfo mi_PatchState flag
	movem.l	d0-d2/a0-a2,-(sp)

	move.l	_modinfo_ptr(pc),a0
	moveq.l	#0,d0
	move.b	mi_PatchState(a0),d0

	kprintf	"*** COLD CAPTURE: TOO LATE (expansion), mi_PatchState=%ld\n",d0

	cmp.b	#MODINFO_STATE_PATCHED,d0
	beq	.already_patched

	cmp.b	#MODINFO_STATE_FAKE_EXECBASE,d0
	beq	.fake_reboot_done

	; State is INITIAL - need to allocate fake CHIP ExecBase and reboot
	kprintf	"  * Allocating fake CHIP ExecBase\n"

	; Calculate ExecBase size
	move.w	LIB_NEGSIZE(a6),d2
	add.w	LIB_POSSIZE(a6),d2
	ext.l	d2

	; Allocate CHIP memory for fake ExecBase
	move.l	d2,d0
	move.l	#MEMF_CHIP|MEMF_CLEAR,d1
	jsr	_LVOAllocMem(a6)
	tst.l	d0
	beq	.alloc_failed

	move.l	d0,a2
	kprintf	"  * Allocated buffer at %08lx\n",a2

	; copy real ExecBase to temporary buffer
	move.l	d0,a1		; a1 = dest (temp buffer)
	move.w	LIB_NEGSIZE(a6),d0
	neg.w	d0
	lea	(a6,d0.w),a0
	move.l	d2,d0
	jsr	_LVOCopyMem(a6)

	move.w	LIB_NEGSIZE(a6),d0
	lea	(a2,d0.w),a2		; a2 = fake ExecBase base

	kprintf	"  * Fake ExecBase at %08lx\n",a2

	; Re-install ColdCapture in fake ExecBase
	move.l	_modinfo_ptr(pc),a0
	lea	mi_ColdCapture(a0),a1
	move.l	a1,ColdCapture(a2)

	; Update ChkBase
	move.l	a2,d0
	not.l	d0
	move.l	d0,ChkBase(a2)

	; Update checksum
	move.l	a2,a1
	lea	SoftVer(a1),a0
	moveq	#0,d1
	moveq	#((ChkSum-SoftVer)/2)-1,d0
.chksum_loop:
	add.w	(a0)+,d1
	dbf	d0,.chksum_loop
	not.w	d1
	move.w	d1,ChkSum(a2)

	; Update state to FAKE_EXECBASE
	move.l	_modinfo_ptr(pc),a0
	move.b	#MODINFO_STATE_FAKE_EXECBASE,mi_PatchState(a0)

	; Write fake ExecBase to address 4
	move.l	a2,4.w

	kprintf	"  * Rebooting with fake ExecBase\n"
	jsr	_LVOCacheClearU(a6)
	jsr	_LVOColdReboot(a6)
.trap	bra	.trap

.alloc_failed:
	kprintf	"  * FATAL - AllocMem failed for fake ExecBase\n"
	movem.l	(sp)+,d0-d2/a0-a2
	jmp	(a5)

.fake_reboot_done:
	; We're in the second boot with fake CHIP ExecBase - this shouldn't happen
	; because fake ExecBase should call us early (A6 == address 4)
	kprintf	"  * ERROR - fake ExecBase but still too late!\n"
	movem.l	(sp)+,d0-d2/a0-a2
	jmp	(a5)

.already_patched:
	; Already patched - just re-install ColdCapture and return
	kprintf	"  * Already patched\n"
	movem.l	(sp)+,d0-d2/a0-a2
	jmp	(a5)

.early_boot:
	; Called from exec.lib - early enough to patch
	movem.l	d1-a6,-(sp)


	kprintf	"*** COLD CAPTURE: entered EARLY (exec.lib)\n"
	kprintf	"  * ABSEXECBASE = %08lx | a6 = %08lx\n",4.w,a6
	move.l	_modinfo_ptr(pc),a0
	kprintf	"  * ModuleInfo at %08lx\n",a0
	moveq.l	#0,d0
	move.b	mi_PatchState(a0),d0
	kprintf	"  * mi_PatchState = %ld\n",d0

	; Move VBR to 0 (handle 68010+)
	moveq.l	#0,d0
	machine	mc68010
	movec	d0,vbr		; TODO handle 68000 case
	machine	mc68000

	lea	temp_trace_handler(pc),a1
	move.l	a1,TRACE_VECTOR.w
	or.w	#$8000,sr	; Set TRACE bit
	nop

	move.l	sp,d0
	sub.l	a0,d0
	kprintf	"  * TRACE stack frame size = %ld\n",d0

	; Install our exception handlers
	lea	trace_handler(pc),a1
	move.l	a1,TRACE_VECTOR.w

	kprintf	"  * Installing TRACE handler at %08lx\n",a1

	lea	illegal_handler(pc),a1
	move.l	a1,ILLEGAL_VECTOR.w
	move.l	a1,FLINE_VECTOR.w

	kprintf	"  * Installing ILLEGAL/FLINE handler at %08lx\n",a1

	lea	fastpath(pc),a1
	move.b	#0,(a1)		; start slow

	movem.l	(sp)+,d1-a6

	lea	stackptr(pc),a0
	move.l	sp,(a0)
	sub.l	d0,(a0)

	kprintf "  * Starting TRACE mode, stackptr=%08lx\n",(a0)

	; Enable TRACE mode and return to coldstart
	or.w	#$8000,sr	; Set TRACE bit
	jmp	(a5)		; Return to coldstart


temp_trace_handler:
	move.l	sp,a0		; Save TRACE stack pointer
	and.w	#$7fff,(sp)	; Clear TRACE bit
	rte

*
* Illegal instruction handler
*
illegal_handler:
	; Just enable TRACE and continue

	kprintf	"*** Illegal instruction / F-line caught, re-enabling TRACE mode\n"

	or.w	#$8000,sr
	move.l	updated_vector(pc),-(sp)
	rts

updated_vector:
	dc.l	0			; Saved exception vector
stackptr:
	dc.l	0			; saved stack pointer for TRACE mode
fastpath:
	dc.b	$ff,$00  		; for enabling fast path TRACE (bypass checks)

*
* TRACE exception handler
*
* Called after every instruction when TRACE mode is enabled.
* We monitor execution until we find the "jsr _LVOInitCode(a6)" call
* for RTF_SINGLETASK, then patch ResModules.
*
* Stack on entry:
*   0(sp) = SR at time of trace
*   2(sp) = PC at time of trace
*
trace_handler:
	; Determine stack nesting level
	; stackptr = baseline SP (adjusted for trace frame)
	; current SP vs stackptr tells us if we're in a subroutine

	cmp.l	stackptr(pc),sp
	bne	.nested_subroutine

	move.l	a0,-(sp)
	; At base level - check for InitCode call
	move.l	4+2(sp),a0		; a0 = PC to be executed next
	move.w	(a0),$dff180
;	kprintf	"PC %08lx => [%08lx] (NOT NESTED)\n",a0,(a0)
	cmp.l	#$4eaeffb8,(a0)		; jsr _LVOInitCode(a6)
	move.l	(sp)+,a0
	beq.s	.initcode_found
	rte

.initcode_found:
	; First ResModules patching (before RTF_SINGLETASK)
	kprintf "  * jsr _LVOInitCode(a6) found!\n"
	bsr	patch_resmodules
	kprintf	"*** COLD CAPTURE: DONE - ResModules patched\n"
	and.w	#$7fff,(sp)		; Clear TRACE bit
	rte

.nested_subroutine:
	btst	#0,fastpath(pc)
	beq.s	.first_subroutine
	rte

.first_subroutine:
	move.l	a0,-(sp)

	; In first subroutine - slow path
	move.l	4+2(sp),a0		; a0 = PC to be executed next
	move.w	(a0),$dff180
;	kprintf	"TRACE PC %08lx => [%08lx] (NESTED)\n",a0,(a0)
	cmp.w	#$4e75,(a0)		; rts
	move.l	(sp)+,a0
	bne	.check_cpu_vectors

	move.l	a0,-(sp)
	lea	fastpath(pc),a0
	or.b	#1,(a0)		; Mark that we've seen first rts
	kprintf	"  * First subroutine exit detected - fastpath enabled\n"
	move.l	(sp)+,a0
	rte

.check_cpu_vectors:
	; In first subroutine - check ILLEGAL/FLINE vectors
	movem.l	a0/a1,-(sp)
	lea	updated_vector(pc),a0
	lea	illegal_handler(pc),a1
	cmp.l	ILLEGAL_VECTOR,a1
	beq.s	.ok1
	kprintf	"  * Restoring ILLEGAL vector (from %08lx)\n",ILLEGAL_VECTOR
	move.l	ILLEGAL_VECTOR,(a0)
	move.l	a1,ILLEGAL_VECTOR
	bra.s	.ok2
.ok1:
	cmp.l	FLINE_VECTOR,a1
	beq.s	.ok2
	kprintf	"  * Restoring FLINE vector (from %08lx)\n",FLINE_VECTOR
	move.l	FLINE_VECTOR,(a0)
	move.l	a1,FLINE_VECTOR
.ok2:	movem.l	(sp)+,a0/a1
	rte

*
* patch_resmodules - Patch ResModules with our RomTags
*
* This function is called from TWO places:
*   1. TRACE handler (before InitCode(RTF_SINGLETASK)) - patches first ResModules
*   2. CoolCapture (before InitCode(RTF_COLDSTART)) - patches rebuilt ResModules
*
* exec.library rebuilds ResModules twice,
* so we must patch both times to ensure all our modules are initialized.
*
* INPUT:
*   A6 = ExecBase
*
* PRESERVES:
*   All registers (uses movem.l to save/restore)
*
patch_resmodules:
	kprintf	"*** Patching ResModules ***\n"

	movem.l	d0-d3/a0-a5,-(sp)

	; Allocate temporary buffer on stack for new RomTags
	suba.l	#MAX_ROMTAGS*4,sp
	move.l	sp,a2			; a2 = base of temp buffer

	; For each RomTag in ModuleInfo.romTags, search ResModules for matching name
	; If found and our version/priority is better, replace the pointer
	; If not found, add to temp buffer
	; If found but not better, discard

	move.l	ResModules(a6),d0
	beq	.no_splice_needed	; No ResModules?
	movea.l	d0,a0			; a0 = ResModules

	; Get ModuleInfo and iterate through our RomTags array
	move.l	_modinfo_ptr(pc),a1
	lea	mi_RomTags(a1),a1		; a1 = pointer to our romTags array

	bsr	update_resmodules

	move.l	a2,d3
	sub.l	sp,d3
	lsr.l	#2,d3			; d3 = count of new RomTags
	kprintf	"Temp buffer has %ld entries\n",d3
	tst.l	d3
	beq	.no_splice_needed

	clr.l	(a2)				; NULL-terminate
	move.l	sp,a4				; a4 = base of temp buffer

	bsr	count_resmodules
	kprintf	"ResModules: %ld entries, New: %ld entries\n",d0,d3

	; Allocate: (old_count + new_count + 1) * 4 bytes
	add.l	d3,d0
	addq.l	#1,d0
	lsl.l	#2,d0
	move.l	#$10001,d1		; MEMF_PUBLIC | MEMF_CLEAR
	jsr	_LVOAllocMem(a6)
	tst.l	d0
	beq	.alloc_fail

	kprintf	"Allocated new ResModules array at %08lx\n",d0

	move.l	d0,-(sp)		; Save new array base

	move.l	ResModules(a6),a0	; a0 = old read ptr
	move.l	a4,a1			; a1 = new read ptr (temp buffer)
	move.l	d0,a2			; a2 = dest write ptr
	bsr	merge_romtags

	; Update ExecBase->ResModules
	move.l	(sp)+,a2		; Pop new array base
	move.l	a2,ResModules(a6)
	kprintf	"Updated ResModules to %08lx\n",a2
	bra.s	.no_splice_needed

.alloc_fail:
	kprintf	"FATAL: AllocMem failed\n"

.no_splice_needed:
	; Clean up temp buffer from stack
	adda.l	#MAX_ROMTAGS*4,sp
	movem.l	(sp)+,d0-d3/a0-a5
	rts



; a0 = ResModules pointer
; a1 = our RomTags array pointer
; a2 = temp buffer write pointer
update_resmodules:

	; Loop through NULL-terminated array of our RomTag pointers
.our_romtag_loop:
	move.l	(a1)+,d3		; a3 = our romtag pointer, advance to next
	beq	.done_patching		; NULL terminator, done

	move.l	d3,a3			; a3 = our RomTag
	kprintf	"Checking our RomTag at %08lx (name=%s)\n",a3,RT_NAME(a3)

	; For this RomTag, search ResModules for matching name
	move.l	a0,a4			; a4 = current position in ResModules
.search_resmodules:
	move.l	(a4)+,d0		; d0 = ResModules entry
	beq	.not_found		; End of ResModules, no match found
	bmi.s	.handle_extended	; Extended pointer (bit 31 set)

	; Compare names: a3 = our RomTag, d0 = their RomTag pointer
	move.l	d0,a5			; a5 = their RomTag
	move.l	RT_NAME(a5),d0		; d0 = their name pointer
	beq.b	.search_resmodules	; Their name NULL? skip
	move.l	RT_NAME(a3),d1		; d1 = our name
	beq.b	.search_resmodules	; Our name NULL? skip
	bsr	strcmp			; Compare names (d0 = 0 if equal)
	beq.s	.name_match		; Names match!
	bra.s	.search_resmodules

.handle_extended:
	; Bit 31 set means this is a pointer to another array
	; Clear bit 31 and follow the pointer
	bclr	#31,d0			; Clear bit 31 to get actual pointer
	move.l	d0,a4			; Follow to new array
	bra.b	.search_resmodules	; Continue searching in new array

.name_match:
	kprintf	"Found matching name, comparing versions...\n"
	; Names match - compare version/priority
	; a3 = our RomTag, a5 = their RomTag, a4 = pointer to ResModules slot
	move.b	RT_VERSION(a3),d0	; Our version
	cmp.b	RT_VERSION(a5),d0	; Compare with their version
	blt.s	.discard_romtag		; Our version < theirs, discard
	bgt.s	.do_replace		; Our version > theirs, replace

	; Versions equal, check priority
	move.b	RT_PRI(a3),d0		; Our priority
	cmp.b	RT_PRI(a5),d0		; Compare with their priority
	blt.s	.discard_romtag		; Our priority < theirs, discard
	; Our priority >= theirs, replace

.do_replace:
	kprintf	"Replacing RomTag at ResModules slot %08lx\n",a4
	move.l	a3,-4(a4)		; Replace pointer in ResModules
	bra	.our_romtag_loop	; Continue with next of our RomTags

.discard_romtag:
	; Name matched but our version/priority is not better - discard
	kprintf	"Version/priority not better, discarding\n"
	bra	.our_romtag_loop	; Continue with next of our RomTags

.not_found:
	; No match found in ResModules, add to temp buffer
	kprintf	"No match found, adding to temp buffer\n"
	move.l	a3,(a2)+			; Store and advance
	bra	.our_romtag_loop

.done_patching:
	rts


; strcmp subroutine
; d0 = string 1, d1 = string 2
; Returns: d0 = 0 if equal, non-zero if different
strcmp:
	movem.l	a0-a1,-(sp)
	move.l	d0,a0		; a0 = string 1
	move.l	d1,a1		; a1 = string 2

.strcmp_loop:
	move.b	(a1)+,d0
	move.b	(a0)+,d1
	cmp.b	d0,d1
	bne.s	.strcmp_diff		; Different
	tst.b	d0
	bne.s	.strcmp_loop		; Continue if not at end
.strcmp_equal:
	moveq	#0,d0			; Equal
.strcmp_done:
	movem.l	(sp)+,a0-a1
	rts
.strcmp_diff:
	moveq	#1,d0			; Different
	bra.b	.strcmp_done

count_resmodules:
	; Count entries in ResModules
	move.l	ResModules(a6),a0	; a0 = ResModules
	moveq	#0,d2			; d2 = count
.count_loop:
	move.l	(a0)+,d0
	beq.s	.count_done
	bmi.s	.count_ext
	addq.l	#1,d2
	bra.s	.count_loop
.count_ext:
	bclr	#31,d0
	move.l	d0,a0
	bra.s	.count_loop
.count_done:
	move.l	d2,d0			; d0 = total count
	rts

; Merge: a0=old, a1=new, a2=dest
merge_romtags:
.merge:
	; Read from both inputs
	move.l	(a0),d0			; d0 = old entry
	move.l	(a1),d1			; d1 = new entry

	; Check if both are NULL - done
	move.l	d0,d2
	or.l	d1,d2
	beq.s	.done_merge

	; Handle extended pointer in old array
	tst.l	d0
	bmi.s	.ext

	; If old is NULL, copy from new
	tst.l	d0
	beq.s	.take_new

	; If new is NULL, copy from old
	tst.l	d1
	beq.s	.take_old

	; Both valid - compare priority (higher priority first)
	move.l	d0,a3
	move.l	d1,a4
	move.b	RT_PRI(a3),d2
	cmp.b	RT_PRI(a4),d2
	blt.s	.take_new		; old < new, take new

.take_old:
	move.l	(a0)+,(a2)+
	bra.s	.merge

.take_new:
	move.l	(a1)+,(a2)+
	bra.s	.merge

.ext:
	bclr	#31,d0
	move.l	d0,a0
	bra.s	.merge

.done_merge:
	clr.l	(a2)
	rts

*
* CoolCapture handler
*
* Called right before InitCode(RTF_COLDSTART)
* This is the second patching opportunity 
* - exec.library has already rebuilt ResModules, so we must patch again
*
_cool_capture:
	kprintf "*** COOL CAPTURE: Prepare RTF_COLDSTART ***\n"
	kprintf	"  * ModuleInfo at %08lx\n",_modinfo_ptr(pc)

	; Second ResModules patching (before RTF_COLDSTART)
	bsr	patch_resmodules
	kprintf	"*** COOL CAPTURE: DONE - ResModules patched\n"

	; Re-install ColdCapture for future reboots
	move.l	_modinfo_ptr(pc),a0
	lea	mi_ColdCapture(a0),a1
	move.l	a1,ColdCapture(a6)
	move.b	#0,mi_PatchState(a0)

	kprintf "  * Re-installed ColdCapture at %08lx ***\n",a1

	; Update ExecBase checksum
	move.l	a6,a1
	lea	SoftVer(a1),a0
	moveq	#0,d1
	moveq	#((ChkSum-SoftVer)/2)-1,d0
.chksum_loop:
	add.w	(a0)+,d1
	dbf	d0,.chksum_loop
	not.w	d1
	move.w	d1,ChkSum(a6)
	kprintf "  * Updated ExecBase checksum\n"
	rts


*
* Data storage (position-independent)
* These are accessed via PC-relative addressing: name-_coldcapture_start(pc)
*
	CNOP	0,4
_modinfo_ptr:
	dc.l	0			; Pointer to ModuleInfo structure

*
* End marker for PIC code block
*
_capture_end:

* Static assert: handler size must fit within MAX_CODE_SIZE
HANDLER_SIZE	EQU	_capture_end-_capture_start
	if HANDLER_SIZE>MAX_CODE_SIZE
	fail	"Handler code size exceeds MAX_CODE_SIZE"
	endc

	END
