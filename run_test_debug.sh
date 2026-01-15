#!/bin/bash
# Run ColdLoadModule test in FS-UAE

SERIAL_LOG="/tmp/loadsinglemodule-serial.log"
SERIAL_SOCK="/tmp/loadsinglemodule-serial.sock"
UAE_LOG="/tmp/loadsinglemodule-uae.log"

echo "Starting ColdLoadModule test..."
echo "======================================="
echo ""
echo "Serial output will be in: $SERIAL_LOG"
echo "FS-UAE output will be in: $UAE_LOG"
echo ""

# Clear old serial log and socket
rm -f "$SERIAL_LOG" "$SERIAL_SOCK" "$UAE_LOG"

# Start socat to capture Unix socket to file
socat -u pty,raw,echo=0,link=$SERIAL_SOCK - > $SERIAL_LOG &  
SOCAT_PID=$!
echo "Started socat (PID $SOCAT_PID)"

# Start tail in background to show serial output
tail -f "$SERIAL_LOG" 2>/dev/null &
TAIL_PID=$!

echo ""
echo "Starting FS-UAE..."
echo "Press Ctrl+C to stop, or close FS-UAE window when done"
echo ""

# Run FS-UAE (using local fs-uae)
./fs-uae/fs-uae test.fs-uae

# Kill background processes
echo ""
echo "Stopping..."
kill $TAIL_PID 2>/dev/null
kill -9 $SOCAT_PID 2>/dev/null
rm -f "$SERIAL_SOCK"

echo ""
echo "Test completed. Serial log:"
echo "----------------------------------------"
cat "$SERIAL_LOG" 2>/dev/null || echo "(No serial output captured)"
echo "----------------------------------------"
