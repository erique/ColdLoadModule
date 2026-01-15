/*
 * module.h - Module loading and RomTag detection
 */

#ifndef MODULE_H
#define MODULE_H

#include <exec/types.h>
#include <exec/resident.h>
#include <exec/memory.h>

// Maximum number of RomTags we support in a module
#define MAX_ROMTAGS 8

// Maximum size for coldcapture handler code (4096 - 4 to avoid first longword)
#define MAX_CODE_SIZE (4096 - 4)

// Buffer size for coldcapture handler (extra space to find safe alignment)
#define COLDCAPTURE_BUFFER_SIZE (MAX_CODE_SIZE + 4096)

// Module name for MemList
static const char MODULE_NAME[] = "CLM";

// State values for coldcapture handler
#define MODINFO_STATE_INITIAL       0   // Initial state
#define MODINFO_STATE_FAKE_EXECBASE 1   // Fake ExecBase allocated, rebooting
#define MODINFO_STATE_PATCHED       2   // ResModules patched successfully

/*
 * ModuleInfo - CHIP memory layout structure
 *
 * This structure defines the layout of the allocated CHIP memory buffer.
 * Everything is in a known, fixed location with proper alignment.
 */
struct ModuleInfo
{
    ULONG               mi_Pad0[2];                                     // AllocAbs padding
    UBYTE               mi_PatchState;                                  // ColdCapture state machine
    UBYTE               mi_Pad1[3];                                     // Alignment padding
    char                mi_Name[4 * ((sizeof(MODULE_NAME) + 3) / 4)];   // Aligned name for MemList
    struct MemList      mi_MemList;                                     // To be linked into KickMemPtr
    struct Resident*    mi_RomTags[MAX_ROMTAGS];                        // To be spliced into ResModules
    char                mi_ColdCapture[COLDCAPTURE_BUFFER_SIZE];        // Cold capture handler buffer
    char                mi_Module[0];                                   // Start of relocated module data
};

/*
 * Scan a loaded module for RomTags
 * Returns: Number of RomTags found, fills romTags array
 */
WORD ScanForRomTags(APTR moduleBase, ULONG moduleSize, struct Resident** romTags, WORD maxRomTags);
APTR CopyHandlerToChip(struct ModuleInfo* modinfo);
void InstallCaptures(APTR handlerAddr, struct ModuleInfo* modinfo);

#endif /* MODULE_H */
