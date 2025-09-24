import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:ui' as ui;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "tekne'nin lig tv hayratı - Android TV",
      theme: ThemeData.dark().copyWith(
        // TV-optimized theme
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
          bodySmall: TextStyle(fontSize: 12),
        ),
        // TV-optimized button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          largeSizeConstraints: BoxConstraints(minWidth: 72, minHeight: 72),
        ),
      ),
      home: const TVChannelListScreen(),
      debugShowCheckedModeBanner: false,
      debugShowMaterialGrid: false,
    );
  }
}

class TVChannelListScreen extends StatefulWidget {
  const TVChannelListScreen({super.key});

  @override
  State<TVChannelListScreen> createState() => _TVChannelListScreenState();
}

class _TVChannelListScreenState extends State<TVChannelListScreen> {
  List<Map<String, dynamic>> channels = [];
  bool _isLoading = true;
  Map<String, dynamic>? _currentChannel;
  bool _isPlayerLoading = false;
  String? _cachedM3UData;
  final FocusNode _mainFocusNode = FocusNode();
  final FocusNode _channelListFocusNode = FocusNode();
  bool _isChannelListOpen = false;
  bool _showUiOverlays = true;
  Timer? _uiHideTimer;
  int _selectedChannelIndex = 0;
  bool _isFullscreen = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Set initial focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _uiHideTimer?.cancel();
    _mainFocusNode.dispose();
    _channelListFocusNode.dispose();
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
    _uiHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isChannelListOpen) {
        setState(() {
          _showUiOverlays = false;
        });
      }
    });
  }

  // TV Remote Key Handling
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          _handleUpKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _handleDownKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowLeft:
          _handleLeftKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          _handleRightKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
          _handleSelectKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _handleBackKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.mediaPlayPause:
          _handlePlayPauseKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.mediaStop:
          _handleStopKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.channelUp:
          _goNextChannel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.channelDown:
          _goPrevChannel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.function('RED'):
          _handleRedKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.function('GREEN'):
          _handleGreenKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.function('YELLOW'):
          _handleYellowKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.function('BLUE'):
          _handleBlueKey();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.f1:
          _refreshAll();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.f2:
          _toggleFullscreen();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.f3:
          _showChannelInfo();
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _handleUpKey() {
    if (_isChannelListOpen && channels.isNotEmpty) {
      setState(() {
        _selectedChannelIndex = (_selectedChannelIndex - 1 + channels.length) % channels.length;
      });
    }
  }

  void _handleDownKey() {
    if (_isChannelListOpen && channels.isNotEmpty) {
      setState(() {
        _selectedChannelIndex = (_selectedChannelIndex + 1) % channels.length;
      });
    }
  }

  void _handleLeftKey() {
    _goPrevChannel();
  }

  void _handleRightKey() {
    _goNextChannel();
  }

  void _handleSelectKey() {
    if (_isChannelListOpen && channels.isNotEmpty) {
      _setCurrentChannel(channels[_selectedChannelIndex]);
      setState(() {
        _isChannelListOpen = false;
      });
      _scheduleHideOverlays();
    } else {
      _toggleOverlays();
    }
  }

  void _handleBackKey() {
    if (_isChannelListOpen) {
      setState(() {
        _isChannelListOpen = false;
      });
      _scheduleHideOverlays();
    } else {
      _toggleOverlays();
    }
  }

  void _handlePlayPauseKey() {
    _toggleOverlays();
  }

  void _handleStopKey() {
    // Could implement stop functionality
  }

  void _handleRedKey() {
    // Red button - Refresh channels
    _refreshAll();
  }

  void _handleGreenKey() {
    // Green button - Toggle fullscreen
    _toggleFullscreen();
  }

  void _handleYellowKey() {
    // Yellow button - Toggle channel list
    setState(() {
      _isChannelListOpen = !_isChannelListOpen;
    });
    if (_isChannelListOpen) {
      setState(() {
        _showUiOverlays = true;
      });
      _channelListFocusNode.requestFocus();
    } else {
      _mainFocusNode.requestFocus();
      _scheduleHideOverlays();
    }
  }

  void _handleBlueKey() {
    // Blue button - Show channel info
    _showChannelInfo();
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFullscreen ? 'Tam Ekran Açıldı' : 'Tam Ekran Kapatıldı'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showChannelInfo() {
    if (_currentChannel != null && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.9),
          title: Text(
            'Kanal Bilgisi',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Kanal Adı:', _currentChannel!['title'] ?? 'Bilinmeyen'),
              const SizedBox(height: 8),
              _buildInfoRow('Kanal Numarası:', '${_selectedChannelIndex + 1}'),
              const SizedBox(height: 8),
              _buildInfoRow('Toplam Kanal:', '${channels.length}'),
              const SizedBox(height: 8),
              _buildInfoRow('Durum:', _isPlayerLoading ? 'Yükleniyor' : 'Oynatılıyor'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Kapat',
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
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
      // Update selected index when channel changes
      _selectedChannelIndex = channels.indexWhere((c) => c['url'] == channel['url']);
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
      focusNode: _mainFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Kanal listesi yükleniyor...',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  // Fullscreen video background
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: _currentChannel == null || _isPlayerLoading
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    strokeWidth: 3,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Kanal yükleniyor...',
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : TVPlayerScreen(
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
                                  _channelListFocusNode.requestFocus();
                                } else {
                                  _mainFocusNode.requestFocus();
                                  _scheduleHideOverlays();
                                }
                              },
                              showControls: _showUiOverlays,
                              onPrevChannel: _goPrevChannel,
                              onNextChannel: _goNextChannel,
                            ),
                    ),
                  ),

                  // TV-optimized watermark/title
                  if (_showUiOverlays)
                    Positioned(
                      top: 24,
                      left: 24,
                      child: SafeArea(
                        top: true,
                        left: true,
                        right: false,
                        bottom: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "tekne'nin lig tv hayratı - Android TV",
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "hayır dualarınızı eksik etmeyiniz",
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // TV Remote Instructions
                  if (_showUiOverlays)
                    Positioned(
                      bottom: 24,
                      right: 24,
                      child: SafeArea(
                        bottom: true,
                        right: true,
                        left: false,
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'TV Kumandası Kısayolları:',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildRemoteInstruction('↑↓', 'Kanal Listesi'),
                              _buildRemoteInstruction('←→', 'Kanal Değiştir'),
                              _buildRemoteInstruction('OK/Enter', 'Seç/Yardım'),
                              _buildRemoteInstruction('Back/Esc', 'Geri/Çıkış'),
                              _buildRemoteInstruction('Play/Pause', 'Kontrolleri Göster/Gizle'),
                              _buildRemoteInstruction('CH+/CH-', 'Sonraki/Önceki Kanal'),
                              _buildRemoteInstruction('Kırmızı', 'Kanal Listesi Yenile'),
                              _buildRemoteInstruction('Yeşil', 'Tam Ekran Aç/Kapat'),
                              _buildRemoteInstruction('Sarı', 'Kanal Listesi Aç/Kapat'),
                              _buildRemoteInstruction('Mavi', 'Kanal Bilgisi'),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // TV-optimized Channel list overlay panel
                  if (_isChannelListOpen)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 480, // Wider for TV
                      child: Focus(
                        focusNode: _channelListFocusNode,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.9),
                            border: Border(
                              left: BorderSide(
                                color: Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Channel list header
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.white.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'Kanal Listesi',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${_selectedChannelIndex + 1}/${channels.length}',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Channel list
                              Expanded(
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: channels.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                                  itemBuilder: (context, index) {
                                    final channel = channels[index];
                                    final isCurrentChannel = _currentChannel != null && _currentChannel!['url'] == channel['url'];
                                    final isSelected = index == _selectedChannelIndex;
                                    
                                    return Container(
                                      height: 64, // Taller for TV
                                      decoration: BoxDecoration(
                                        color: isSelected 
                                            ? Colors.blue.withOpacity(0.3)
                                            : isCurrentChannel 
                                                ? Colors.purple.withOpacity(0.2)
                                                : null,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected 
                                              ? Colors.blue
                                              : isCurrentChannel 
                                                  ? Colors.purple
                                                  : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            _setCurrentChannel(channel);
                                            setState(() {
                                              _isChannelListOpen = false;
                                            });
                                            _mainFocusNode.requestFocus();
                                            _scheduleHideOverlays();
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            child: Row(
                                              children: [
                                                // Channel number/icon
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: isCurrentChannel 
                                                        ? Colors.purple 
                                                        : Colors.white.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      '${index + 1}',
                                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                // Channel name
                                                Expanded(
                                                  child: Text(
                                                    channel['title'] ?? 'Bilinmeyen Kanal',
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                      color: Colors.white,
                                                      fontWeight: isCurrentChannel 
                                                          ? FontWeight.bold 
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                // Current channel indicator
                                                if (isCurrentChannel)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.purple,
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Text(
                                                      'ŞU AN',
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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

  Widget _buildRemoteInstruction(String key, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              key,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TVPlayerScreen extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleChannelList;
  final bool showControls;
  final VoidCallback? onPrevChannel;
  final VoidCallback? onNextChannel;

  const TVPlayerScreen({
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
  State<TVPlayerScreen> createState() => _TVPlayerScreenState();
}

class _TVPlayerScreenState extends State<TVPlayerScreen> {
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
      height: double.infinity,
      color: Colors.black,
      child: _isInitialized
          ? Stack(
              children: [
                // Fullscreen video
                Center(
                  child: _controller != null && _isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        )
                      : const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 3,
                        ),
                ),
                
                // TV-optimized Controls overlay
                if (widget.showControls)
                  Positioned(
                    bottom: 32,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: true,
                      left: true,
                      right: true,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Play/Pause
                            _buildTVControlButton(
                              icon: _controller?.value.isPlaying == true 
                                  ? Icons.pause 
                                  : Icons.play_arrow,
                              label: _controller?.value.isPlaying == true 
                                  ? 'Duraklat' 
                                  : 'Oynat',
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
                            ),
                            
                            // Previous Channel
                            _buildTVControlButton(
                              icon: Icons.skip_previous,
                              label: 'Önceki Kanal',
                              onPressed: widget.onPrevChannel,
                            ),
                            
                            // Next Channel
                            _buildTVControlButton(
                              icon: Icons.skip_next,
                              label: 'Sonraki Kanal',
                              onPressed: widget.onNextChannel,
                            ),
                            
                            // Refresh
                            _buildTVControlButton(
                              icon: Icons.refresh,
                              label: 'Yenile',
                              onPressed: widget.onRefresh,
                            ),
                            
                            // Channel List
                            _buildTVControlButton(
                              icon: Icons.list,
                              label: 'Kanal Listesi',
                              onPressed: widget.onToggleChannelList,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ),
    );
  }

  Widget _buildTVControlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(32),
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// TV-specific focusable FAB removed; reverted to standard FABs

// Removed old fullscreen page implementation; now fullscreen is same-page overlay
