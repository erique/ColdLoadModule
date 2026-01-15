#include <exec/types.h>
#include <proto/exec.h>
#include <stdarg.h>

// kprintf implementation using exec.library/RawDoFmt

static void rawPutChar(UBYTE c __asm("d0"))
{
    ULONG _RawPutChar_c = (c);
    {
        struct ExecBase* SysBase = *(struct ExecBase**)4;
        register struct ExecBase* const __RawPutChar__bn __asm("a6") = SysBase;
        register ULONG __RawPutChar_c __asm("d0") = (_RawPutChar_c);
        __asm volatile ("jsr a6@(-516:W)"
            :
            : "r"(__RawPutChar__bn), "r"(__RawPutChar_c)
            : "d0", "d1", "a0", "a1", "fp0", "fp1", "cc", "memory");
    }
}

void kprintf(const char* format, ...)
{
    if (format == NULL)
        return;

    va_list arg;
    va_start(arg, format);
    struct ExecBase* SysBase = *(struct ExecBase**)4;
    RawDoFmt((STRPTR)format, arg, (__fpt)rawPutChar, NULL);
    va_end(arg);
}
