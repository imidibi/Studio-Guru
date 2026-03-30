# TestFlight Setup Guide for Studio Guru Pro

## Step 1: Wait for Processing (Current Step)

**What you're waiting for:**
- Your build to finish processing (15-30 minutes)
- You'll receive an email when it's ready
- In App Store Connect, status will change from "Processing" to "Ready to Submit"

**Check status:**
1. Go to https://appstoreconnect.apple.com
2. Click "Studio Guru Pro"
3. Click **TestFlight** tab
4. Look for Build 1.0 (1) - should show processing status

---

## Step 2: Answer Export Compliance (Once Processing Completes)

**When your build shows "Ready to Submit":**

1. Click on the build (version 1.0)
2. You'll see a warning: **"Provide Export Compliance Information"**
3. Click **"Provide Export Compliance Information"** or the warning banner
4. Answer the questions:

**Question 1:** "Is your app designed to use cryptography or does it contain or incorporate cryptography?"

**Answer:** **NO** (select this)
- Your app uses standard iCloud sync and HTTPS
- These don't count as custom encryption
- Only say "YES" if you wrote custom encryption code

5. Click **"Start Internal Testing"** (or the confirmation button)

---

## Step 3: Set Up External Testing Group

**External Testing = Beta testers outside your company**

1. Still in **TestFlight** tab
2. Click **"External Testing"** in the left sidebar (under "TestFlight" section)
3. Click the **"+"** button (or "Create Group")
4. **Group Name**: `Beta Testers` (or your choice)
5. **Enable automatic distribution**: Leave unchecked for now (you'll manually add builds)
6. Click **"Create"**

---

## Step 4: Add Your Build to the Group

1. In your "Beta Testers" group (just created)
2. Click **"Builds"** section
3. Click **"+"** or **"Add Build"**
4. Select **Version 1.0 (Build 1)**
5. Click **"Add"** or **"Next"**

---

## Step 5: Add Test Information (Required)

You'll be asked to provide test information:

### What to Test:
```
This is Beta 1 of Studio Guru Pro - a professional studio connection management tool.

Key areas to test:
- Creating and managing studio setups
- Adding devices with various I/O configurations
- Creating connections between devices (analog, digital, MIDI, computer)
- ADAT/S/PDIF bulk connections (8-channel and stereo)
- Matrix view with zoom/pan functionality
- Device inspection (long press)
- iCloud sync across multiple devices
- Export/Import studio configurations
- PDF manual storage and viewing

Please refer to the Beta Test Plan document for detailed test scenarios.
```

### Beta App Description:
```
Studio Guru Pro helps audio professionals document and manage their studio connections. Create a visual map of your devices, track detailed I/O configurations, and sync your setups across all your devices via iCloud.

This beta version includes all core features:
- Graphical studio visualization
- Detailed connection tracking
- Matrix view for spreadsheet-style overview
- Multi-device iCloud sync
- Import/Export functionality
- Device manual storage with PDF viewer
```

### Feedback Email:
```
[Your email address for beta feedback]
```

### Privacy Policy URL (if required):
```
[Your privacy policy URL - you may need to create one]
```

**Click "Next" or "Submit"**

---

## Step 6: Submit for Beta App Review

**Important:** First external build requires Apple review (1-2 days)

1. After adding test information, you'll see **"Submit for Review"** button
2. Click **"Submit for Review"**
3. You may be asked additional questions:
   - **Sign-in required?** NO (your app doesn't need login)
   - **Demo account?** Not applicable
   - **Contact information:** Your email and phone
4. Click **"Submit"**

**What happens now:**
- Apple reviews your app for TestFlight (24-48 hours typically)
- You'll get email when approved
- Once approved, you can add testers

---

## Step 7: Add Beta Testers (After Approval)

**Once Apple approves your beta:**

### Option A: Add Individual Testers

1. In your "Beta Testers" group
2. Click **"Testers"** section
3. Click **"+"** or **"Add Testers"**
4. **Enter email addresses** (one per line):
   ```
   tester1@example.com
   tester2@example.com
   tester3@example.com
   ```
5. Click **"Add"**

**Each tester will receive:**
- Email invitation to test
- Instructions to download TestFlight app
- Link to install Studio Guru Pro

### Option B: Public Link (Easier for Many Testers)

1. In your "Beta Testers" group
2. Enable **"Public Link"**
3. Copy the public link
4. Share this link with anyone you want to test
5. They click link → Download TestFlight → Install app

**Public link advantages:**
- No need to collect emails
- Testers can join instantly
- Easy to share (email, Slack, social media)
- Up to 10,000 external testers

---

## Step 8: Monitor Testing

**Check feedback and crashes:**

1. **TestFlight tab** → **Beta Testers** group
2. Click **"Builds"** to see installation stats
3. Click **"Feedback"** to see:
   - Tester screenshots
   - Comments
   - Crash reports
4. Click **"Crashes"** to see crash logs

---

## Step 9: Update Your Beta (When Ready)

**To release a new beta build:**

1. In Xcode: Increment **Build** number (1 → 2)
2. Product → Archive
3. Distribute → Upload to App Store Connect
4. Wait for processing
5. In TestFlight: Add new build to your "Beta Testers" group
6. Testers automatically get update notification

**Note:** Subsequent builds don't need Apple review (instant to testers)

---

## Quick Reference: TestFlight Limits

- **Internal testers**: Up to 100 (instant access, no review)
- **External testers**: Up to 10,000 (requires review for first build)
- **Beta test duration**: 90 days per build
- **Builds active**: Up to 100 builds at once
- **Groups**: Unlimited

---

## Troubleshooting

**Build stuck on "Processing":**
- Wait 60 minutes
- If still processing, contact Apple Developer Support

**"Missing Compliance" warning:**
- Answer export compliance questions (see Step 2)

**"Invalid Build" error:**
- Check version/build numbers are incremented
- Verify signing is correct
- Re-archive and upload

**Testers not receiving invitation:**
- Check email addresses are correct
- Ask them to check spam folder
- Use public link instead

**Crashes in TestFlight:**
- Check Crashes section for logs
- Symbols must be included in upload (you did this ✓)

---

## Next Steps After Beta Testing

Once beta testing is complete and you're ready for App Store release:

1. Go to **App Store** tab (not TestFlight)
2. Complete all required fields:
   - Screenshots (iPad screenshots required)
   - Description
   - Keywords
   - Support URL
   - Marketing URL (optional)
   - Privacy Policy URL
3. Select a build from TestFlight
4. Submit for App Store Review
5. Wait 1-3 days for review
6. App goes live!

---

## Important Reminders

✅ First build needs Beta App Review (1-2 days)
✅ Subsequent builds are instant (no review)
✅ Testers need TestFlight app installed
✅ Beta builds expire after 90 days
✅ Up to 10,000 external testers allowed
✅ Public link is easiest for sharing

---

## Your Beta Test Plan

You already have a comprehensive test plan at:
`/Users/ianmiller/Development/Studio Guru/BETA_TEST_PLAN.md`

Share this with your testers along with the TestFlight invitation!

---

**Questions?** Let me know if you need help with any step!
