; This file is GENERATED from module.h using h2i.py. Edits will be LOST!

    IFND    SRC_MODULE_I
SRC_MODULE_I SET 1

    NOLIST
    INCLUDE "exec/types.i"
    LIST

MAX_ROMTAGS              EQU 8
MAX_CODE_SIZE            EQU ($1000-4)
COLDCAPTURE_BUFFER_SIZE  EQU (MAX_CODE_SIZE+$1000)
MODINFO_STATE_INITIAL    EQU 0
MODINFO_STATE_FAKE_EXECBASE EQU 1
MODINFO_STATE_PATCHED    EQU 2

;/*
;  * ModuleInfo - CHIP memory layout structure
;  *
;  * This structure defines the layout of the allocated CHIP memory buffer.
;  * Everything is in a known, fixed location with proper alignment.
;  */
    STRUCTURE   ModuleInfo,0
        STRUCT  mi_Pad0,2*4            ; AllocAbs padding
        UBYTE   mi_PatchState          ; ColdCapture state machine
        STRUCT  mi_Pad1,3*1            ; Alignment padding
        STRUCT  mi_Name,4*1            ; Aligned name for MemList
        STRUCT  mi_MemList,24          ; To be linked into KickMemPtr
        STRUCT  mi_RomTags,8*4         ; To be spliced into ResModules
        STRUCT  mi_ColdCapture,8188*1  ; Cold capture handler buffer
        STRUCT  mi_Module,0*1          ; Start of relocated module data
    LABEL       ModuleInfo_sizeof      ; 8260 bytes


    ENDC    ; SRC_MODULE_I
