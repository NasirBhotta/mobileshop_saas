import 'package:connectivity_plus/connectivity_plus.dart';

class Network {
  static const networkTimeout = Duration(milliseconds: 1200);
  Network._();
}

class NetworkService {
  const NetworkService();

  Future<bool> get hasConnection async {
    final results = await Connectivity().checkConnectivity();

    return results.any(
      (result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet,
    );
  }
}
