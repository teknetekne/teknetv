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
  
  // TV Navigation state
  int _focusedControlIndex = 0; // 0: play/pause, 1: refresh, 2: prev, 3: next, 4: channel list
  int _focusedChannelIndex = 0; // For channel list navigation
  final List<String> _controlIds = ['play_pause', 'refresh', 'prev', 'next', 'channel_list'];
  final GlobalKey<_PlayerScreenState> _playerKey = GlobalKey<_PlayerScreenState>();
  final ScrollController _channelListScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _uiHideTimer?.cancel();
    _focusNode.dispose();
    _channelListScrollController.dispose();
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

  // TV Navigation methods
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (_isChannelListOpen) {
        _handleChannelListNavigation(event);
      } else {
        _handleMainNavigation(event);
      }
    }
  }

  void _handleMainNavigation(KeyDownEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        setState(() {
          _focusedControlIndex = (_focusedControlIndex - 1 + _controlIds.length) % _controlIds.length;
          _showUiOverlays = true;
        });
        _scheduleHideOverlays();
        break;
      case LogicalKeyboardKey.arrowRight:
        setState(() {
          _focusedControlIndex = (_focusedControlIndex + 1) % _controlIds.length;
          _showUiOverlays = true;
        });
        _scheduleHideOverlays();
        break;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        _executeFocusedControl();
        break;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.backspace:
        setState(() {
          _showUiOverlays = !_showUiOverlays;
        });
        if (_showUiOverlays) {
          _scheduleHideOverlays();
        }
        break;
      case LogicalKeyboardKey.pageUp:
      case LogicalKeyboardKey.audioVolumeUp:
        // CH+ tuşu - sonraki kanal
        _goNextChannel();
        break;
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.audioVolumeDown:
        // CH- tuşu - önceki kanal
        _goPrevChannel();
        break;
    }
  }

  void _handleChannelListNavigation(KeyDownEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        setState(() {
          _focusedChannelIndex = (_focusedChannelIndex - 1 + channels.length) % channels.length;
        });
        _scrollToFocusedChannel();
        break;
      case LogicalKeyboardKey.arrowDown:
        setState(() {
          _focusedChannelIndex = (_focusedChannelIndex + 1) % channels.length;
        });
        _scrollToFocusedChannel();
        break;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        if (_focusedChannelIndex < channels.length) {
          _setCurrentChannel(channels[_focusedChannelIndex]);
          // Kanal listesi açık kalsın, sadece UI overlay'i gizle
          _scheduleHideOverlays();
        }
        break;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.backspace:
        setState(() {
          _isChannelListOpen = false;
        });
        _scheduleHideOverlays();
        break;
    }
  }

  void _executeFocusedControl() {
    switch (_controlIds[_focusedControlIndex]) {
      case 'play_pause':
        // Play/pause logic will be handled by calling PlayerScreen method
        _playerKey.currentState?.togglePlayPause();
        break;
      case 'refresh':
        _refreshAll();
        break;
      case 'prev':
        _goPrevChannel();
        break;
      case 'next':
        _goNextChannel();
        break;
      case 'channel_list':
        setState(() {
          _isChannelListOpen = !_isChannelListOpen;
          if (_isChannelListOpen) {
            _focusedChannelIndex = channels.indexWhere(
              (c) => _currentChannel != null && c['url'] == _currentChannel!['url']
            );
            if (_focusedChannelIndex == -1) _focusedChannelIndex = 0;
          }
        });
        if (_isChannelListOpen) {
          setState(() {
            _showUiOverlays = true;
          });
        } else {
          _scheduleHideOverlays();
        }
        break;
    }
  }

  void _scrollToFocusedChannel() {
    if (_channelListScrollController.hasClients) {
      const double itemHeight = 50.0; // Her kanal item'ının yüksekliği
      final double targetOffset = _focusedChannelIndex * itemHeight;
      final double maxScrollExtent = _channelListScrollController.position.maxScrollExtent;
      final double viewportHeight = _channelListScrollController.position.viewportDimension;
      
      // Eğer hedef pozisyon viewport'un dışındaysa scroll yap
      if (targetOffset < _channelListScrollController.offset) {
        // Yukarı scroll
        _channelListScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      } else if (targetOffset + itemHeight > _channelListScrollController.offset + viewportHeight - 60) {
        // Aşağı scroll - alt padding için 60px ekstra alan bırak
        _channelListScrollController.animateTo(
          (targetOffset + itemHeight - viewportHeight + 60).clamp(0.0, maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Widget _buildLoadingControls() {
    return Positioned(
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
                  _buildControlButton(
                    index: 0,
                    icon: Icons.play_arrow,
                    onPressed: () {
                      // Loading sırasında play/pause çalışmaz
                    },
                    heroTag: "loading_play_pause",
                  ),
                  const SizedBox(width: 8),
                  // Refresh (next to pause)
                  _buildControlButton(
                    index: 1,
                    icon: Icons.refresh,
                    onPressed: _refreshAll,
                    heroTag: "loading_refresh",
                  ),
                  const SizedBox(width: 8),
                  // Prev channel
                  _buildControlButton(
                    index: 2,
                    icon: Icons.skip_previous,
                    onPressed: _goPrevChannel,
                    heroTag: "loading_prev",
                  ),
                  const SizedBox(width: 8),
                  // Next channel
                  _buildControlButton(
                    index: 3,
                    icon: Icons.skip_next,
                    onPressed: _goNextChannel,
                    heroTag: "loading_next",
                  ),
                  const Spacer(),
                  // Channel list (far right)
                  _buildControlButton(
                    index: 4,
                    icon: Icons.list,
                    onPressed: () {
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
                    heroTag: "loading_toggle_list",
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required int index,
    required IconData icon,
    required VoidCallback? onPressed,
    required String heroTag,
  }) {
    final isFocused = _focusedControlIndex == index;
    return FloatingActionButton.small(
      heroTag: heroTag,
      elevation: 0,
      backgroundColor: isFocused ? Colors.yellow : null,
      onPressed: onPressed,
      child: Icon(
        icon,
        color: isFocused ? const Color(0xFFA855F7) : Colors.white70,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: Scaffold(
      body: Stack(
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
                        ? Stack(
                            children: [
                              const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 8),
                                    Text('Loading channel...', style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                              // Loading sırasında sadece butonları göster (video player değil)
                              if (_currentChannel != null)
                                _buildLoadingControls(),
                            ],
                          )
                        : PlayerScreen(
                            key: _playerKey,
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
                            focusedControlIndex: _focusedControlIndex,
                            onPlayPause: () {
                              // This will be handled by the player screen itself
                            },
                          ),
                      ),
                    ),
                  ),
                ),

                // Top-left watermark/title (auto-hide, responsive)
                if (_showUiOverlays || _isPlayerLoading)
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
                        controller: _channelListScrollController,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 60),
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
                          final isFocused = _focusedChannelIndex == index;
                          return SizedBox(
                            height: 50,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isFocused 
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : isCurrentChannel ? const Color(0x33A855F7) : null,
                                  border: Border(
                                    left: BorderSide(
                                      color: isCurrentChannel ? const Color(0xFFA855F7) : Colors.transparent,
                                      width: 3,
                                    ),
                                    right: BorderSide(
                                      color: isFocused ? Colors.white : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                  child: Material(
                                  color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        _setCurrentChannel(channel);
                                        // Kanal listesi açık kalsın, sadece UI overlay'i gizle
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
                                              color: isFocused 
                                                ? Colors.white
                                                : isCurrentChannel ? const Color(0xFFA855F7) : Colors.white,
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

                // Loading overlay (when channels are being loaded)
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.8),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Loading channels...', 
                              style: TextStyle(
                                fontSize: 16, 
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
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
  final int focusedControlIndex;
  final VoidCallback? onPlayPause;

  const PlayerScreen({
    super.key, 
    required this.url, 
    required this.headers,
    this.onRefresh,
    this.onToggleChannelList,
    this.showControls = false,
    this.onPrevChannel,
    this.onNextChannel,
    required this.focusedControlIndex,
    this.onPlayPause,
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

  void togglePlayPause() {
    if (_controller != null) {
      setState(() {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
      });
    }
  }

  Widget _buildControlButton({
    required int index,
    required IconData icon,
    required VoidCallback? onPressed,
    required String heroTag,
  }) {
    final isFocused = widget.focusedControlIndex == index;
    return FloatingActionButton.small(
      heroTag: heroTag,
      elevation: 0,
      backgroundColor: isFocused ? Colors.yellow : null,
      onPressed: onPressed,
      child: Icon(
        icon,
        color: isFocused ? const Color(0xFFA855F7) : Colors.white70,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        width: double.infinity,
        height: _isInitialized ? 200 : double.infinity,
        color: Colors.black,
        child: Stack(
          children: [
            // Video player or loading indicator
            _isInitialized
                ? Center(
                    child: _controller != null && _isInitialized
                        ? AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          )
                        : const CircularProgressIndicator(),
                  )
                : const Center(child: CircularProgressIndicator()),
            
            // Controls overlay - always show when showControls is true or when not initialized
            if (widget.showControls || !_isInitialized)
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
                              _buildControlButton(
                                index: 0,
                                icon: _controller?.value.isPlaying == true ? Icons.pause : Icons.play_arrow,
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
                                heroTag: "embedded_play_pause",
                              ),
                              const SizedBox(width: 8),
                    // Refresh (next to pause)
                              _buildControlButton(
                                index: 1,
                                icon: Icons.refresh,
                                onPressed: widget.onRefresh,
                                heroTag: "embedded_refresh",
                              ),
                              const SizedBox(width: 8),
                    // Prev channel
                              _buildControlButton(
                                index: 2,
                                icon: Icons.skip_previous,
                                onPressed: widget.onPrevChannel,
                                heroTag: "embedded_prev",
                              ),
                              const SizedBox(width: 8),
                    // Next channel
                              _buildControlButton(
                                index: 3,
                                icon: Icons.skip_next,
                                onPressed: widget.onNextChannel,
                                heroTag: "embedded_next",
                              ),
                    const Spacer(),
                    // Channel list (far right)
                              _buildControlButton(
                                index: 4,
                                icon: Icons.list,
                                onPressed: widget.onToggleChannelList,
                                heroTag: "embedded_toggle_list",
                              ),
                            ],
                          ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      );
  }
}

// TV-specific focusable FAB removed; reverted to standard FABs

// Removed old fullscreen page implementation; now fullscreen is same-page overlay