import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/featured_albums_service.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';

class FeaturedAlbumsSettingsScreen extends StatefulWidget {
  const FeaturedAlbumsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<FeaturedAlbumsSettingsScreen> createState() =>
      _FeaturedAlbumsSettingsScreenState();
}

class _FeaturedAlbumsSettingsScreenState
    extends State<FeaturedAlbumsSettingsScreen> {
  late Future<FeaturedAlbumsConfig> _configFuture;
  late Future<List<Album>> _allAlbumsFuture;
  FeaturedAlbumsConfig? _currentConfig;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _configFuture = FeaturedAlbumsService.instance.loadConfig();
    _allAlbumsFuture = AlbumService.instance.getAllAlbums();
  }

  Future<void> _saveConfig(FeaturedAlbumsConfig config) async {
    await FeaturedAlbumsService.instance.saveConfig(config);
    setState(() {
      _currentConfig = config;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait([_configFuture, _allAlbumsFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('No data available'));
          }

          _currentConfig ??= snapshot.data![0] as FeaturedAlbumsConfig;
          final allAlbums = snapshot.data![1] as List<Album>;

          return _buildSettingsList(context, _currentConfig!, allAlbums);
        },
      ),
    );
  }

  Widget _buildSettingsList(
    BuildContext context,
    FeaturedAlbumsConfig config,
    List<Album> allAlbums,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Show Featured Albums in Gallery Hub'),
          value: config.showInGalleryHub,
          onChanged: (value) {
            final newConfig = FeaturedAlbumsConfig.fromJson(config.toJson())
              ..showInGalleryHub = value;
            _saveConfig(newConfig);
          },
        ),
        SwitchListTile(
          title: const Text('Auto-select recent albums'),
          subtitle: const Text('Automatically feature your most recent albums'),
          value: config.autoSelectRecent,
          onChanged: (value) {
            final newConfig = FeaturedAlbumsConfig.fromJson(config.toJson())
              ..autoSelectRecent = value;
            _saveConfig(newConfig);
          },
        ),
        ListTile(
          title: const Text('Max featured albums'),
          trailing: CbSelect.fromValues<int>(
            values: const [2, 4, 6, 8, 10],
            value: config.maxFeaturedAlbums,
            labelBuilder: (value) => value.toString(),
            onChanged: (value) {
              final newConfig = FeaturedAlbumsConfig.fromJson(config.toJson())
                ..maxFeaturedAlbums = value;
              _saveConfig(newConfig);
            },
          ),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text('Manually select featured albums',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...allAlbums.map((album) {
          return CheckboxListTile(
            title: Text(album.name),
            subtitle: Text(album.description ?? ''),
            value: config.featuredAlbumIds.contains(album.id),
            onChanged: (value) {
              final newConfig = FeaturedAlbumsConfig.fromJson(config.toJson());
              if (value == true) {
                newConfig.featuredAlbumIds.add(album.id);
              } else {
                newConfig.featuredAlbumIds.remove(album.id);
              }
              _saveConfig(newConfig);
            },
          );
        }),
      ],
    );
  }
}
