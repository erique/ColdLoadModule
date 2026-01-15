/*
 * module.c - Module loading and RomTag scanning
 */

#include <exec/types.h>
#include <exec/resident.h>
#include <dos/dos.h>

#include <proto/dos.h>
#include <proto/exec.h>

#include "module.h"
#include "kprintf.h"

// External symbols from capture.s
extern UBYTE capture_start[];
extern UBYTE capture_end[];
extern APTR cold_capture;
extern APTR cool_capture;
extern struct ModuleInfo* modinfo_ptr;


WORD ScanForRomTags(APTR moduleBase, ULONG moduleSize, struct Resident** romTags, WORD maxRomTags)
{
    WORD count = 0;

    if (!moduleBase || !romTags || moduleSize == 0)
    {
        return 0;
    }

    kprintf("ScanForRomTags: module at %08lx, size=%ld bytes\n",
            (ULONG)moduleBase, moduleSize);

    // Scan module for RomTag signature
    UWORD* ptr = (UWORD*)moduleBase;
    UWORD* end = (UWORD*)((UBYTE*)moduleBase + moduleSize - sizeof(struct Resident));

    while (ptr < end && count < maxRomTags)
    {
        // Check for RT_MATCHWORD
        if (*ptr == RTC_MATCHWORD)
        {
            kprintf("  Found 0x4AFC at %08lx\n", (ULONG)ptr);
            struct Resident* rt = (struct Resident*)ptr;

            // Validate self-referential pointer
            kprintf("    rt=%08lx, rt_MatchTag=%08lx\n", (ULONG)rt, (ULONG)rt->rt_MatchTag);
            if (rt->rt_MatchTag == rt)
            {
                // Found a valid RomTag!
                kprintf("  Found RomTag: %s (flags=%02lx, pri=%ld)\n",
                        (ULONG)rt->rt_Name, (ULONG)rt->rt_Flags, (LONG)rt->rt_Pri);

                romTags[count] = rt;
                count++;

                // Skip to end of this RomTag
                kprintf("    Skipping to rt_EndSkip=%08lx\n", (ULONG)rt->rt_EndSkip);
                ptr = (UWORD*)rt->rt_EndSkip;
                continue;
            }
            else
            {
                kprintf("    Self-referential check failed\n");
            }
        }

        // Move to next word-aligned position
        ptr++;
    }

    kprintf("ScanForRomTags: Found %ld RomTag(s) total\n", (LONG)count);
    return count;
}

APTR CopyHandlerToChip(struct ModuleInfo* modinfo)
{
    ULONG handlerSize = (ULONG)(capture_end - capture_start);
    kprintf("ColdCapture handler size: %ld bytes\n", handlerSize);

    // Find safe offset in coldCapture buffer that:
    // - Doesn't use first longword of any 4096-byte page
    // - Doesn't cross a page boundary
    ULONG bufferStart = (ULONG)modinfo->mi_ColdCapture;
    ULONG offsetInPage = bufferStart & 4095UL;
    ULONG safeOffset = 0;

    if (offsetInPage < 4)
    {
        // Start is in first longword - skip to offset 4 of this page
        safeOffset = 4 - offsetInPage;
    }
    else if (offsetInPage + handlerSize > 4096)
    {
        // Would cross page boundary - move to next page + 4
        safeOffset = (4096 - offsetInPage) + 4;
    }

    APTR handlerAddr = (APTR)(bufferStart + safeOffset);
    kprintf("Copying handler from %08lx to %08lx (%ld bytes, offset=%ld)\n",
            (ULONG)capture_start, (ULONG)handlerAddr, handlerSize, safeOffset);

    CopyMem(capture_start, handlerAddr, handlerSize);

    // Verify placement is safe
    ULONG handlerStart = (ULONG)handlerAddr;
    ULONG handlerEnd = handlerStart + handlerSize - 1;
    kprintf("Handler occupies addr %08lx to %08lx\n", handlerStart, handlerEnd);
    kprintf("  Start page offset: %ld, End page offset: %ld\n",
            handlerStart & 4095UL, handlerEnd & 4095UL);

    // Calculate actual handler entry point in CHIP
    APTR handlerEntry = (APTR)((UBYTE *)handlerAddr +
                               ((UBYTE *)&cold_capture - (UBYTE *)capture_start));

    kprintf("Handler entry point in CHIP: %08lx\n", (ULONG)handlerEntry);
    return handlerEntry;
}

void InstallCaptures(APTR handlerAddr, struct ModuleInfo* modinfo)
{
    struct ExecBase* ExecBase = SysBase;

    kprintf("installCaptures: handler at %08lx, modinfo at %08lx\n",
            (ULONG)handlerAddr, (ULONG)modinfo);

    intptr_t handlerOffset = (intptr_t)handlerAddr - (intptr_t)&cold_capture;

    struct ModuleInfo** modinfoStorage = (struct ModuleInfo**)(handlerOffset + (intptr_t)&modinfo_ptr);
    *modinfoStorage = modinfo;
    kprintf("  Stored modinfo_ptr at %08lx\n", (ULONG)modinfoStorage);

    Disable();

    // Install our ColdCapture/CoolCapture handlers
    ExecBase->ColdCapture = handlerAddr;
    kprintf("  Set ColdCapture to %08lx\n", (ULONG)handlerAddr);

    APTR coolHandler = (APTR)(handlerOffset + (intptr_t)&cool_capture);
    ExecBase->CoolCapture = coolHandler;
    kprintf("  Set CoolCapture to %08lx\n", (ULONG)coolHandler);

    // Update ExecBase checksum
    UWORD checksum = 0;
    UWORD* chksumPtr = (UWORD*)&ExecBase->SoftVer;
    while ((APTR)chksumPtr < (APTR)&ExecBase->ChkSum)
    {
        checksum += *chksumPtr++;
    }
    ExecBase->ChkSum = ~checksum;
    kprintf("  Updated ExecBase checksum: %04x\n", ExecBase->ChkSum);

    // Clear caches
    CacheClearU();

    kprintf("Rebooting...\n");
    Delay(25); // Give serial time to flush

    // Reboot - NEVER RETURNS
    ColdReboot();

    // Should never reach here
    Enable();
}
