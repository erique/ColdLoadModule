/*
 * main.c - ColdLoadModule entry point
 *
 * *** DEVELOPMENT/RESEARCH TOOL ***
 * For production use, especially COLDSTART modules, use the regular LoadModule.
 *
 * This tool exists solely to handle the edge case of replacing SINGLETASK
 * modules during development, which the standard KickTag mechanism cannot do.
 */

#include <exec/types.h>
#include <exec/execbase.h>
#include <exec/resident.h>
#include <exec/memory.h>
#include <dos/dos.h>
#include <dos/dosextens.h>

#include <proto/exec.h>
#include <proto/dos.h>

#include <string.h>

#include "module.h"
#include "loadseg.h"
#include "kprintf.h"

extern struct ExecBase* SysBase;

static ULONG getFileSize(const char* filename);
static int loadAndInstallModule(const char* moduleName);
static int removeHandlers(void);

int main(void)
{
    #define TEMPLATE "MODULE,REMOVE/S,FORCE/S"
    enum { ARG_MODULE, ARG_REMOVE, ARG_FORCE, ARG_COUNT };

    LONG args[ARG_COUNT] = { 0 };
    struct RDArgs* rdargs = ReadArgs((STRPTR)TEMPLATE, args, NULL);

    if (!rdargs)
    {
        PrintFault(IoErr(), (STRPTR) "ColdLoadModule");
        Printf((STRPTR) "Usage: ColdLoadModule <MODULE> [FORCE]\n");
        Printf((STRPTR) "       ColdLoadModule REMOVE\n");
        return RETURN_ERROR;
    }

    BOOL remove = args[ARG_REMOVE];
    BOOL force = args[ARG_FORCE];
    char moduleName[256]; moduleName[0] = '\0';

    if (args[ARG_MODULE])
    {
        strncpy(moduleName, (const char*)args[ARG_MODULE], sizeof(moduleName) - 1);
        moduleName[sizeof(moduleName) - 1] = '\0';
    }

    FreeArgs(rdargs);

    kprintf("ColdLoadModule starting...\n");

    if (remove)
        return removeHandlers();

    if (!moduleName[0])
    {
        Printf((STRPTR) "Error: MODULE argument required\n");
        return RETURN_ERROR;
    }

    kprintf("Module: %s\n", moduleName);

    if ((SysBase->ColdCapture || SysBase->CoolCapture) && !force)
    {
        Printf((STRPTR) "Error: ColdCapture is %08lx\n", (ULONG)SysBase->ColdCapture);
        Printf((STRPTR) "       CoolCapture is %08lx\n", (ULONG)SysBase->CoolCapture);
        Printf((STRPTR) "Cannot run ColdLoadModule while Cold/CoolCapture is active\n");
        return RETURN_FAIL;
    }

    return loadAndInstallModule(moduleName);
}

// Get file size using Examine()
static ULONG getFileSize(const char* filename)
{
    struct FileInfoBlock* fib = AllocDosObject(DOS_FIB, NULL);
    if (!fib)
    {
        kprintf("getFileSize: Failed to allocate FIB\n");
        return 0;
    }

    ULONG size = 0;
    BPTR lock = Lock((STRPTR)filename, ACCESS_READ);
    if (lock)
    {
        if (Examine(lock, fib))
        {
            size = fib->fib_Size;
            kprintf("getFileSize: '%s' is %ld bytes\n", filename, size);
        }
        UnLock(lock);
    }
    else
    {
        kprintf("getFileSize: Failed to lock '%s'\n", filename);
    }

    FreeDosObject(DOS_FIB, fib);
    return size;
}

static int loadAndInstallModule(const char* moduleName)
{
    // * Get module file size
    ULONG moduleFileSize = getFileSize(moduleName);
    if (moduleFileSize == 0)
    {
        Printf((STRPTR) "Error: Cannot determine file size for '%s'\n", (ULONG)moduleName);
        return RETURN_FAIL;
    }

    // * Calculate total CHIP memory needed
    ULONG totalSize = sizeof(struct ModuleInfo) + moduleFileSize;
    kprintf("Allocating %ld bytes from CHIP RAM\n", totalSize);

    // * Allocate CHIP memory for ModuleInfo + module
    struct ModuleInfo *modinfo = (struct ModuleInfo *)AllocMem(totalSize, MEMF_CHIP | MEMF_CLEAR | MEMF_REVERSE);
    if (!modinfo)
    {
        kprintf("Error: Failed to allocate %ld bytes of CHIP RAM\n", totalSize);
        return RETURN_FAIL;
    }

    kprintf("Allocated CHIP buffer at %08lx\n", (ULONG)modinfo);

    // * Load module into CHIP using InternalLoadSeg
    BPTR seglist = LoadModuleToChip(moduleName, modinfo->mi_Module, moduleFileSize);
    if (!seglist)
    {
        kprintf("Error: Failed to load module into CHIP RAM\n");
        FreeMem(modinfo, totalSize);
        return RETURN_FAIL;
    }

    kprintf("Module loaded into CHIP, seglist=%08lx\n", seglist);

    // * Scan for RomTags
    WORD numRomTags = ScanForRomTags(modinfo->mi_Module, moduleFileSize, modinfo->mi_RomTags, MAX_ROMTAGS);
    if (numRomTags == 0)
    {
        Printf((STRPTR) "Error: No RomTags found in module\n");
        UnLoadSeg(seglist);
        FreeMem(modinfo, totalSize);
        return RETURN_FAIL;
    }

    kprintf("Found %ld RomTag(s) in module\n", (LONG)numRomTags);

    // Sort RomTags by priority (higher priority first)
    // Simple insertion sort - good enough for small arrays
    for (WORD i = 1; i < numRomTags; i++)
    {
        struct Resident *key = modinfo->mi_RomTags[i];
        WORD j = i - 1;

        // Move elements with lower priority down
        while (j >= 0 && modinfo->mi_RomTags[j]->rt_Pri < key->rt_Pri)
        {
            modinfo->mi_RomTags[j + 1] = modinfo->mi_RomTags[j];
            j--;
        }
        modinfo->mi_RomTags[j + 1] = key;
    }

    kprintf("RomTags sorted by priority\n");

    // Print RomTag info
    for (WORD i = 0; i < numRomTags; i++)
    {
        struct Resident *rt = modinfo->mi_RomTags[i];
        kprintf("  RomTag %ld: [%08lx] %s (flags=%02lx, pri=%ld)\n",
                (LONG)i, (ULONG)rt, (ULONG)rt->rt_Name, (ULONG)rt->rt_Flags, (LONG)rt->rt_Pri);
    }

    // * Copy coldcapture handler to CHIP at safe location
    APTR handlerEntry = CopyHandlerToChip(modinfo);

    // * Initialize MemList and link into KickMemPtr
    // This protects our CHIP memory from being reclaimed during boot
    struct ExecBase *ExecBase = SysBase;

    // Initialize MemList node
    modinfo->mi_MemList.ml_Node.ln_Type = NT_MEMORY;
    modinfo->mi_MemList.ml_Node.ln_Pri = 0;
    modinfo->mi_MemList.ml_Node.ln_Name = modinfo->mi_Name;

    // Copy module name
    CopyMem((APTR)MODULE_NAME, modinfo->mi_Name, sizeof(MODULE_NAME));

    // Set up memory entry
    modinfo->mi_MemList.ml_NumEntries = 1;
    modinfo->mi_MemList.ml_ME[0].me_Addr = modinfo;
    modinfo->mi_MemList.ml_ME[0].me_Length = totalSize;

    // Link into KickMemPtr
    modinfo->mi_MemList.ml_Node.ln_Succ = (struct Node *)ExecBase->KickMemPtr;
    ExecBase->KickMemPtr = (APTR)&modinfo->mi_MemList;

    kprintf("MemList initialized and linked to KickMemPtr\n");
    kprintf("  Memory: %08lx - %08lx (%ld bytes)\n",
            (ULONG)modinfo, (ULONG)modinfo + totalSize, totalSize);

    // Update KickCheckSum (call SumKickData from exec.library)
    ULONG checksum = SumKickData();
    ExecBase->KickCheckSum = (APTR)checksum;
    kprintf("KickCheckSum updated to %08lx\n", checksum);

    // * Install ColdCapture and reboot - NEVER RETURNS
    kprintf("System will reboot to install SINGLETASK module...\n");
    Delay(50);

    InstallCaptures(handlerEntry, modinfo);
    // NOT REACHED

    return RETURN_FAIL;
}

// Remove installed handlers
static int removeHandlers(void)
{
    struct ExecBase* ExecBase = SysBase;

    kprintf("Checking for installed handlers...\n");

    if (!ExecBase->ColdCapture && !ExecBase->CoolCapture)
    {
        Printf((STRPTR) "No handlers installed\n");
        return RETURN_OK;
    }

    kprintf("Found handlers:\n");
    if (ExecBase->ColdCapture)
    {
        kprintf("  ColdCapture = %08lx\n", ExecBase->ColdCapture);
        Printf((STRPTR) "  ColdCapture at %08lx\n", (ULONG)ExecBase->ColdCapture);
    }
    if (ExecBase->CoolCapture)
    {
        kprintf("  CoolCapture = %08lx\n", ExecBase->CoolCapture);
        Printf((STRPTR) "  CoolCapture at %08lx\n", (ULONG)ExecBase->CoolCapture);
    }

    // Find and remove our MemList from KickMemPtr chain
    struct MemList* ml = (struct MemList*)ExecBase->KickMemPtr;
    struct MemList* prev = NULL;

    kprintf("Searching KickMemPtr chain for our MemList...\n");

    while (ml)
    {
        if (ml->ml_Node.ln_Name && strcmp(ml->ml_Node.ln_Name, MODULE_NAME) == 0)
        {
            kprintf("Found our MemList at %08lx\n", (ULONG)ml);

            Disable();

            // Unlink from chain
            if (prev)
            {
                prev->ml_Node.ln_Succ = ml->ml_Node.ln_Succ;
            }
            else
            {
                ExecBase->KickMemPtr = ml->ml_Node.ln_Succ;
            }

            // Update KickCheckSum
            ULONG kickChecksum = SumKickData();
            ExecBase->KickCheckSum = (APTR)kickChecksum;

            // Clear handlers
            ExecBase->ColdCapture = NULL;
            ExecBase->CoolCapture = NULL;

            // Update ExecBase checksum
            UWORD checksum = 0;
            UWORD* chksumPtr = (UWORD*)&ExecBase->SoftVer;
            while ((APTR)chksumPtr < (APTR)&ExecBase->ChkSum)
            {
                checksum += *chksumPtr++;
            }
            ExecBase->ChkSum = ~checksum;

            // Clear caches
            CacheClearU();

            Enable();

            kprintf("  Unlinked from KickMemPtr chain\n");
            kprintf("  Updated KickCheckSum to %08lx\n", (ULONG)ExecBase->KickCheckSum);
            kprintf("  Cleared handlers and updated ExecBase checksum\n");

            break;
        }

        prev = ml;
        ml = (struct MemList*)ml->ml_Node.ln_Succ;
    }

    Printf((STRPTR) "Handlers removed and checksum updated. Rebooting...\n");

    Delay(50);
    kprintf("Rebooting system...\n");
    Delay(25);

    ColdReboot();

    return RETURN_OK;
}
