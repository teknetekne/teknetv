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
  // Removed unused periodic refresh timer
  String? _cachedM3UData;
  final FocusNode _focusNode = FocusNode();
  bool _isChannelListOpen = false;
  bool _showUiOverlays = true;
  Timer? _uiHideTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _uiHideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleOverlays() {
    setState(() {
      _showUiOverlays = !_showUiOverlays;
    });
    if (_showUiOverlays) {
      _scheduleHideOverlays();
    }
  }

  void _scheduleHideOverlays() {
    _uiHideTimer?.cancel();
    _uiHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isChannelListOpen) {
        setState(() {
          _showUiOverlays = false;
        });
      }
    });
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
        content: Text('Yenileniyor: mevcut kanal yeniden başlatılacak...'),
        duration: Duration(seconds: 2),
      ),
    );

    // Keep reference to currently playing channel (by URL preferred)
    final String? previousUrl = _currentChannel != null ? _currentChannel!['url'] as String? : null;
    final String? previousTitle = _currentChannel != null ? _currentChannel!['title'] as String? : null;

    // Temporarily clear player to force full re-initialization
    setState(() {
      _currentChannel = null;
      _isPlayerLoading = false;
    });

    try {
      // Fetch fresh data with cache clearing
      await fetchM3U(forceRefresh: true);

      if (!mounted) return;

      // Try to find the same channel again in refreshed list
      Map<String, dynamic>? nextChannel;
      if (previousUrl != null) {
        nextChannel = channels.firstWhere(
          (c) => c['url'] == previousUrl,
          orElse: () => <String, dynamic>{},
        );
        if (nextChannel.isEmpty) nextChannel = null;
      }

      // Fallback by title if URL match not found
      if (nextChannel == null && previousTitle != null) {
        nextChannel = channels.firstWhere(
          (c) => (c['title'] as String?)?.trim() == previousTitle.trim(),
          orElse: () => <String, dynamic>{},
        );
        if (nextChannel.isEmpty) nextChannel = null;
      }

      // Final fallback to first channel
      nextChannel ??= channels.isNotEmpty ? channels.first : null;

      if (nextChannel != null) {
        // Small delay so widget tree disposes previous player fully
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            _setCurrentChannel(nextChannel!);
          }
        });
      } else {
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

  void _goPrevChannel() {
    if (_currentChannel == null || channels.isEmpty) return;
    final int currentIndex = channels.indexWhere((c) => c['url'] == _currentChannel!['url']);
    if (currentIndex <= 0) {
      _setCurrentChannel(channels.last);
    } else {
      _setCurrentChannel(channels[currentIndex - 1]);
    }
    _showUiOverlays = true;
    _scheduleHideOverlays();
  }

  void _goNextChannel() {
    if (_currentChannel == null || channels.isEmpty) return;
    final int currentIndex = channels.indexWhere((c) => c['url'] == _currentChannel!['url']);
    if (currentIndex < 0 || currentIndex >= channels.length - 1) {
      _setCurrentChannel(channels.first);
    } else {
      _setCurrentChannel(channels[currentIndex + 1]);
    }
    _showUiOverlays = true;
    _scheduleHideOverlays();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => KeyEventResult.ignored,
      child: Scaffold(
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
          : Stack(
              children: [
                // Fullscreen video background
                Positioned.fill(
                  child: MouseRegion(
                    onHover: (_) {
                      if (!_showUiOverlays) {
                        setState(() {
                          _showUiOverlays = true;
                        });
                      }
                      _scheduleHideOverlays();
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleOverlays,
                      onDoubleTap: _toggleOverlays,
                      child: Container(
                    color: Colors.black,
                    child: _currentChannel == null || _isPlayerLoading
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
                            onRefresh: _refreshAll,
                            onToggleChannelList: () {
                              setState(() {
                                _isChannelListOpen = !_isChannelListOpen;
                              });
                              if (_isChannelListOpen) {
                                setState(() {
                                  _showUiOverlays = true;
                                });
                              } else {
                                _scheduleHideOverlays();
                              }
                            },
                            showControls: _showUiOverlays,
                            onPrevChannel: _goPrevChannel,
                            onNextChannel: _goNextChannel,
                          ),
                      ),
                    ),
                  ),
                ),

                // Top-left watermark/title (auto-hide, responsive)
                if (_showUiOverlays)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: SafeArea(
                      top: true,
                      left: true,
                      right: false,
                      bottom: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "tekne'nin lig tv hayratı",
                                softWrap: true,
                                overflow: TextOverflow.fade,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "hayır dualarınızı eksik etmeyiniz",
                                softWrap: true,
                                overflow: TextOverflow.fade,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: MediaQuery.of(context).size.width < 360 ? 10 : 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Toggle button for channel list
                  // Top-right toggle removed; moved into player controls

                // Tap-outside-to-close area (when list is open)
                if (_isChannelListOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _isChannelListOpen = false;
                          _scheduleHideOverlays();
                        });
                      },
                      child: const SizedBox.shrink(),
                    ),
                  ),

                // Channel list overlay panel
                if (_isChannelListOpen)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 360,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.8),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        physics: const BouncingScrollPhysics(),
                        itemCount: channels.length,
                        separatorBuilder: (context, index) => const Divider(
                          color: Colors.white12,
                          height: 1,
                          thickness: 1,
                        ),
                        itemBuilder: (context, index) {
                          final channel = channels[index];
                          final isCurrentChannel = _currentChannel != null && _currentChannel!['url'] == channel['url'];
                          return SizedBox(
                            height: 50,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isCurrentChannel ? const Color(0x33A855F7) : null, // light purple bg
                                  border: Border(
                                    left: BorderSide(
                                      color: isCurrentChannel ? const Color(0xFFA855F7) : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                  child: Material(
                                  color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        _setCurrentChannel(channel);
                                        _scheduleHideOverlays();
                                      },
                                      hoverColor: Colors.white10,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            channel['title'] ?? 'Unknown',
                                            maxLines: 1,
                                            overflow: TextOverflow.fade,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isCurrentChannel ? const Color(0xFFA855F7) : Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleChannelList;
  final bool showControls;
  final VoidCallback? onPrevChannel;
  final VoidCallback? onNextChannel;

  const PlayerScreen({
    super.key, 
    required this.url, 
    required this.headers,
    this.onRefresh,
    this.onToggleChannelList,
    this.showControls = false,
    this.onPrevChannel,
    this.onNextChannel,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
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
        
        // Auto-play with small delay
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _controller != null) {
            _controller!.play();
          }
        });
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

  @override
  Widget build(BuildContext context) {
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
                if (widget.showControls)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      left: true,
                      right: true,
                      child: Builder(
                        builder: (context) {
                          final double width = MediaQuery.of(context).size.width;
                          final double pad = (width * 0.05).clamp(8.0, 16.0).toDouble();
                          return Padding(
                            padding: EdgeInsets.fromLTRB(pad, 0, pad, 6),
                            child: Row(
                                children: [
                                  // Play/Pause (leftmost)
                                  FloatingActionButton.small(
                          heroTag: "embedded_play_pause",
                                    elevation: 0,
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
                                    child: Icon(_controller?.value.isPlaying == true ? Icons.pause : Icons.play_arrow),
                        ),
                                  const SizedBox(width: 8),
                        // Refresh (next to pause)
                                  FloatingActionButton.small(
                          heroTag: "embedded_refresh",
                                    elevation: 0,
                                    onPressed: widget.onRefresh,
                                    child: const Icon(Icons.refresh),
                        ),
                                  const SizedBox(width: 8),
                        // Prev channel
                                  FloatingActionButton.small(
                          heroTag: "embedded_prev",
                                    elevation: 0,
                                    onPressed: widget.onPrevChannel,
                                    child: const Icon(Icons.skip_previous),
                        ),
                                  const SizedBox(width: 8),
                        // Next channel
                                  FloatingActionButton.small(
                          heroTag: "embedded_next",
                                    elevation: 0,
                                    onPressed: widget.onNextChannel,
                                    child: const Icon(Icons.skip_next),
                        ),
                        const Spacer(),
                        // Channel list (far right)
                                  FloatingActionButton.small(
                          heroTag: "embedded_toggle_list",
                                    elevation: 0,
                                    onPressed: widget.onToggleChannelList,
                                    child: const Icon(Icons.list),
                                  ),
                                ],
                              ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      );
  }
}

// TV-specific focusable FAB removed; reverted to standard FABs

// Removed old fullscreen page implementation; now fullscreen is same-page overlay
