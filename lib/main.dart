import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Sharing App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

enum Role { sender, receiver }

class _MyHomePageState extends State<MyHomePage> {
  String? _selectedFilePath;
  final int _port = 3000;
  ServerSocket? _serverSocket;
  Role _role = Role.sender; // Default role
  String _statusMessage = '';
  String _ipAddress = 'Fetching IP...';
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getIPAddress();
  }

  @override
  void dispose() {
    _serverSocket?.close();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _getIPAddress() async {
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (var interface in interfaces) {
        for (var address in interface.addresses) {
          if (!address.isLoopback) {
            setState(() {
              _ipAddress = address.address;
            });
            print('IP Address: ${address.address}');
            return;
          }
        }
      }
      setState(() {
        _ipAddress = 'No non-loopback IPv4 address found';
      });
    } catch (e) {
      setState(() {
        _ipAddress = 'Failed to get IP address: $e';
      });
      print('Failed to get IP address: $e');
    }
  }

  Future<void> _startServer() async {
    if (_serverSocket != null) {
      print('Server already running');
      return;
    }

    try {
      _serverSocket =
          await ServerSocket.bind(InternetAddress.anyIPv4, _port, shared: true);
      print('Server running on port $_port');
      _serverSocket!.listen((Socket client) {
        _handleClient(client);
      });
      setState(() {
        _statusMessage = 'Server running on port $_port';
      });
    } catch (e) {
      print('Failed to start server: $e');
      setState(() {
        _statusMessage = 'Failed to start server: $e';
      });
    }
  }

  void _handleClient(Socket client) async {
    print(
        'Connection from ${client.remoteAddress.address}:${client.remotePort}');
    final file = await _receiveFile(client);
    print('File received and saved as ${file.path}');
    setState(() {
      _statusMessage = 'File received and saved as ${file.path}';
    });
  }

  Future<File> _receiveFile(Socket client) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/received_file');
    final fileSink = file.openWrite();
    await client.listen(fileSink.add).asFuture();
    await fileSink.flush();
    await fileSink.close();
    client.close();
    return file;
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
      });
    }
  }

  Future<void> _sendFile() async {
    if (_selectedFilePath != null) {
      final bytes = await File(_selectedFilePath!).readAsBytes();
      try {
        final socket = await Socket.connect(_ipController.text, _port);
        socket.add(bytes);
        await socket.flush();
        socket.close();
        print('File sent!');
        setState(() {
          _statusMessage = 'File sent successfully!';
        });
      } catch (e) {
        print('Failed to send file: $e');
        setState(() {
          _statusMessage = 'Failed to send file: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('File Sharing App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Device IP: $_ipAddress'),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _role = Role.sender;
                      _statusMessage = 'Switched to Sender';
                    });
                  },
                  child: Text('Sender'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _role == Role.sender ? Colors.blue : Colors.grey,
                  ),
                ),
                SizedBox(width: 20),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _role = Role.receiver;
                      _statusMessage = 'Switched to Receiver';
                    });
                    await _startServer();
                  },
                  child: Text('Receiver'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _role == Role.receiver ? Colors.blue : Colors.grey,
                  ),
                ),
              ],
            ),
            SizedBox(height: 30),
            if (_role == Role.sender) ...[
              _selectedFilePath == null
                  ? Text('No file selected.')
                  : Text('Selected File: $_selectedFilePath'),
              SizedBox(height: 20),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: 'Enter Receiver IP Address',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _pickFile,
                child: Text('Pick File'),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: _sendFile,
                child: Text('Send File'),
              ),
            ],
            if (_role == Role.receiver)
              Text('Waiting to receive file on port $_port'),
            SizedBox(height: 20),
            Text(_statusMessage),
          ],
        ),
      ),
    );
  }
}
