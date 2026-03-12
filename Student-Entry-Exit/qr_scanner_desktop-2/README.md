# QR Scanner Desktop

This project is a Flutter desktop application that implements a QR code scanner using the desktop camera. It provides a user-friendly interface for scanning QR codes and displaying the results.

## Features

- **Home Screen**: The main interface of the application, featuring a three-line menu icon that reveals additional options.
- **Console Screen**: A separate view for displaying console logs and messages.
- **Camera Integration**: Accesses the desktop camera to scan QR codes.
- **Overflow Menu**: A responsive menu that allows navigation between the Home Screen and Console Screen.

## Project Structure

```
qr_scanner_desktop
├── lib
│   ├── main.dart                # Entry point of the application
│   ├── screens
│   │   ├── home_screen.dart     # Main interface of the application
│   │   └── console_screen.dart   # Console view for logs
│   ├── widgets
│   │   └── overflow_menu.dart    # Menu widget for navigation
│   ├── services
│   │   └── camera_service.dart    # Service for camera functionality
│   └── models
│       └── scan_result.dart       # Model for scan results
├── test
│   └── widget_test.dart           # Widget tests for the application
├── pubspec.yaml                   # Project configuration and dependencies
├── analysis_options.yaml          # Dart analyzer configuration
├── windows                        # Windows platform-specific files
├── linux                          # Linux platform-specific files
└── macos                          # macOS platform-specific files
```

## Setup Instructions

1. **Clone the repository**:
   ```
   git clone <repository-url>
   cd qr_scanner_desktop
   ```

2. **Install dependencies**:
   ```
   flutter pub get
   ```

3. **Run the application**:
   ```
   flutter run
   ```

## Usage

- Launch the application to access the Home Screen.
- Click on the three-line menu icon to reveal additional options, including navigation to the Console Screen.
- Use the camera to scan QR codes, and the results will be displayed in the application.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any enhancements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for details.