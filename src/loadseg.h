/*
 * loadseg.h - Custom InternalLoadSeg hooks for loading into CHIP memory
 */

#ifndef LOADSEG_H
#define LOADSEG_H

#include <exec/types.h>

/*
 * Load a module into CHIP memory using InternalLoadSeg with custom hooks
 *
 * Arguments:
 *   filename - Path to module file
 *   chipBuffer - Pre-allocated CHIP memory buffer
 *   bufferSize - Size of CHIP buffer
 *
 * Returns:
 *   seglist BPTR on success, NULL on error
 */
BPTR LoadModuleToChip(const char* filename, APTR chipBuffer, ULONG bufferSize);

#endif /* LOADSEG_H */
