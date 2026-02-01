# ASM-Nano Walkthrough

A lightweight, pure assembly text editor for Linux x86_64.

## Features
- **No Dependencies**: Uses direct Linux system calls (no libc).
- **Basic Editing**: Insert, Backspace, Left/Right Navigation.
- **Status Bar**: Shows filename, modification status, and current line number.
- **Shortcuts Legend**: Displays keybindings at the bottom of the screen.
- **Dynamic Terminal Size**: Automatically adapts to terminal window dimensions.
- **Minimalist**: ~3KB binary size.

## Build and Run

### 1. Build
```bash
make
```

### 2. Run
Provide a filename to edit (must provide a filename to enable saving):
```bash
./asm-nano test.txt
```

## Usage
- **Type** to insert text.
- **Enter** to insert new line.
- **Arrows (Left/Right)** to move cursor.
- **Backspace** to delete character before cursor.
- **CTRL+S** to save changes to disk.
- **CTRL+Q** to quit the editor.

## Implementation Details
The editor uses `termios` to switch the terminal to "raw mode", allowing character-by-character input processing. It maintains a 1MB memory buffer for the file content and renders the entire visible buffer on every keypress (simplistic rendering).

## Known Limitations
- No scrolling (limited to terminal height, though logic handles larger files linearly).
- No Up/Down arrow navigation (currently restricted to Left/Right for simplicity).
- No complex features (Copy/Paste, Search, etc).

## Troubleshooting
- **Segfault on Enter**: Fixed by correcting a logic error in the rendering loop. Previously, when a newline character was encountered, a jump occurred that bypassed the `push` instructions but still reached the `pop` instructions at the end of the loop, corrupting the stack and leading to a crash. The loop has been restructured to ensure stack operations are always balanced regardless of the character being processed.
- **Garbage Output**: Ensured proper addressing using `lea` for memory buffers to avoid any position-independent code issues or symbol resolution quirks.
