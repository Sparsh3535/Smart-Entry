# QR Scanner Desktop

This project is a Flutter desktop application that functions as a QR code scanner. It utilizes the desktop camera to scan QR codes and displays the scanned data in a structured table format.

## Project Structure

The project is organized as follows:

```
qr_scanner_desktop
├── lib
│   ├── main.dart               # Entry point of the application
│   └── screens
│       └── home_screen.dart    # Home screen displaying scanned data
├── pubspec.yaml                # Flutter project configuration and dependencies
├── windows                     # Windows-specific files for building the application
├── linux                       # Linux-specific files for building the application
├── macos                       # macOS-specific files for building the application
└── README.md                   # Project documentation
```

## Features

- **QR Code Scanning**: Uses the desktop camera to scan QR codes.
- **Data Display**: Displays scanned data in a table format with the following columns:
  - Name
  - ID (Roll No.)
  - Phone Number
  - Location
  - Out Time
  - In Time
  - Security Name

## Getting Started

To run the application, ensure you have Flutter installed on your machine. Clone the repository and navigate to the project directory. Then, run the following commands:

```bash
flutter pub get
flutter run
```

## Dependencies

This project may use various Flutter packages. Check the `pubspec.yaml` file for the complete list of dependencies.

## License

This project is open-source and available under the MIT License.