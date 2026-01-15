/*
 * loadseg.c - Load modules into CHIP memory using InternalLoadSeg
 *
 * Uses dos.library/InternalLoadSeg with custom Read/Alloc/Free hooks
 * to load a module into a pre-allocated CHIP memory buffer.
 */

#include <exec/types.h>
#include <exec/execbase.h>
#include <dos/dos.h>
#include <dos/dosextens.h>

#include <proto/dos.h>
#include <proto/exec.h>

#include <string.h>

#include "loadseg.h"
#include "kprintf.h"

// Allocation state for custom hooks
static struct
{
    APTR base;       // Start of CHIP buffer
    APTR current;    // Current allocation pointer
    ULONG remaining; // Bytes remaining in buffer
    BPTR fh;         // File handle for reading
} allocState;

/*
 * Custom Read hook for InternalLoadSeg
 * Register conventions: d1=file handle, d2=buffer, d3=length, a6=DOSBase
 */
static ULONG ReadHook(BPTR fh __asm("d1"),
                      APTR buffer __asm("d2"),
                      ULONG length __asm("d3"),
                      struct DosLibrary *DOSBase __asm("a6"))
{
    LONG result = Read(allocState.fh, buffer, length);
    if (result < 0)
    {
        return 0;
    }
    return (ULONG)result;
}

/*
 * Custom Alloc hook for InternalLoadSeg
 * Register conventions: d0=size, d1=flags, a6=SysBase
 */
static APTR AllocHook(ULONG size __asm("d0"),
                      ULONG flags __asm("d1"),
                      struct ExecBase* SysBase __asm("a6"))
{
    // Align size to longword boundary
    ULONG alignedSize = (size + 3) & ~3;

    // Check if we have enough space
    if (alignedSize > allocState.remaining)
    {
        kprintf("  Out of memory (need %ld, have %ld)\n",
                alignedSize, allocState.remaining);
        return NULL;
    }

    APTR result = allocState.current;

    kprintf("  Allocated %ld bytes at %08lx\n", alignedSize, (ULONG)result);

    // Update state
    allocState.current = (APTR)((ULONG)allocState.current + alignedSize);
    allocState.remaining -= alignedSize;

    return result;
}

/*
 * Custom Free hook for InternalLoadSeg
 * Register conventions: a1=memory, d0=size, a6=SysBase
 */
static void FreeHook(APTR memory __asm("a1"),
                     ULONG size __asm("d0"),
                     struct ExecBase* SysBase __asm("a6"))
{
    // No-op: we keep everything in CHIP RAM
    (void)memory;
    (void)size;
    (void)SysBase;
}

/*
 * Load a module into CHIP memory using InternalLoadSeg with custom hooks
 */
BPTR LoadModuleToChip(const char* filename, APTR chipBuffer, ULONG bufferSize)
{
    kprintf("LoadModuleToChip: Loading '%s' into CHIP at %08lx (%ld bytes)\n",
            filename, (ULONG)chipBuffer, bufferSize);

    // Open the file
    BPTR fh = Open((STRPTR)filename, MODE_OLDFILE);
    if (!fh)
    {
        kprintf("  Error: Cannot open file\n");
        return 0;
    }

    // Initialize allocation state
    allocState.base = chipBuffer;
    allocState.current = chipBuffer;
    allocState.remaining = bufferSize;
    allocState.fh = fh;

    // Set up hook function table
    LONG functable[3] =
    {
        (LONG)ReadHook,
        (LONG)AllocHook,
        (LONG)FreeHook
    };

    kprintf("  Calling InternalLoadSeg with hooks\n");

    // Load the module using InternalLoadSeg
    LONG stackSize = 0;
    BPTR seglist = InternalLoadSeg(fh, 0, functable, &stackSize);

    Close(fh);

    if (!seglist)
    {
        kprintf("  Error: InternalLoadSeg failed\n");
        return 0;
    }

    kprintf("  Loaded successfully, seglist=%08lx, used %ld bytes\n",
            seglist, bufferSize - allocState.remaining);

    return seglist;
}
