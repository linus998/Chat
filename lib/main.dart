import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';

/* ---------- CONFIG ---------- */
const String baseUrl = 'http://26.20.168.83:5000';   // your LAN IP

/* ---------- MAIN ---------- */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();                 // initialise plugin
  runApp(const MyApp());
}

/* ---------- APP SHELL ---------- */
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat',
      theme: ThemeData.dark(),
      home: const AuthScreen(),
      onGenerateRoute: (settings) {                       // deep-link from tap
        if (settings.name != null) {
          final friend = settings.name!;
          final args = settings.arguments as List<String>; // [username, password]
          return MaterialPageRoute(
            builder: (_) => HomeScreen(
                username: args[0], password: args[1], initialFriend: friend),
          );
        }
        return null;
      },
    );
  }
}

/* ===========================================
 *  NOTIFICATION HELPERS
 * =========================================== */
final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings android =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings ios =
      DarwinInitializationSettings(requestAlertPermission: true);
  const InitializationSettings settings =
      InitializationSettings(android: android, iOS: ios);
  await _notif.initialize(settings);
}

Future<void> showTextNotification({
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
  const AndroidNotificationDetails android = AndroidNotificationDetails(
    'chat_channel', 'Chat messages',
    channelDescription: 'Incoming chat messages',
    importance: Importance.high,
    priority: Priority.high,
  );
  const DarwinNotificationDetails ios =
      DarwinNotificationDetails(presentAlert: true, presentBadge: true);
  const NotificationDetails details =
      NotificationDetails(android: android, iOS: ios);
  await _notif.show(id, title, body, details, payload: payload);
}

/* ===========================================
 *  AUTH SCREEN  (login / register)
 * =========================================== */
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _isLogin = true;

  Future<void> _submit() async {
    final url = Uri.parse('$baseUrl/${_isLogin ? 'login' : 'register'}');
    final res = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _user.text, 'password': _pass.text}));
    final body = jsonDecode(res.body);
    if (!mounted) return;
    if (body['status'] == 'success') {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  HomeScreen(username: _user.text, password: _pass.text)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(body['message'])));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Login' : 'Register')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
                controller: _user,
                decoration: const InputDecoration(labelText: 'Username')),
            TextField(
                controller: _pass,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _submit, child: Text(_isLogin ? 'Login' : 'Register')),
            TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin
                    ? 'Need an account? Register'
                    : 'Have an account? Login'))
          ],
        ),
      ),
    );
  }
}

/* ===========================================
 *  HOME SCREEN  (friends + chat)
 * =========================================== */
class HomeScreen extends StatefulWidget {
  final String username;
  final String password;
  final String? initialFriend;                // from notification tap
  const HomeScreen(
      {super.key, required this.username, required this.password, this.initialFriend});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _friends = [];
  String? _activeFriend;
  final List<Message> _messages = [];
  final _msgCtrl = TextEditingController();
  final _friendCtrl = TextEditingController();
  Timer? _timer;
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFriends().then((_) {
      if (widget.initialFriend != null && _friends.contains(widget.initialFriend)) {
        setState(() => _activeFriend = widget.initialFriend);
        _loadMessages();
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_activeFriend != null) _loadMessages();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /* ---------- friends ---------- */
  Future<void> _loadFriends() async {
    final url = Uri.parse('$baseUrl/friends/${widget.username}');
    final res = await http.get(url);
    final body = jsonDecode(res.body);
    setState(() => _friends = List<String>.from(body['friends']));
  }

  Future<void> _addFriend() async {
    final friend = _friendCtrl.text.trim();
    if (friend.isEmpty) return;
    final url = Uri.parse('$baseUrl/add_friend');
    final res = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': widget.username, 'friend': friend}));
    final body = jsonDecode(res.body);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(body['message'])));
    _loadFriends();
    _friendCtrl.clear();
  }

  /* ---------- messages ---------- */
  Future<void> _loadMessages() async {
    if (_activeFriend == null) return;
    final url = Uri.parse(
        '$baseUrl/messages/${widget.username}/$_activeFriend?password=${widget.password}');
    final res = await http.get(url);
    final body = jsonDecode(res.body);
    if (body['status'] == 'success') {
      final msgs = (body['messages'] as List)
          .map((m) => Message(
              from: m['from'],
              to: m['to'],
              content: m['content'],
              ts: m['timestamp']))
          .toList();

      /* ======  NOTIFICATION  ====== */
      if (msgs.length > _lastMsgCount) {
        for (int i = _lastMsgCount; i < msgs.length; i++) {
          final m = msgs[i];
          if (m.from != widget.username) {
            showTextNotification(
              id: m.content.hashCode & 0x7FFFFFFF,
              title: '$_activeFriend',
              body: m.content,
              payload: '$_activeFriend',
            );
          }
        }
      }
      _lastMsgCount = msgs.length;
      /* ============================ */

      setState(() {
        _messages.clear();
        _messages.addAll(msgs);
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_msgCtrl.text.trim().isEmpty || _activeFriend == null) return;
    final url = Uri.parse('$baseUrl/send');
    await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender': widget.username,
          'receiver': _activeFriend,
          'content': _msgCtrl.text.trim()
        }));
    _msgCtrl.clear();
    _loadMessages();
  }

  /* ---------- UI ---------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 250,
            child: Column(
              children: [
                AppBar(title: const Text('Friends'), elevation: 0),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                      controller: _friendCtrl,
                      decoration: InputDecoration(
                          hintText: 'Add friend',
                          suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _addFriend))),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _friends.length,
                    itemBuilder: (_, i) => ListTile(
                        title: Text(_friends[i]),
                        selected: _friends[i] == _activeFriend,
                        onTap: () {
                          setState(() => _activeFriend = _friends[i]);
                          _lastMsgCount = 0; // reset counter
                          _loadMessages();
                        }),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                AppBar(
                    title: Text(_activeFriend ?? 'Select a friend'),
                    elevation: 0),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final mine = m.from == widget.username;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Card(
                          color: mine ? Colors.blue : Colors.grey[700],
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(m.content,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                const SizedBox(height: 4),
                                Text(m.ts,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white70))
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                            controller: _msgCtrl,
                            decoration:
                                const InputDecoration(hintText: 'Message'),
                            onSubmitted: (_) => _sendMessage()),
                      ),
                      IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _sendMessage)
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

/* ===========================================
 *  DATA CLASS
 * =========================================== */
class Message {
  final String from;
  final String to;
  final String content;
  final String ts;
  Message({required this.from, required this.to, required this.content, required this.ts});
}