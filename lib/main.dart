import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:app_links/app_links.dart';

void main() {
  runApp(const MaterialApp(home: MainAppWrapper()));
}

class MainAppWrapper extends StatefulWidget {
  const MainAppWrapper({Key? key}) : super(key: key);

  @override
  _MainAppWrapperState createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends State<MainAppWrapper> {
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() async {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleCourseLink(initialUri);
    }

    _appLinks.uriLinkStream.listen((uri) {
      _handleCourseLink(uri);
    });
  }

  void _handleCourseLink(Uri uri) {
    if (uri.path.startsWith('/courses/')) {
      final String courseId = uri.pathSegments.last;
      if (courseId.isNotEmpty && courseId != 'courses') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AutoCoursePlayerPage(
              courseId: courseId,
              lessonId: 'lesson1',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تطبيق فهّمني')),
      body: const Center(child: Text('في انتظار فتح رابط الكورس...')),
    );
  }
}

class AutoCoursePlayerPage extends StatefulWidget {
  final String courseId;
  final String lessonId;

  const AutoCoursePlayerPage({
    Key? key,
    required this.courseId,
    required this.lessonId,
  }) : super(key: key);

  @override
  _AutoCoursePlayerPageState createState() => _AutoCoursePlayerPageState();
}

class _AutoCoursePlayerPageState extends State<AutoCoursePlayerPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _fetchAndInitializePlayer();
  }

  Future<void> _fetchAndInitializePlayer() async {
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('getSecureVideoUrl');

      final response = await callable.call({
        'courseId': widget.courseId,
        'lessonId': widget.lessonId,
      });

      final String videoUrl = response.data['videoUrl'];
      final Duration lastPosition = await _getLastPosition();

      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        aspectRatio: 16 / 9,
        autoPlay: true,
        startAt: lastPosition,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF00897B),
          handleColor: const Color(0xFF00897B),
          backgroundColor: Colors.grey,
          bufferedColor: Colors.grey.shade300,
        ),
      );

      _videoPlayerController!.addListener(_onVideoPositionChanged);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ أثناء تحميل الفيديو: ${e.toString()}';
      });
    }
  }

  Future<Duration> _getLastPosition() async {
    final String? userId = _auth.currentUser?.uid;
    if (userId == null) return Duration.zero;

    final snapshot = await _firestore
        .collection('progress')
        .doc(userId)
        .collection('courses')
        .doc(widget.courseId)
        .collection('lessons')
        .doc(widget.lessonId)
        .get();

    if (snapshot.exists && snapshot.data() != null) {
      final seconds = snapshot.data()!['progressSeconds'] ?? 0;
      return Duration(seconds: seconds);
    }
    return Duration.zero;
  }

  void _onVideoPositionChanged() {
    if (_videoPlayerController == null) return;
    final position = _videoPlayerController!.value.position;
    final String? userId = _auth.currentUser?.uid;

    if (userId != null && position.inSeconds > 0) {
      _firestore
          .collection('progress')
          .doc(userId)
          .collection('courses')
          .doc(widget.courseId)
          .collection('lessons')
          .doc(widget.lessonId)
          .set({'progressSeconds': position.inSeconds}, SetOptions(merge: true));
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.removeListener(_onVideoPositionChanged);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مشغل الدروس'),
        backgroundColor: const Color(0xFF00897B),
      ),
      body: Center(
        child: _isLoading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Color(0xFF00897B)),
                  SizedBox(height: 16),
                  Text('جارِ التحقق من الصلاحية وجلب الفيديو...'),
                ],
              )
            : _errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    textDirection: TextDirection.rtl,
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Chewie(controller: _chewieController!),
      ),
    );
  }
}
