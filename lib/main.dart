import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  runApp(const MyApp());
}

Future<dynamic> getJson(String uri, dynamic headers) async {
  var url = Uri.parse(uri);
  final response = await http.get(url, headers: headers);
  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    return {'statusCodeError': response.statusCode};
  }
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const mkChannel = MethodChannel('sh.cider.android/musickit');
  final storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ));

  String _devToken = "";
  String _usrToken = "";

  bool _isAuthenticated = false;

  bool _hasErrored = false;
  String _errorMessage = "";

  Future<void> _musicKitAuthentication() async {
    // Fetch developer token via FETCH api.cider.sh
    final res = await getJson("https://api.cider.sh/v1", {
      'user-agent': 'Cider/0.0.1',
    });
    if (res['statusCodeError'] != null) {
      if (kDebugMode) {
        print("Error fetching developer token: ${res['statusCodeError']}");
      }
      return;
    }

    // Is this redundant?
    setState(() {
      _devToken = res['token'];
    });

    var usrToken = await storage.read(key: "usrToken");
    if (usrToken != null) {
      // Verify user token
      final res = await getJson('https://api.music.apple.com/v1/me/library/songs', {
        'Authorization': 'Bearer $_devToken',
        'Music-User-Token': usrToken,
      });
      if (res['statusCodeError'] != null) {
        // Invalid token, delete it
        await storage.delete(key: "usrToken");
      } else if (res['errors'] == null) {
        setState(() {
          _usrToken = usrToken;
          _isAuthenticated = true;
        });
      }
    }

    if (!_isAuthenticated) {
      // Authenticate user with MusicKit
      try {
        var token = await mkChannel.invokeMethod('auth', {'devToken': _devToken});
        if (token != null) {
          await storage.write(key: "usrToken", value: token);
          setState(() {
            _usrToken = token;
            _isAuthenticated = true;
          });
        }
      } on PlatformException catch (e) {
        if (kDebugMode) {
          print(e.message);
        }
        setState(() {
          _isAuthenticated = false;
        });
      } on Exception catch (e) {
        if (kDebugMode) {
          print(e.toString());
        }
        setState(() {
          _isAuthenticated = false;
        });
      }
    }

    if (!_isAuthenticated) {
      setState(() {
        _hasErrored = true;
        _errorMessage = "Failed to authenticate user";
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _musicKitAuthentication();
  }

  @override
  Widget build(BuildContext context) {
    // Show error message (if there is one)
    if (_hasErrored) {
      return Center(
        child: Text(
          _errorMessage,
          style: const TextStyle(
            color: Colors.red,
          ),
          textDirection: TextDirection.ltr,
        ),
      );
    }

    // Show loading indicator (if not authenticated)
    if (!_isAuthenticated) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Show app
    return MaterialApp(
      title: 'Cider',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Cider Mobile Test'),
        ),
        body: const Center(
          child: Text('Tokens are loaded!'),
        ),
      ),
    );
  }
}
