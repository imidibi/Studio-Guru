# Studio Guru - Comprehensive Data Integrity Test Plan

**Version:** 1.32 (Build 16)
**Test Date:** _____________
**Tester:** Ian Miller
**Devices:** Mac, iPad 1, iPad 2

---

## Prerequisites

### Before You Begin

1. **Backup Everything First**
   - Export all studios from current production app
   - Save to a safe location outside the app
   - Create local backups using Settings → Backup & Restore

2. **Install TestFlight Build**
   - Install latest TestFlight build on all three devices
   - Ensure all devices are on the same build number
   - Verify all devices signed into same iCloud account

3. **Initial Clean State**
   - On **Mac**: Delete app data (optional - see note below)
   - On **iPad 1**: Delete app data (optional)
   - On **iPad 2**: Delete app data (optional)
   - Reinstall TestFlight build on all devices
   - **Note:** If you want to test with existing data, skip deletion

4. **Enable Pro Features**
   - On each device, go to Settings
   - Enable "Enable Pro for Testing" toggle (TestFlight only)
   - Verify "Status: Pro features enabled" shows on all devices

5. **Prepare Test Data**
   - Create or identify 3 test studios with different characteristics:
     - **Studio A:** Simple (2-3 devices, 2-3 connections)
     - **Studio B:** Medium (5-7 devices, 8-10 connections, has canvas annotations)
     - **Studio C:** Complex (10+ devices, 20+ connections, multiple manuals attached)

---

## Test Suite 1: Fresh Start - iCloud Sync Setup

**Objective:** Verify initial sync from scratch works correctly

### Test 1.1: Initial Data Creation on Mac
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Launch app on Mac (should be empty or existing data)
2. Create **Studio A** with:
   - 3 devices (different types: interface, synth, mixer)
   - 3 connections between devices
   - Add canvas annotation (draw a simple shape)
   - Take screenshot of canvas
3. Create **Studio B** with:
   - 5 devices
   - 8 connections
   - Upload 1 manual PDF to one device
   - Add canvas annotations
   - Take screenshot
4. Go to Settings → Enable iCloud Sync
5. Tap "Enable and Restart App"
6. App should restart
7. Wait 30 seconds for initial upload

**Expected Results:**
- ✓ App restarts successfully
- ✓ All studios still visible after restart
- ✓ All connections intact
- ✓ Canvas annotations preserved
- ✓ Manual still attached

**Notes:**
_________________________________________________

---

### Test 1.2: First Sync to iPad 1
**Device:** iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Launch app on iPad 1 (should be empty)
2. Go to Settings → Enable iCloud Sync
3. Tap "Enable and Restart App"
4. After restart, wait 2 minutes
5. Pull down to refresh studio list if needed
6. Check both studios appear
7. Open **Studio A**, compare with Mac screenshot
8. Count devices and connections
9. Check canvas annotations visible
10. Open **Studio B**, compare with Mac screenshot
11. Check manual is available on device

**Expected Results:**
- ✓ Studio A appears with correct name
- ✓ Studio A has 3 devices in same positions
- ✓ Studio A has 3 connections intact
- ✓ Studio A canvas annotations synced
- ✓ Studio B appears with correct name
- ✓ Studio B has 5 devices in same positions
- ✓ Studio B has 8 connections intact
- ✓ Studio B manual accessible (tap to view)
- ✓ Studio B canvas annotations synced

**Actual Results:**
- Studio A devices: _______ (expected 3)
- Studio A connections: _______ (expected 3)
- Studio B devices: _______ (expected 5)
- Studio B connections: _______ (expected 8)
- Manual visible: ☐ Yes ☐ No

**Notes:**
_________________________________________________

---

### Test 1.3: Second Sync to iPad 2
**Device:** iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Launch app on iPad 2 (should be empty)
2. Go to Settings → Enable iCloud Sync
3. Tap "Enable and Restart App"
4. After restart, wait 2 minutes
5. Verify both studios appear
6. Open each studio and verify data matches Mac

**Expected Results:**
- ✓ Both studios appear
- ✓ All devices present in correct positions
- ✓ All connections intact
- ✓ Canvas annotations synced
- ✓ Manuals accessible

**Actual Results:**
- Studio A devices: _______ (expected 3)
- Studio A connections: _______ (expected 3)
- Studio B devices: _______ (expected 5)
- Studio B connections: _______ (expected 8)

**Notes:**
_________________________________________________

---

## Test Suite 2: Bi-Directional Sync

**Objective:** Verify changes sync correctly between devices

### Test 2.1: Create Studio on iPad 1
**Device:** iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 1, create **Studio C**:
   - Add 4 devices
   - Create 5 connections
   - Add canvas annotations (different from others)
   - Attach 2 manual PDFs
   - Take screenshot
2. Wait 1 minute
3. Force quit app (swipe up)

**Expected Results:**
- ✓ Studio C created successfully
- ✓ All data saved

**Notes:**
_________________________________________________

---

### Test 2.2: Verify Studio C on Mac
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Wait 2 minutes after iPad 1 force quit
2. On Mac, check studio list
3. Pull down to refresh if needed
4. Open **Studio C**
5. Compare with iPad 1 screenshot

**Expected Results:**
- ✓ Studio C appears in list
- ✓ 4 devices present in same positions
- ✓ 5 connections intact
- ✓ Canvas annotations synced
- ✓ 2 manuals accessible

**Actual Results:**
- Studio C visible: ☐ Yes ☐ No
- Devices: _______ (expected 4)
- Connections: _______ (expected 5)
- Manuals: _______ (expected 2)

**Notes:**
_________________________________________________

---

### Test 2.3: Verify Studio C on iPad 2
**Device:** iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 2, check studio list
2. Open **Studio C**
3. Verify all data matches

**Expected Results:**
- ✓ Studio C synced to iPad 2
- ✓ All data intact

**Actual Results:**
- Devices: _______ (expected 4)
- Connections: _______ (expected 5)
- Manuals: _______ (expected 2)

**Notes:**
_________________________________________________

---

### Test 2.4: Modify Studio on Mac
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, open **Studio A**
2. Add 2 more devices
3. Create 3 more connections
4. Modify canvas annotations (add new shapes)
5. Take screenshot
6. Wait 1 minute

**Expected Results:**
- ✓ Changes saved on Mac
- Total devices: 5
- Total connections: 6

**Notes:**
_________________________________________________

---

### Test 2.5: Verify Modifications on Both iPads
**Devices:** iPad 1, iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Wait 2 minutes after Mac modifications
2. On iPad 1: Open Studio A, verify changes
3. On iPad 2: Open Studio A, verify changes
4. Compare with Mac screenshot

**Expected Results:**
- ✓ iPad 1 shows 5 devices (was 3)
- ✓ iPad 1 shows 6 connections (was 3)
- ✓ iPad 1 shows updated annotations
- ✓ iPad 2 shows same changes

**Actual Results - iPad 1:**
- Devices: _______ (expected 5)
- Connections: _______ (expected 6)
- Annotations updated: ☐ Yes ☐ No

**Actual Results - iPad 2:**
- Devices: _______ (expected 5)
- Connections: _______ (expected 6)
- Annotations updated: ☐ Yes ☐ No

**Notes:**
_________________________________________________

---

## Test Suite 3: Connection Integrity (Critical)

**Objective:** Verify connections don't disappear during sync

### Test 3.1: Connection Count Baseline
**Device:** All
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On each device, document current connection counts:

**Mac:**
- Studio A connections: _______
- Studio B connections: _______
- Studio C connections: _______
- **TOTAL:** _______

**iPad 1:**
- Studio A connections: _______
- Studio B connections: _______
- Studio C connections: _______
- **TOTAL:** _______

**iPad 2:**
- Studio A connections: _______
- Studio B connections: _______
- Studio C connections: _______
- **TOTAL:** _______

**Expected Results:**
- ✓ All three devices show identical connection counts

**Notes:**
_________________________________________________

---

### Test 3.2: Delete and Re-sync Test
**Device:** iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 1, go to Settings
2. Disable iCloud Sync
3. Restart app
4. Delete **Studio B**
5. Enable iCloud Sync again
6. Restart app
7. Wait 2 minutes
8. Check if Studio B re-appears from cloud
9. If yes, verify connection count

**Expected Results:**
- ✓ Studio B re-downloads from iCloud
- ✓ All connections intact
- ✓ Connection count matches baseline

**Actual Results:**
- Studio B re-appeared: ☐ Yes ☐ No
- Studio B connections: _______ (expected: from baseline)

**Notes:**
_________________________________________________

---

### Test 3.3: Simultaneous Edits Test
**Devices:** Mac and iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Put devices side-by-side
2. On **Mac**: Open Studio C, add 1 device
3. On **iPad 1** (at same time): Open Studio C, add 1 different device
4. Save both (they should auto-save)
5. Wait 3 minutes
6. On **iPad 2**: Check Studio C

**Expected Results:**
- ✓ Studio C on iPad 2 shows both new devices (6 total)
- ✓ No connections lost
- ✓ Last-writer-wins conflict resolution

**Actual Results:**
- Total devices on iPad 2: _______ (expected 6)
- Connections lost: ☐ Yes ☐ No
- If connections lost, count: _______

**Notes:**
_________________________________________________

---

## Test Suite 4: Export and Import

**Objective:** Verify export/import preserves all data

### Test 4.1: Export Studio with Connections
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, open **Studio B**
2. Before export, document:
   - Device count: _______
   - Connection count: _______
   - Has canvas annotations: ☐ Yes ☐ No
   - Manual count: _______
3. Tap share button
4. Export Studio
5. Save to Desktop as "Studio B Export.studioguru"
6. Note file size: _______ KB

**Expected Results:**
- ✓ Export completes without errors
- ✓ File created on Desktop

**Notes:**
_________________________________________________

---

### Test 4.2: Import on Clean Device
**Device:** iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 2, delete **Studio B** (tap and hold → Delete)
2. Confirm deletion
3. Wait for sync (1 minute)
4. Tap "+" to import
5. Select "Studio B Export.studioguru" from Files app
6. Wait for import
7. Open imported Studio B

**Expected Results:**
- ✓ Import completes successfully
- ✓ Studio B appears in list
- ✓ All devices present (count matches baseline)
- ✓ All connections intact (count matches baseline)
- ✓ Canvas annotations preserved
- ✓ Manual accessible (if was in export)

**Actual Results:**
- Devices: _______ (expected: from baseline)
- Connections: _______ (expected: from baseline)
- Annotations: ☐ Present ☐ Missing
- Manual: ☐ Present ☐ Missing ☐ N/A

**Notes:**
_________________________________________________

---

### Test 4.3: Verify Import Synced to Other Devices
**Devices:** Mac, iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Wait 2 minutes after import on iPad 2
2. On **Mac**: Check if Studio B still exists (should - was only deleted on iPad 2)
3. On **iPad 1**: Check Studio B
4. Verify all have same data

**Expected Results:**
- ✓ All devices show Studio B
- ✓ Data consistent across all devices

**Notes:**
_________________________________________________

---

### Test 4.4: Export Studio with Manuals
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, open **Studio C**
2. Ensure at least 2 manuals attached
3. Export Studio C
4. Check Settings → iCloud Sync Status
5. Verify manual storage location

**Expected Results:**
- ✓ Export includes manual references
- ✓ Export completes successfully

**Current Behavior Note:**
- Manuals are stored in iCloud Drive separately
- Export may not include actual PDF files (only references)
- This is a known limitation to verify

**Actual Results:**
- Export file size: _______ KB
- Manual files included: ☐ Yes ☐ No ☐ Unknown

**Notes:**
_________________________________________________

---

## Test Suite 5: Backup and Restore

**Objective:** Verify backup/restore functionality

### Test 5.1: Create Backup
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, go to Settings → Backup & Restore
2. Document current state:
   - Total studios: _______
   - Studio A connections: _______
   - Studio B connections: _______
   - Studio C connections: _______
3. Tap "Create Backup Now"
4. Wait for confirmation
5. Note backup timestamp shown

**Expected Results:**
- ✓ Backup created successfully
- ✓ Confirmation message appears
- ✓ Timestamp updated

**Notes:**
_________________________________________________

---

### Test 5.2: Make Destructive Changes
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, delete all connections in Studio A
2. Delete 3 devices from Studio B
3. Delete Studio C entirely
4. Wait 1 minute for sync

**Expected Results:**
- ✓ Changes applied on Mac
- ✓ Changes sync to iPads

**Verification on iPad 1:**
- Studio A connections: _______ (should be 0)
- Studio B devices: _______ (should be reduced)
- Studio C exists: ☐ Yes ☐ No (should be No)

**Notes:**
_________________________________________________

---

### Test 5.3: Restore from Backup
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, go to Settings → Backup & Restore
2. Tap "Restore from Backup"
3. Confirm restore
4. App should force quit
5. Relaunch app
6. Wait for iCloud sync (if enabled)
7. Verify all studios restored to backup state

**Expected Results:**
- ✓ Restore completes successfully
- ✓ Studio A connections restored (from baseline)
- ✓ Studio B devices restored
- ✓ Studio C re-appears
- ✓ All data matches pre-destruction state

**Actual Results:**
- Studio A connections: _______ (expected: from baseline)
- Studio B devices: _______ (expected: from baseline)
- Studio C exists: ☐ Yes ☐ No (expected: Yes)

**Notes:**
_________________________________________________

---

### Test 5.4: Verify Restore Synced
**Devices:** iPad 1, iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Wait 3 minutes after Mac restore
2. On iPad 1: Check all studios
3. On iPad 2: Check all studios
4. Verify restored data synced

**Expected Results:**
- ✓ iPad 1 shows restored data
- ✓ iPad 2 shows restored data
- ✓ All devices in sync

**Actual Results - iPad 1:**
- Studio C re-appeared: ☐ Yes ☐ No
- Studio A connections: _______ (expected: from baseline)

**Actual Results - iPad 2:**
- Studio C re-appeared: ☐ Yes ☐ No
- Studio A connections: _______ (expected: from baseline)

**Notes:**
_________________________________________________

---

## Test Suite 6: Gear Locker Sync

**Objective:** Verify Gear Locker syncs correctly

### Test 6.1: Add to Gear Locker
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, go to Gear Locker
2. Add 3 devices with different configurations
3. Attach manual to one device
4. Take screenshot
5. Wait 1 minute

**Expected Results:**
- ✓ 3 devices added to locker
- ✓ Manual attached

**Notes:**
_________________________________________________

---

### Test 6.2: Verify Gear Locker on iPads
**Devices:** iPad 1, iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 1: Open Gear Locker
2. Verify 3 devices present
3. Check manual accessibility
4. On iPad 2: Repeat verification

**Expected Results:**
- ✓ All 3 devices synced to iPad 1
- ✓ All 3 devices synced to iPad 2
- ✓ Manual accessible on both iPads

**Actual Results:**
- iPad 1 locker devices: _______ (expected 3)
- iPad 2 locker devices: _______ (expected 3)

**Notes:**
_________________________________________________

---

### Test 6.3: Assign from Locker
**Device:** iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 1, open Studio A
2. Tap Gear Locker button
3. Assign one device to canvas
4. Wait 1 minute

**Expected Results:**
- ✓ Device appears in Studio A
- ✓ Device marked as assigned in locker

**Notes:**
_________________________________________________

---

### Test 6.4: Verify Assignment Synced
**Devices:** Mac, iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac: Open Studio A
2. Verify assigned device present
3. On iPad 2: Open Studio A
4. Verify assigned device present
5. Check Gear Locker shows device as assigned

**Expected Results:**
- ✓ Assigned device synced to Mac
- ✓ Assigned device synced to iPad 2
- ✓ Locker shows correct assignment status

**Notes:**
_________________________________________________

---

## Test Suite 7: Stress Tests

**Objective:** Test edge cases and limits

### Test 7.1: Rapid Sequential Changes
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Open Studio B
2. Rapidly perform these actions:
   - Add device
   - Add connection
   - Add device
   - Add connection
   - Delete connection
   - Add annotation
   - Add device
3. Force quit immediately (don't wait)
4. Relaunch
5. Check if all changes persisted

**Expected Results:**
- ✓ Most or all changes persisted
- ✓ No data corruption
- ✓ App launches successfully

**Notes:**
_________________________________________________

---

### Test 7.2: Network Interruption Test
**Device:** iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 1, enable Airplane Mode
2. Make changes to Studio C:
   - Add 2 devices
   - Create 3 connections
3. Wait 1 minute
4. Turn off Airplane Mode
5. Wait 2 minutes for sync
6. Check Mac and iPad 2 for changes

**Expected Results:**
- ✓ Changes queued while offline
- ✓ Changes sync when online
- ✓ No data loss

**Actual Results:**
- Changes synced: ☐ Yes ☐ No
- Time to sync: _______ seconds

**Notes:**
_________________________________________________

---

### Test 7.3: App Background/Foreground
**Device:** iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Open Studio A
2. Add a device
3. Immediately swipe home (background app without force quit)
4. Wait 2 minutes
5. Make changes on Mac to Studio A
6. Return to iPad 2 app (bring to foreground)
7. Verify both sets of changes present

**Expected Results:**
- ✓ iPad 2 changes saved
- ✓ Mac changes received
- ✓ Merge successful

**Notes:**
_________________________________________________

---

### Test 7.4: Large Studio Test
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Create new Studio "Stress Test"
2. Add 20 devices
3. Create 40 connections
4. Add extensive canvas annotations
5. Attach 5 manuals
6. Save and wait for sync
7. Open on iPad 1 and verify

**Expected Results:**
- ✓ All 20 devices sync
- ✓ All 40 connections intact
- ✓ Annotations visible
- ✓ All manuals accessible
- ✓ No performance issues

**Actual Results:**
- Devices on iPad 1: _______ (expected 20)
- Connections on iPad 1: _______ (expected 40)
- Manuals on iPad 1: _______ (expected 5)
- Load time: _______ seconds

**Notes:**
_________________________________________________

---

## Test Suite 8: Manual (PDF) Sync

**Objective:** Verify device manuals sync via iCloud Drive

### Test 8.1: Upload Manual on Mac
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, open Gear Locker (or any studio)
2. Select a device
3. Tap "Add Manual"
4. Upload a PDF (test with 1-5MB file)
5. Verify manual appears in device details
6. Wait 2 minutes

**Expected Results:**
- ✓ Manual uploaded successfully
- ✓ Manual visible in device view

**Notes:**
_________________________________________________

---

### Test 8.2: Verify Manual on iPad via iCloud Drive
**Device:** iPad 1
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 1, open Files app
2. Navigate to: iCloud Drive → Studio Guru → Documents → DeviceManuals
3. Verify uploaded manual PDF is present
4. Open Studio Guru app
5. Open same device
6. Tap manual to view
7. Verify PDF loads

**Expected Results:**
- ✓ Manual file in iCloud Drive
- ✓ Manual accessible in app
- ✓ PDF renders correctly

**Actual Results:**
- File in iCloud Drive: ☐ Yes ☐ No
- Accessible in app: ☐ Yes ☐ No
- PDF loads: ☐ Yes ☐ No

**Notes:**
_________________________________________________

---

### Test 8.3: Manual Deletion Sync
**Device:** Mac
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On Mac, delete the manual from device
2. Wait 1 minute
3. On iPad 1: Verify manual removed from device
4. Check iCloud Drive - file may still exist (this is OK)

**Expected Results:**
- ✓ Manual removed from device on iPad 1
- ✓ No errors displayed

**Notes:**
_________________________________________________

---

## Test Suite 9: Free vs Pro Sync

**Objective:** Verify free tier sync limitations

### Test 9.1: Disable Pro Mode
**Device:** iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. On iPad 2, go to Settings
2. Disable "Enable Pro for Testing"
3. App should restart or disable sync
4. Check iCloud Sync status

**Expected Results:**
- ✓ iCloud Sync disabled when Pro off
- ✓ Warning shown to user
- ✓ Local data still accessible

**Notes:**
_________________________________________________

---

### Test 9.2: Re-enable Pro and Sync
**Device:** iPad 2
**Status:** ☐ Pass ☐ Fail

**Steps:**
1. Re-enable "Enable Pro for Testing"
2. Enable iCloud Sync
3. Restart app
4. Verify all studios re-sync from cloud

**Expected Results:**
- ✓ Sync re-enabled
- ✓ All studios download
- ✓ No data lost during Pro toggle

**Notes:**
_________________________________________________

---

## Final Validation Checklist

After completing all tests, verify final state:

### All Devices - Final Count Verification

**Mac:**
- Total Studios: _______
- Studio A - Devices: _______ Connections: _______
- Studio B - Devices: _______ Connections: _______
- Studio C - Devices: _______ Connections: _______
- Gear Locker Devices: _______

**iPad 1:**
- Total Studios: _______
- Studio A - Devices: _______ Connections: _______
- Studio B - Devices: _______ Connections: _______
- Studio C - Devices: _______ Connections: _______
- Gear Locker Devices: _______

**iPad 2:**
- Total Studios: _______
- Studio A - Devices: _______ Connections: _______
- Studio B - Devices: _______ Connections: _______
- Studio C - Devices: _______ Connections: _______
- Gear Locker Devices: _______

**All devices should match ✓**

---

## Critical Issues Found

**Issue 1:**
- Severity: ☐ Critical ☐ High ☐ Medium ☐ Low
- Description: _______________________________________________
- Steps to Reproduce: ________________________________________
- Devices Affected: __________________________________________

**Issue 2:**
- Severity: ☐ Critical ☐ High ☐ Medium ☐ Low
- Description: _______________________________________________
- Steps to Reproduce: ________________________________________
- Devices Affected: __________________________________________

**Issue 3:**
- Severity: ☐ Critical ☐ High ☐ Medium ☐ Low
- Description: _______________________________________________
- Steps to Reproduce: ________________________________________
- Devices Affected: __________________________________________

---

## Test Summary

**Date Completed:** _____________
**Time Invested:** _______ hours
**Total Tests:** 40+
**Tests Passed:** _______
**Tests Failed:** _______
**Pass Rate:** _______%

**Overall Confidence Level:**
- ☐ High - Ready for production
- ☐ Medium - Minor issues to address
- ☐ Low - Major issues found

**Recommended Actions:**
1. _________________________________________________
2. _________________________________________________
3. _________________________________________________

**Notes:**
_____________________________________________________________
_____________________________________________________________
_____________________________________________________________
_____________________________________________________________

---

## Appendix: Quick Reference Commands

### Delete App Data (macOS)
```bash
rm -rf ~/Library/Containers/com.ianmiller.studioguru
rm -rf ~/Library/Group\ Containers/group.com.ianmiller.studioguru
```

### Check iCloud Drive Manually Location
- **Mac:** ~/Library/Mobile Documents/iCloud~com~ianmiller~studioguru/Documents/DeviceManuals/
- **iPad:** Files app → iCloud Drive → Studio Guru → Documents → DeviceManuals

### Force Sync Trigger
- Pull down on studio list to refresh
- Force quit app and relaunch
- Toggle airplane mode off/on

### Expected Sync Times
- Small changes: 30-60 seconds
- New studio: 1-2 minutes
- Complex studio: 2-3 minutes
- First sync: 3-5 minutes

---

**End of Test Plan**
