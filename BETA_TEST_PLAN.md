# Studio Guru Beta Test Plan

## Overview
Studio Guru is a studio connection management tool that provides graphical representation of audio studio setups, detailed connection tracking, and multi-device synchronization via iCloud.

## Product Features
- **Graphical Studio View**: High-level depiction of all devices and their connections
- **Connection Details**: Breakdown of connection types (analog, ADAT, DANTE, USB, MIDI, etc.)
- **Device Inspector**: Detailed view of each device and its connections (long press on device)
- **Matrix View**: Spreadsheet-like view showing all devices, connections, and signal flow (from→to)
- **Manual Storage**: Store device manuals with full PDF reader and search functionality
- **Import/Export**: Share studio configurations with other users via .studioguru files
- **Multiple Studios**: Manage multiple studio setups (Studio A, Studio B, etc.)
- **iCloud Sync**: Seamless synchronization across all your Macs and iPads
- **Help Screen**: Built-in onboarding assistance

---

## Test Environment

### Supported Platforms
- macOS (latest version recommended)
- iPadOS (latest version recommended)

### Prerequisites
- Active iCloud account (for sync testing)
- At least one device for basic testing
- Two or more devices for sync testing (recommended)

---

## Test Scenarios

### 1. First Launch & Onboarding

**Objective**: Verify the initial user experience and help system

**Steps**:
1. Launch Studio Guru for the first time
2. Click the Help icon (question mark) in the toolbar
3. Review the help content
4. Close the help screen

**Expected Results**:
- App launches without errors
- Help button is visible in toolbar
- Help screen displays 8 numbered instructions clearly
- "Done" button successfully closes help screen

**Notes**: _______________________________________________

---

### 2. Creating Your First Studio

**Objective**: Test basic studio creation and device management

**Steps**:
1. Click "New Studio" button
2. Enter a studio name (e.g., "My Studio A")
3. Add a device by clicking the "+" button on the canvas
4. Fill in device details:
   - Manufacturer (e.g., "Focusrite")
   - Product (e.g., "Scarlett 18i20")
   - Configure I/O settings (analog inputs/outputs, digital formats)
5. Save the device
6. Add at least 2-3 more devices with different I/O configurations

**Expected Results**:
- Studio is created successfully
- Device editor opens with all fields accessible
- Devices appear on canvas after saving
- Each device displays correct nickname and I/O summary

**Notes**: _______________________________________________

---

### 3. Creating Connections

**Objective**: Test connection creation between devices

**Steps**:
1. Click and drag from the connection handle (triangle) on one device
2. Drag to another device
3. Verify green plus sign appears when hovering over target device
4. Release to create connection
5. Click on the connection line to open connection editor
6. Review the connection endpoints listed
7. Test different connection types:
   - Analog audio connections
   - Digital connections (ADAT if available)
   - MIDI connections
   - Computer interface connections (USB/Thunderbolt/Ethernet)

**Expected Results**:
- Connection line appears during drag (not offset or invisible)
- Connection is created when released on target device
- Connection editor shows correct source and destination
- Different connection types display appropriate colors:
  - Blue: Analog
  - Green: Digital (ADAT/MADI/S/PDIF)
  - Purple: MIDI
  - Orange: Computer (USB/Thunderbolt/Ethernet)

**Issues Found**: _______________________________________________

---

### 4. ADAT/S/PDIF Bulk Connections

**Objective**: Test multi-channel digital connection features

**Steps**:
1. Add two devices with ADAT ports (8 channels each)
2. Drag from ADAT output to ADAT input
3. Open the connection editor
4. Verify all 8 channels are connected correctly (1→1, 2→2, 3→3, etc.)
5. Repeat with S/PDIF connections (2 channels: L/R)

**Expected Results**:
- All ADAT channels (1-8) connect automatically in correct order
- S/PDIF shows as single "L/R" stereo connection
- Channel alignment is correct (Out 1 → In 1, Out 2 → In 2, etc.)

**Issues Found**: _______________________________________________

---

### 5. Editing and Deleting Connections

**Objective**: Test connection management

**Steps**:
1. Single-click a connection line to select it
2. Right-click (or long-press on iPad) a connection line
3. Select "Delete Connection" from context menu
4. Confirm deletion
5. Try double-click on connection line to delete (Mac)
6. Try long-press on connection line to delete (iPad)

**Expected Results**:
- Connection line highlights when selected
- Context menu appears on right-click/long-press
- Connection is deleted after confirmation
- Double-click deletes connection (Mac only)
- Long-press deletes connection (iPad only)
- Connection line does NOT appear offset when right-clicking

**Issues Found**: _______________________________________________

---

### 6. Device Inspector (Long Press)

**Objective**: Test detailed device view

**Steps**:
1. Long-press on a device card
2. Review the connection explosion view
3. Verify all input and output connections are listed
4. Check that connection types and channel counts are shown
5. Close the inspector

**Expected Results**:
- Inspector opens showing all device connections
- Connections are categorized by type
- Channel counts are accurate
- Easy to read and understand

**Notes**: _______________________________________________

---

### 7. Auto-Arrange Feature

**Objective**: Test automatic device layout

**Steps**:
1. Create a studio with 5-6 devices
2. Manually drag devices to random positions
3. Click "Auto-Arrange" button in toolbar
4. Observe device positioning
5. Test on both Mac (wide screen) and iPad (vertical orientation)

**Expected Results**:
- Devices arrange in logical pyramid/flow structure
- Layout is centered on screen (not offset to right on iPad)
- Devices are positioned based on signal flow
- Works correctly on both Mac and iPad orientations

**Issues Found**: _______________________________________________

---

### 8. Matrix View

**Objective**: Test spreadsheet-style connection view

**Steps**:
1. Create connections between several devices
2. Click "Connection Matrix" button in toolbar
3. Review the matrix layout:
   - Column headers (destination devices)
   - Row headers (source devices)
   - Connection cells showing types and channel counts
4. Test zoom functionality (pinch to zoom on iPad, magnification gesture on Mac)
5. Test pan mode after zooming in
6. Toggle between Pan Mode and Zoom Mode using toolbar menu
7. Click "Reset Zoom" to return to 1.0x

**Expected Results**:
- Matrix displays all devices correctly
- Connections show in appropriate cells
- Color coding matches main view (blue/green/purple/orange)
- Channel counts are accurate
- Zoom/pan works smoothly
- Matrix content stays centered when zooming (not offset)
- Pan mode allows scrolling when zoomed
- Toolbar controls switch correctly between modes

**Issues Found**: _______________________________________________

---

### 9. Device Manual Management

**Objective**: Test PDF manual storage and viewing

**Steps**:
1. Click on a device to select it
2. In the inspector, find "Manuals" section
3. Add a PDF manual (use any PDF file for testing)
4. Give it a title
5. Click on the manual to open PDF viewer
6. Test search functionality in PDF viewer
7. Navigate through pages
8. Close PDF viewer

**Expected Results**:
- PDF file can be added successfully
- Manual appears in device inspector
- PDF viewer opens and displays content correctly
- Search function works
- Page navigation is smooth

**Notes**: _______________________________________________

---

### 10. Export Studio Configuration

**Objective**: Test studio export functionality

**Steps**:
1. Create or open a studio with several devices and connections
2. Click "Export" button in toolbar
3. Choose save location
4. Save the .studioguru file
5. Verify file is created

**Expected Results**:
- Export dialog appears
- File saves successfully to chosen location
- File has .studioguru extension
- File size is reasonable

**Notes**: _______________________________________________

---

### 11. Import Studio Configuration

**Objective**: Test studio import functionality

**Steps**:
1. Click "Import" button in toolbar
2. Select a previously exported .studioguru file
3. Handle name conflict if duplicate studio name exists
4. Verify imported studio appears in studio list
5. Open imported studio
6. Verify all devices and connections are intact

**Expected Results**:
- Import dialog appears
- File can be selected and imported
- Name conflict handling works (if applicable)
- Imported studio matches original configuration
- All devices, connections, and manuals are preserved

**Issues Found**: _______________________________________________

---

### 12. Multiple Studio Management

**Objective**: Test managing multiple studios

**Steps**:
1. Create 3 different studios (e.g., "Studio A", "Studio B", "Control Room")
2. Switch between studios using the studio picker
3. Verify each studio maintains its own devices and connections
4. Delete one studio
5. Verify other studios remain unaffected

**Expected Results**:
- Multiple studios can be created
- Switching between studios works smoothly
- Each studio is independent
- Studio deletion works correctly
- Deletion confirmation prevents accidental removal

**Notes**: _______________________________________________

---

### 13. iCloud Sync - Single Device

**Objective**: Verify iCloud sync is active

**Steps**:
1. Open Settings (gear icon)
2. Verify "iCloud sync is active" message appears
3. Make changes to a studio (add device, create connection)
4. Wait a few moments for sync
5. Check Settings again for any sync status changes

**Expected Results**:
- Settings shows iCloud sync is active
- No error messages appear
- Changes are saved locally

**Notes**: _______________________________________________

---

### 14. iCloud Sync - Multi-Device (CRITICAL TEST)

**Objective**: Test sync across multiple devices

**Required**: 2 or more devices (Mac/iPad combinations)

**Steps**:
1. **Device 1**: Create a new studio with 2-3 devices
2. **Device 1**: Create some connections between devices
3. **Device 1**: Wait 30 seconds for sync
4. **Device 2**: Launch Studio Guru (ensure signed in to same iCloud account)
5. **Device 2**: Verify the studio appears
6. **Device 2**: Add a new device to the studio
7. **Device 2**: Wait 30 seconds for sync
8. **Device 1**: Verify the new device appears
9. **Both Devices**: Make simultaneous changes and verify conflict resolution
10. Test with both devices online, then test with one device offline (airplane mode)

**Expected Results**:
- Studios sync from Device 1 to Device 2
- Devices sync correctly
- Connections sync correctly (this was a previous bug - verify it's fixed)
- Device manuals sync
- Bidirectional sync works (Device 2 → Device 1)
- Offline changes sync when device comes back online
- No data loss during sync
- Last-writer-wins for conflicts

**Issues Found**: _______________________________________________

---

### 15. Zoom and Pan on Main Canvas

**Objective**: Test canvas zoom and pan functionality

**Steps**:
1. Open a studio with several devices
2. Use pinch gesture (iPad) or magnification gesture (Mac) to zoom in
3. Verify pan mode activates automatically when zoomed in
4. Pan around the canvas by dragging
5. Toggle between Pan Mode and Zoom Mode using toolbar button
6. Zoom out back to 1.0x
7. Verify pan mode disables when at normal zoom

**Expected Results**:
- Zoom works smoothly from 0.5x to 5x
- Pan mode activates automatically when zoomed > 1.0x
- Pan mode allows scrolling around canvas
- Zoom mode allows further zoom adjustment
- Toolbar icon changes between hand (pan) and magnifying glass (zoom)
- Canvas returns to normal when zoomed to 1.0x

**Issues Found**: _______________________________________________

---

### 16. iPad Vertical Orientation (REGRESSION TEST)

**Objective**: Verify iPad vertical orientation positioning is fixed

**Steps**:
1. **iPad Only**: Rotate device to vertical orientation
2. Create/open a studio with devices
3. Click "Auto-Arrange"
4. Verify devices are centered on screen
5. Try dragging a device to the left edge of screen
6. Try dragging a device to the right edge of screen
7. Create a connection by dragging between devices

**Expected Results**:
- Auto-arrange centers devices properly (not shifted right)
- Devices can be dragged to all areas of screen (left, right, center)
- Connection line appears correctly during drag (not offset)
- Connection line is visible at correct position (not off-screen)

**Issues Found**: _______________________________________________

---

## Performance Testing

### 17. Large Studio Performance

**Objective**: Test app performance with many devices

**Steps**:
1. Create a studio with 15-20 devices
2. Create 30-40 connections between devices
3. Test the following operations:
   - Auto-arrange
   - Scrolling/panning the canvas
   - Zooming in and out
   - Opening connection editor
   - Opening matrix view
   - Switching between studios

**Expected Results**:
- App remains responsive
- No significant lag or freezing
- Animations are smooth
- Matrix view loads without delay

**Notes**: _______________________________________________

---

## Bug Reporting

If you encounter any issues, please report them with the following information:

1. **Device Information**:
   - Device model (e.g., MacBook Pro 16" 2021, iPad Pro 12.9" 2024)
   - OS version (e.g., macOS 15.2, iPadOS 17.5)

2. **Issue Description**:
   - What were you trying to do?
   - What happened instead?
   - Can you reproduce it consistently?

3. **Steps to Reproduce**:
   - Numbered steps to recreate the issue

4. **Screenshots/Screen Recording**:
   - Visual evidence is extremely helpful

5. **Severity**:
   - **Critical**: App crashes, data loss, cannot use core features
   - **High**: Feature doesn't work, major workflow disruption
   - **Medium**: Feature works but has issues, workaround available
   - **Low**: Cosmetic issues, minor inconveniences

---

## Known Issues

*(This section will be populated based on current known bugs)*

- None currently documented

---

## Success Criteria

A successful beta test will verify:
- ✅ All core features work as expected
- ✅ iCloud sync works reliably across devices
- ✅ No data loss during normal operation
- ✅ App is stable (no crashes during testing)
- ✅ UI is intuitive and responsive
- ✅ iPad and Mac versions both function correctly
- ✅ Import/export preserves all studio data

---

## Feedback Form

After completing testing, please provide feedback on:

1. **Overall Experience** (1-5 stars): _____
2. **Ease of Use** (1-5 stars): _____
3. **Performance** (1-5 stars): _____
4. **Feature Completeness** (1-5 stars): _____
5. **Most Useful Feature**: _______________________________________________
6. **Most Confusing Feature**: _______________________________________________
7. **Missing Features/Suggestions**: _______________________________________________
8. **Would you recommend this to other studio professionals?**: YES / NO
9. **Additional Comments**: _______________________________________________

---

## Thank You!

Thank you for participating in the Studio Guru beta test program. Your feedback is invaluable in making Studio Guru the best studio connection management tool available.

For questions or to submit bug reports, please contact: [Your Contact Email]

---

**Version**: Beta 1.0
**Test Plan Date**: March 25, 2026
