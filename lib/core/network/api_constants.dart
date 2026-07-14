class ApiConstants {
  // Use 10.0.2.2 for Android Emulator, or your IPv4 address for physical devices
  static const String baseUrl = 'https://swagger-dense-barcode.ngrok-free.dev';

  static const String loginEndpoint = '$baseUrl/token/';
  static const String scannerUploadEndpoint = '$baseUrl/scanner/upload/';
}