# ColdLoadModule

Development tool for hot-loading resident modules on Amiga using ColdCapture/CoolCapture interception, instead of the usual KickTagPtr approach.
Using ColdCapture, it intercepts the boot flow right before InitCode() is called.
This allows installing modules not supported by the normal mechanism, such as `expansion.library.`

**IMPORTANT**: This is a development/research tool, NOT a replacement for the regular LoadModule!

## Usage

```bash
ColdLoadModule <modulefile> [FORCE]   # Install module and reboot
ColdLoadModule REMOVE                 # Remove handlers and reboot
```

## How It Works

This tool uses ColdCapture/CoolCapture to intercept the boot flow and inject module ROMTAGs before InitCode() is called, using the CPU TRACE.

### Boot Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: PREPARATION (Before Reboot)                            │
├─────────────────────────────────────────────────────────────────┤
│ • Load module into CHIP RAM                                     │
│ • Scan for ROMTAGs, sort by priority                            │
│ • Copy ColdCapture/CoolCapture handlers to CHIP                 │
│ • Add MemList to KickMemPtr (protect from reclaim)              │
│ • Install ColdCapture and CoolCapture in ExecBase               │
│ • Update ExecBase checksum                                      │
│ • Reboot                                                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────┴─────────┐
                    │  ColdCapture      │
                    │  called - from    │
                    │  where?           │
                    └─────────┬─────────┘
                              │
                       ┌──────┴───────────────────────────────┐
                       ↓                                      ↓
┌─────────────────────────────────────────────┐   ExecBase in local memory
│ Phase 2: COLDCAPTURE FROM EXPANSION         │         (exec calling)
├─────────────────────────────────────────────┤               │
│ • ExecBase in non-local memory (AutoConfig) │               │
│ • Called during SINGLETASK init             │               │
│ • Create fake ExecBase in CHIPMEM           │               │
│ • Set Cold/CoolCapture                      │               │
│ • Reboot                                    │               │
└──────────────────────┬──────────────────────┘               │
                       │                                      │
                       └──────┬───────────────────────────────┘
                              ↓
    ┌─────────────────────────────────────────────────────┐
    │ Phase 3: COLDCAPTURE FROM EXEC                      │
    ├─────────────────────────────────────────────────────┤
    │ • Called during exec coldstart initialization       │
    │ • Install TRACE exception handler                   │
    │ • TRACE single-steps execution until InitCode()     │
    │ • At InitCode(RTF_SINGLETASK): patch ResModules     │
    │ • Remove TRACE handler                              │
    │ • Return to normal boot flow                        │
    └─────────────────────────────────────────────────────┘
                              ↓
    ┌─────────────────────────────────────────────────────┐
    │ Phase 4: COOLCAPTURE                                │
    ├─────────────────────────────────────────────────────┤
    │ • Called right before InitCode(RTF_COLDSTART).      │
    │ • Patch ResModules to inject ROMTAGs                │
    │ • Reinstall ColdCapture                             │
    │ • Return to continue boot                           │
    └─────────────────────────────────────────────────────┘
                              ↓
                   Module is now active!
```
