*
* testmodule.s - Test module with both COLDSTART and SINGLETASK RomTags
*
* This module is used to test ColdLoadModule functionality.
* It contains two RomTags:
*   1. A SINGLETASK RomTag (to test ColdCapture/TRACE approach)
*   2. A COLDSTART RomTag (to test CoolCapture patching)
*
* Both simply log to serial when initialized.
*

	machine	mc68060

	include	"exec/types.i"
	include	"exec/resident.i"
	include	"exec/execbase.i"

	IFND ENABLE_KPRINTF
ENABLE_KPRINTF
	ENDC
	include	"../src/kprintf.i"

*******************************************************************************
* SINGLETASK RomTag
*******************************************************************************

singletask_romtag:
	dc.w	RTC_MATCHWORD		; rt_MatchWord
	dc.l	singletask_romtag	; rt_MatchTag (points to itself)
	dc.l	singletask_end		; rt_EndSkip
	dc.b	RTF_SINGLETASK		; rt_Flags
	dc.b	1			; rt_Version
	dc.b	NT_UNKNOWN		; rt_Type
	dc.b	110			; rt_Pri (medium priority)
	dc.l	singletask_name		; rt_Name
	dc.l	singletask_idstring	; rt_IdString
	dc.l	singletask_init		; rt_Init

singletask_name:
	dc.b	"testmodule.singletask",0
	even

singletask_idstring:
	dc.b	"testmodule singletask 1.0",13,10,0
	even

*
* SINGLETASK initialization
* Called during system init, before multitasking starts
*
*
singletask_init:
	movem.l	d0-d1/a0-a1,-(sp)

	kprintf	"*** TESTMODULE SINGLETASK INIT ***\n"
	kprintf "    ABSEXECBASE = %08lx\n",4.w
	kprintf "    A6 ExecBase = %08lx\n",a6
	kprintf	"    ColdCapture = %08lx\n",ColdCapture(a6)
	kprintf	"    CoolCapture = %08lx\n",CoolCapture(a6)

	movem.l	(sp)+,d0-d1/a0-a1
	moveq	#0,d0			; Return NULL (no base structure)
	rts

singletask_end:

*******************************************************************************
* COLDSTART RomTag
*******************************************************************************

coldstart_romtag:
	dc.w	RTC_MATCHWORD		; rt_MatchWord
	dc.l	coldstart_romtag	; rt_MatchTag (points to itself)
	dc.l	coldstart_end		; rt_EndSkip
	dc.b	RTF_COLDSTART		; rt_Flags
	dc.b	1			; rt_Version
	dc.b	NT_UNKNOWN		; rt_Type
	dc.b	100			; rt_Pri (high priority)
	dc.l	coldstart_name		; rt_Name
	dc.l	coldstart_idstring	; rt_IdString
	dc.l	coldstart_init		; rt_Init

coldstart_name:
	dc.b	"testmodule.coldstart",0
	even

coldstart_idstring:
	dc.b	"testmodule coldstart 1.0",13,10,0
	even

*
* COLDSTART initialization
* Called during coldstart, before any tasks exist
*
coldstart_init:
	movem.l	d0-d1/a0-a1,-(sp)

	kprintf	"*** TESTMODULE COLDSTART INIT ***\n"
	kprintf "    ABSEXECBASE = %08lx\n",4.w
	kprintf "    A6 ExecBase = %08lx\n",a6
	kprintf	"    ColdCapture = %08lx\n",ColdCapture(a6)
	kprintf	"    CoolCapture = %08lx\n",CoolCapture(a6)

	movem.l	(sp)+,d0-d1/a0-a1
	moveq	#0,d0			; Return NULL (no base structure)
	rts

coldstart_end:

	END
