import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "tekne'nin lig tv hayratı",
      theme: ThemeData.dark(),
      home: const ChannelListScreen(),
      debugShowCheckedModeBanner: false,
      debugShowMaterialGrid: false,
    );
  }
}

class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key});

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  List<Map<String, dynamic>> channels = [];
  bool _isLoading = true;
  Map<String, dynamic>? _currentChannel;
  bool _isPlayerLoading = false;
  Timer? _refreshTimer;
  String? _cachedM3UData;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Load M3U data first
    await fetchM3U();
    // Then initialize player for first channel with a small delay
    if (channels.isNotEmpty && mounted) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _setCurrentChannel(channels.first);
        }
      });
    }
  }

  Future<void> fetchM3U({bool forceRefresh = false}) async {
    if (_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    
    try {
      // Clear cache if force refresh
      if (forceRefresh) {
        _cachedM3UData = null;
      }
      
      // Use cache if available and not forcing refresh
      if (_cachedM3UData != null && !forceRefresh) {
        final parsedChannels = parseM3U(_cachedM3UData!);
        setState(() {
          channels = parsedChannels;
          _isLoading = false;
        });
        return;
      }
      
      final response = await http.get(
        Uri.parse('https://tekne.boats/bein.m3u'),
        headers: {
          'User-Agent': 'TekneTV/1.0',
          'Accept': 'application/vnd.apple.mpegurl, application/x-mpegURL, application/octet-stream',
          if (forceRefresh) ...{
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        },
      );
      
      if (response.statusCode == 200) {
        _cachedM3UData = response.body;
        final parsedChannels = parseM3U(response.body);
        setState(() {
          channels = parsedChannels;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        _showError('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Network Error: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _setCurrentChannel(Map<String, dynamic> channel) {
    setState(() {
      _currentChannel = channel;
      _isPlayerLoading = true;
    });
    // Small delay to let UI update before starting video
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isPlayerLoading = false;
        });
      }
    });
  }

  Future<void> _refreshAll() async {
    // Show refresh feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refreshing channels and restarting player...'),
        duration: Duration(seconds: 2),
      ),
    );
    
    // Clear current player
    setState(() {
      _currentChannel = null;
      _isPlayerLoading = false;
    });
    
    try {
      // Fetch fresh data with cache clearing
      await fetchM3U(forceRefresh: true);
      
      // Restart with first channel if available
      if (channels.isNotEmpty && mounted) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _setCurrentChannel(channels.first);
          }
        });
      } else if (mounted) {
        _showError('No channels found. Please check your internet connection.');
      }
    } catch (e) {
      _showError('Refresh failed: $e');
    }
  }

  List<Map<String, dynamic>> parseM3U(String content) {
    final lines = content.split('\n');
    List<Map<String, dynamic>> list = [];
    String? title;
    Map<String, String> currentHeaders = {};

    for (var line in lines) {
      line = line.trim();
      if (line.startsWith('#EXTINF')) {
        final parts = line.split(',');
        title = parts.isNotEmpty ? parts.last.trim() : 'Unknown';
      } else if (line.startsWith('#EXTVLCOPT')) {
        if (line.contains('http-user-agent')) {
          final ua = line.split('=')[1];
          currentHeaders['User-Agent'] = ua;
        } else if (line.contains('http-referrer')) {
          final ref = line.split('=')[1];
          currentHeaders['Referer'] = ref;
        }
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        list.add({
          'title': title ?? 'Unknown',
          'url': line,
          'headers': {...currentHeaders},
        });
        currentHeaders.clear();
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowUp:
              // Navigate up in channel list
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowDown:
              // Navigate down in channel list
              return KeyEventResult.handled;
            case LogicalKeyboardKey.select:
            case LogicalKeyboardKey.enter:
              // Select channel or play/pause
              return KeyEventResult.handled;
            case LogicalKeyboardKey.backspace:
            case LogicalKeyboardKey.escape:
              // Back button
              return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("tekne'nin lig tv hayratı"),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshAll,
            ),
          ],
        ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading channels...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          : Column(
              children: [
                // Current playing channel
                if (_currentChannel != null)
                  Container(
                    width: double.infinity,
                    height: 200,
                    color: Colors.black,
                    child: _isPlayerLoading
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 8),
                                Text('Loading channel...', style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          )
                        : PlayerScreen(
                            url: _currentChannel!['url'],
                            headers: _currentChannel!['headers'],
                            isEmbedded: true,
                          ),
                  ),
                // Channel list
                Expanded(
                  child: ListView.builder(
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
                      final isCurrentChannel = _currentChannel != null && 
                          _currentChannel!['url'] == channel['url'];
                      
          return ListTile(
                        title: Text(
                          channel['title'] ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: isCurrentChannel ? FontWeight.bold : FontWeight.normal,
                            color: isCurrentChannel ? Colors.blue : null,
                          ),
                        ),
                        leading: isCurrentChannel
                            ? const Icon(Icons.play_arrow, color: Colors.blue)
                            : const Icon(Icons.tv),
            onTap: () {
                          _setCurrentChannel(channel);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final bool isEmbedded;

  const PlayerScreen({
    super.key, 
    required this.url, 
    required this.headers,
    this.isEmbedded = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isFullscreen = false;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reinitialize if URL changed
    if (oldWidget.url != widget.url) {
      _initializeController();
    }
  }

  Future<void> _initializeController() async {
    if (_isInitializing) return;
    
    setState(() {
      _isInitializing = true;
      _currentUrl = widget.url;
    });
    
    // Dispose existing controller if URL changed
    if (_controller != null && _currentUrl != widget.url) {
      await _controller!.dispose();
      _controller = null;
    }
    
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: {
        ...widget.headers,
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
    );
    
    try {
      // Initialize with shorter timeout for faster failure
      await _controller!.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Video initialization timeout');
        },
      );
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
        });
        
        // Auto-play for embedded player with small delay
        if (widget.isEmbedded) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && _controller != null) {
              _controller!.play();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  void _openFullscreenPlayer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenPlayerScreen(
          url: widget.url,
          headers: widget.headers,
          controller: _controller,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return Container(
        width: double.infinity,
        height: 200,
        color: Colors.black,
        child: _isInitialized
            ? Stack(
                children: [
                  Center(
                    child: _controller != null && _isInitialized
                        ? AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          )
                        : const CircularProgressIndicator(),
                  ),
                  // Controls overlay
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Play/Pause button
                        FloatingActionButton.small(
                          heroTag: "embedded_play_pause",
                          onPressed: () {
                            if (_controller != null) {
                              setState(() {
                                if (_controller!.value.isPlaying) {
                                  _controller!.pause();
                                } else {
                                  _controller!.play();
                                }
                              });
                            }
                          },
                          child: Icon(
                            _controller?.value.isPlaying == true ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Fullscreen button
                        FloatingActionButton.small(
                          heroTag: "embedded_fullscreen",
                          onPressed: _openFullscreenPlayer,
                          child: const Icon(Icons.fullscreen),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Player'),
        actions: [
          IconButton(
            icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
      body: Center(
        child: _controller != null && _isInitialized
            ? AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: _controller != null && _isInitialized
          ? FloatingActionButton(
              heroTag: "main_play_pause",
              onPressed: () {
                if (_controller != null) {
                  setState(() {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  });
                }
              },
              child: Icon(
                _controller?.value.isPlaying == true ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}

class FullscreenPlayerScreen extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final VideoPlayerController? controller;

  const FullscreenPlayerScreen({
    super.key,
    required this.url,
    required this.headers,
    this.controller,
  });

  @override
  State<FullscreenPlayerScreen> createState() => _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends State<FullscreenPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
    _startHideControlsTimer();
  }

  Future<void> _initializeController() async {
    // Use existing controller if available, otherwise create new one
    if (widget.controller != null && widget.controller!.value.isInitialized) {
      _controller = widget.controller;
      setState(() {
        _isInitialized = true;
        _isPlaying = _controller!.value.isPlaying;
      });
    } else {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: widget.headers,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );

      try {
        await _controller!.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception('Video initialization timeout');
          },
        );

        if (mounted) {
          setState(() {
            _isInitialized = true;
            _isPlaying = false;
          });
          _controller!.play();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isInitialized = false;
          });
        }
      }
    }
  }

  void _startHideControlsTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showControls) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _togglePlayPause() {
    if (_controller != null) {
      setState(() {
        _isPlaying = !_isPlaying;
      });
      if (_isPlaying) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
    }
  }

  @override
  void dispose() {
    // Don't dispose controller here as it might be shared
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video player
            Center(
              child: _controller != null && _isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            
            // Top controls
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.only(
                    top: 50,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Bottom controls
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 48,
                        ),
                        onPressed: _togglePlayPause,
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
