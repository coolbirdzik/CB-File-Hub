import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/languages/app_localizations.dart';
import '../../services/torrent/torrent_launch_request.dart';
import '../tab_manager/core/tab_manager.dart';

/// Routes file-browser opens through the same queued dialog as OS magnets.
class TorrentOpenActions {
  static bool tryOpen(BuildContext context, String source) {
    if (!TorrentLaunchRequest.isSource(source)) return false;
    context.read<TabManagerBloc>().add(
      AddTab(
        path: TorrentLaunchRequest.pathFor(source),
        name: AppLocalizations.of(context)?.torrents ?? 'Torrents',
      ),
    );
    return true;
  }
}
