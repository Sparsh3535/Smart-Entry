# Firebase Integration Setup Guide

## Overview
The app now supports Firebase integration for fetching student data from Firestore instead of receiving full JSON payloads.

## Data Flow

```
Port 9000 receives data:
  ├── If JSON format → Parse directly → QRAuthenticator
  ├── If simple rollno key → Fetch from Firebase → QRAuthenticator
  └── If raw text → Parse as key-value → QRAuthenticator

Firebase Collections:
  ├── gate_passes (day scholars, hostellers)
  └── leave_requests (leave applications)
```

## Setup Instructions

### 1. Update Firebase Credentials

Edit `lib/firebase_options.dart` and replace the placeholder credentials with your **nit-goa-gate-system** project credentials:

**From Firebase Console:**
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your **nit-goa-gate-system** project
3. Go to **Project Settings** (gear icon)
4. In the **Your apps** section, select your Windows app
5. Copy the config values

**Replace these in `firebase_options.dart`:**
```dart
static const FirebaseOptions windows = FirebaseOptions(
  apiKey: 'YOUR_API_KEY_HERE',
  projectId: 'nit-goa-gate-system',  // Already correct
  messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
  appId: 'YOUR_APP_ID',
  // Keep these empty for desktop-only app
);
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Test Firebase Connection

The app will:
- Connect to port 9000
- Accept incoming data as either:
  - **Rollno Key**: `23ece1031` → Fetches from Firebase
  - **Full JSON**: `{"type":"day_scholar","name":"..."}` → Uses directly
  - **Key-value**: `type:day_scholar\nname:...` → Parses and routes

## Example Firestore Documents

### gate_passes Collection
```json
{
  "rollno": "23ece1031",
  "name": "Student Name",
  "type": "day_scholar",
  "phone": "9876543210",
  "degree": "B Tech",
  "status": "active",
  "studentId": "unique-id",
  "comingFrom": "Location",
  "createdAt": "2026-03-19T11:50:19Z",
  "scanCount": 0
}
```

### leave_requests Collection
```json
{
  "rollno": "23ece1031",
  "name": "Student Name",
  "phone": "9876543210",
  "leaving": "2026-03-20",
  "returning": "2026-03-25",
  "duration": "5 days",
  "address": "Home Address",
  "status": "pending",
  "reason": "Personal Leave"
}
```

## Firebase Service Methods

### `FirebaseService.fetchStudentByRollNo(String rollNo)`
- Searches gate_passes first, then leave_requests
- Returns normalized Map with student data
- Matches the same format sent to QRAuthenticator

### `FirebaseService.fetchAllActiveStudents()`
- Returns all active students from gate_passes

### `FirebaseService.fetchAllLeaveRequests()`
- Returns all pending leave requests

## Console Logs

When data is processed, check the console for logs like:
- `✓ Firebase lookup successful for rollno: 23ece1031`
- `✗ No student found in Firebase for rollno: ...`
- `Detected JSON format - passing to QRAuthenticator`
- `Detected rollno key format: ... - fetching from Firebase`

## Troubleshooting

**Firebase connection fails:**
- Verify API key is correct in `firebase_options.dart`
- Check project ID matches Firebase Console
- Ensure Firestore is enabled in Firebase project

**Data not found:**
- Verify rollno field exists in Firestore documents
- Check spelling and exact field names match
- Ensure documents are in correct collections

**Building fails:**
- Run `flutter pub get` after adding Firebase dependencies
- Clear build cache: `flutter clean`
- Rebuild: `flutter build windows`

## File Changes

- `lib/main.dart` - Firebase initialization
- `lib/firebase_options.dart` - Firebase configuration (UPDATE WITH YOUR CREDENTIALS)
- `lib/managers/firebase_service.dart` - New Firebase service class
- `lib/screens/home_screen.dart` - Updated to support Firebase lookups
- `pubspec.yaml` - Added firebase_core and cloud_firestore packages
